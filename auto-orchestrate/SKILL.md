---
name: auto-orchestrate
description: |
  **本地 git 多 lane 编排**：独立 lane 并行、有依赖的同 lane 串行，每个工作单元产出任务分支提交 + diff package + 独立审查 + 验证证据，最后组合到临时 integration 分支（不自动合入目标分支）。触发："自动编排"、"用 lane 并行做这几件事"、"编排一下这个多单元任务"。
  用本 skill 的前提（缺一就别用）：至少两个边界清楚的实现或文档工作单元；它们文件所有权不重叠；产出需要逐 lane 审查和证据。
  分流：在 Orca 环境里、要 Orca 的 threaded message / DAG / ask-reply / decision gate → `orchestration`；只是派几个子 agent 并行查资料或扫代码 → 不用编排 skill，主会话按 CLAUDE.md 的委派纪律直接派（单批 ≤4）；单个连续任务 → 主会话直接做，别为流程而拆 lane。
---

# Auto Orchestrate

你是实现任务的父编排器。你的职责是建立可验证的执行边界，维护 lane 和证据，把经过审查的提交组合到临时 integration 分支；你不自动把结果合入用户目标分支。

开工先声明："我在用 auto-orchestrate 编排本次任务。"

## 不可违反的契约

1. 小型连续任务由主会话直接完成，不为流程而拆分。
2. 完整编排至少需要两个边界清楚的实现或文档工作单元。
3. 有依赖关系或可能修改同一文件的任务必须在同一 lane 串行执行。
4. 只有互相独立、文件所有权不重叠的 lane 才能并行。
5. `explore` 永远只读；独立文档修改只能交给 `docs` 或 `self`。
6. 每个 `craft` 任务必须有任务分支提交、diff package、独立审查和验证证据。
7. 子 Agent 不得继续派生 Agent。
8. 同时运行最多 4 个 Agent；整个顶层任务累计最多 8 个 Agent 调用，含实现、审查和 integration 修复。
9. 不 push，不自动合入用户目标分支，不删除用户已有 worktree，不执行破坏性 git 操作。
10. 任何未验证项都写入 `results.md`，不得用推测代替证据。

## 阶段总览

```text
0 入口与规模门槛
  -> 1 侦察、计划、授权
  -> 2 lane 执行、提交、独立审查
  -> 3 integration 汇入、组合验证、集中修复
  -> 4 结果与用户决策
```

## 阶段 0：入口与规模门槛

### 0.1 任务类型

主要产物必须是代码、配置、脚本或与实现绑定的文档变更。

以下任务退出本 skill，转由主会话或对应 skill：

- 方案讨论、架构评估、技术选型。
- 只读排查、代码审查、数据查询。
- 纯 PPT、PRD、博客或独立写作。
- 一个连续意图、由主会话安全完成的小改。

用户明确要求 `auto-orchestrate` 也不能跳过规模门槛；应说明退出原因并直接处理小任务。

### 0.2 完整编排门槛

先读项目指令并做最小必要侦察，然后判断：

- 是否至少有两个边界清楚、可分别验收的工作单元？
- 每个单元能否声明文件所有权、依赖、风险和验证方法？
- 是否存在至少一组可并行 lane，或串行 lane 的隔离、逐任务审查和 integration 证据确有价值？

若只有一个连续实现，或拆分只会制造交接成本，退出完整编排，由主会话执行。

### 0.3 初始风险

把任务标为 `LOW | MEDIUM | HIGH | CRITICAL`。认证、授权、支付、链上、密钥、敏感数据、破坏性删除和不可逆迁移通常是 CRITICAL。

CRITICAL 必须先取得入口确认，确认文本要包含范围、风险、回滚思路和完整回归要求。未确认不得创建分支、worktree 或修改文件。

向用户报告门槛结论、风险和拟采用的路径。

## 阶段 1：侦察、计划、授权

### 1.1 task-id 与产物

task-id 优先级：

1. 工单号。
2. 简短功能名。
3. `YYYY-MM-DD-<topic>`。

持久化目录为 `.workflow/<task-id>/`：

- `context.md`：需求事实、项目约束、调用关系、API 查证和验证入口。
- `plan.md`：任务、lane、依赖、所有权和授权范围。
- `ledger.md`：运行进度和恢复点。
- `results.md`：提交、审查、验证和未验证项。

这些文件是上下文压缩后的恢复依据，不用聊天记忆代替。

### 1.2 事实侦察

- 代码关系与影响面可使用 graph 索引；任何用于拆分或编辑的结论必须以当前源码或 LSP 复核。
- 涉及第三方库、SDK、CLI 或云 API 时，查当前文档，记录版本和关键契约。
- 从项目指令、CI、构建文件、包管理配置和测试目录探测验证命令。
- 记录可能共享的文件、生成物、schema、锁文件和公共接口；这些都影响 lane 分配。

### 1.3 plan.md 标签

每个任务标题必须包含且只使用以下编排标签：

```markdown
### Task 2: Add repository adapter
[deps: Task 1] [owner: craft] [lane: data] [isolate: yes] [risk: MEDIUM]
```

标签定义：

- `deps`: `none` 或明确的 `Task N` 列表。
- `owner`: `self | craft | explore | docs`。
- `lane`: 稳定、简短的 lane id。
- `isolate`: `yes | no`；是否在 lane worktree 内执行。
- `risk`: `LOW | MEDIUM | HIGH | CRITICAL`。

owner 规则：

| owner | 权限 |
|---|---|
| `self` | 父编排器处理编排元数据和少量胶水；修改产品文件时仍须提交、diff、验证和独立审查 |
| `craft` | 在 lane worktree 写代码、验证并提交一个任务 |
| `explore` | 只读调研；禁止编辑、提交或生成修改型产物 |
| `docs` | 独立文档修改；按任务要求提交并验证文档一致性 |

### 1.4 lane 分配

按以下顺序分配：

1. 任务有直接或传递依赖：放进同一 lane，按依赖顺序串行。
2. 任务修改或生成同一文件：放进同一 lane。
3. 任务共享 schema、锁文件、公共接口或必须读取对方未集成结果：放进同一 lane。
4. 只有不存在上述关系的任务才可进入不同 lane 并行。

计划中同时写明每个任务的预期文件。若无法证明两个 lane 独立，就合并 lane。

`explore` 可先于实现运行，但其只读结论必须固化到 `context.md`。`docs` 若依赖实现产生的最终接口，应与该实现同 lane 串行；完全独立的文档可单独成 lane。

### 1.5 分支与 worktree

- lane 分支：`orchestrate/<task-id>/lane-<id>`。
- integration 分支：`orchestrate/<task-id>/integration`。
- 每个 lane 共用一个 worktree；lane 内任务按计划顺序在同一分支执行。
- integration 使用独立 worktree，从用户确认的目标 base 创建。

创建前检查 worktree 目录安全、忽略规则、依赖安装方式和基线状态。基线失败要记录并先请求裁决，不能把旧失败算作本次失败。

### 1.6 一次性计划授权

执行前把完整 `plan.md` 给用户过目。授权文本必须明确请求：

- 创建计划中列出的 lane worktree 和分支。
- 创建临时 integration 分支和 worktree。
- 允许 craft/docs 以及修改产品文件的 self 任务在各自任务分支提交。
- 允许父编排器把已审查 lane 按计划顺序内部合并到 integration。
- 不 push、不合入目标分支、不删除用户已有 worktree。

用户批准后只能在该范围内执行。新增 lane、扩大 CRITICAL 范围或改变目标 base 时重新请求授权。

## 阶段 2：lane 执行、提交、独立审查

### 2.1 Agent 预算

在 `ledger.md` 记录：

- 已调用 Agent 数和剩余额度。
- 当前并发数。
- 每个 lane 当前任务和状态。
- 最后确认的 base/head SHA。

调用计数包括每次实现、调研、文档、审查、修复和复审派发；恢复同一 Agent 继续工作也计一次。计划准入前计算：

```text
预计调用 = 所有实际派发给 Agent 的 explore/docs/craft 执行调用
         + 每个修改型任务至少一次独立 reviewer 调用
         + 至少 2 次修复/复审预留
```

`owner: self` 的执行本身不计 Agent 调用，但它的独立 reviewer 调用要计。预计调用必须不大于 8。CRITICAL 的质量 reviewer 必须具备独立安全审查职责；若需额外安全 reviewer，也计入公式。预算不足时先合并过细任务、减少调研派发或退出完整编排，不能让 `self` 绕过证据要求。每次 P2/P3 修复或重试都消耗预留；剩余额度不足时先暂停派发。

所有子 Agent prompt 都写明："不得调用 Agent 或继续委派。"

### 2.2 lane 执行

- 不同独立 lane 可并行，同一 lane 永远一次只运行一个任务。
- 后续任务从同一 lane 的最新已审查 head 开始，因此能看到前置提交。
- `owner: craft` 必须加载 craft 契约，提交聚焦改动并返回标准 Craft Result。
- `owner: docs` 使用同样的分支、提交和证据要求，但验证重点是内容、链接、示例和源代码一致性。
- `owner: explore` 只返回事实、证据路径、不确定项和建议，不得改变 worktree。
- `owner: self` 若修改产品文件，使用与 craft/docs 相同的提交、diff package、验证和独立审查要求；只改 `.workflow` 编排元数据时可不单独提交。

实现 prompt 必须包含：

- 完整任务和验收标准。
- lane、worktree、分支、base SHA 和预期文件。
- `context.md` 中相关事实与 API 查证。
- 风险级和最低验证要求。
- git 权限边界。
- 返回格式和未验证项披露要求。

### 2.3 每任务提交与 diff package

每个 craft/docs 任务及任何修改产品文件的 self 任务完成时必须提供：

- task、lane、worktree。
- base SHA、head SHA、提交信息。
- 文件清单和 diff stat。
- 可复现的 diff 范围或获取命令。
- 验收标准映射。
- 验证命令、退出状态、关键结果。
- 未验证项和偏离计划之处。

缺少提交、head 不在预期分支、diff 混入别的任务或验证证据缺失，都不能进入审查通过状态。

### 2.4 独立审查

实现者不能审查自己的最终结果。由独立 reviewer 对实际 `base..head` 做两个有顺序的检查：

1. **规格审查**：逐条核对任务范围和验收标准，检查漏做、越界和错误假设。
2. **质量审查**：检查正确性、回归、测试、复杂度、复用、安全和维护性。

reviewer 只读，不提交修改。结论为：

- `APPROVED`。
- `CHANGES_REQUESTED`，列出 P0-P3、文件/行、证据和所违反的要求。
- `BLOCKED`，说明缺少什么事实。

P2/P3 返回同一任务执行者自动修复、提交并重跑受影响验证，然后 reviewer 复审新范围。P0/P1 由父编排器汇总后一次请求用户裁决。

用户裁决后按唯一明确状态转换：

- **修复**：重开原任务，形成新提交，重跑受影响验证，再做规格和质量复审。
- **缩小/取消范围**：冻结并放弃包含该未批准提交的旧 lane，不将它汇入 integration。从该任务的 base SHA（即前一个已批准提交）创建 replacement lane，更新 plan/授权后再执行后续任务；这样被取消提交不会随整条 lane 汇入。
- **接受风险**：记录 finding、授权者、适用范围和退出条件。只有用户另行明确授权进入 integration 且不违反不可豁免的项目安全规则时，标为 `WAIVED`；最终报告不得称为审查通过。
- **终止**：冻结该 lane，记录恢复条件，其他独立 lane 可继续。

任务只有在规格和质量两项都批准后，才可标记 `reviewed` 并推进 lane。

### 2.5 规模重判与阻塞熔断

出现以下任一情况，暂停新任务并回到阶段 0/1：

- 实际文件范围显著超过计划。
- 新发现依赖、共享文件或 lane 间可见性要求。
- 风险升级到 HIGH/CRITICAL。
- 需要新增 lane 或改变 integration base。

同一阻塞在补充上下文或重试后再次发生，就触发熔断：停止该 lane，记录最后证据和恢复条件，不盲目继续。其他真正独立 lane 可继续。

## 阶段 3：integration 汇入与组合验证

### 3.1 汇入

所有待汇入任务必须先审查通过；唯一例外是已完成独立审查、由用户明确授权进入 integration 的 `WAIVED` 任务，且该风险不违反不可豁免规则。父编排器在 integration worktree 中按 `plan.md` 的 lane 顺序合并 lane 分支，并在每次合并后记录 integration head。

若出现任何冲突：

1. 立即终止并中止本次合并，恢复到合并前 integration head。
2. 把冲突记为拆分失败，不在 integration 中手工解冲突。
3. 识别已汇入的冲突任务和当前待汇入任务，在 plan 中将它们重组为一个 replacement lane。
4. replacement lane 从步骤 1 的最后干净 integration head 创建；已汇入冲突任务作为已审查前缀，待汇入任务在其后串行重做。若前缀本身必须改变，把变更建成 replacement lane 的新修复任务并重新审查。
5. replacement lane 只包含相对该干净 integration head 的新提交，因此再次汇入时不会重复合并已汇入提交。
6. 更新 plan、ledger 和授权范围；需要新分支、改变 base 或扩大范围时请求用户确认。
7. replacement lane 的新提交全部审查通过后，再汇入当前干净 integration。

不要用 ours/theirs、跳过提交或临时拼补来掩盖错误拆分。

### 3.2 组合验证命令探测

只在 integration worktree 对真实组合代码运行聚合验证。命令按以下证据选择：

1. 项目级指令和 CI 配置。
2. 构建系统、manifest、包管理脚本。
3. 现有测试入口和受影响模块惯例。

不假设语言、包管理器或类型系统。命令不存在或环境不足时记录未验证项。

### 3.3 风险分级

| 风险 | integration 最低验证 |
|---|---|
| LOW | 配置/语法检查、目标测试或项目定义的轻量检查 |
| MEDIUM | LOW + 受影响测试 + 静态检查 + 跨模块用法搜索 |
| HIGH | MEDIUM + 全量测试或构建 + 关键路径验证 |
| CRITICAL | HIGH + 完整回归 + 独立安全审查 + 出口用户确认 |

如果项目提供多种验证，优先复现 CI 的关键命令。记录每条命令、工作目录、退出状态和未运行原因。

### 3.4 integration 修复

组合验证暴露的问题只能集中到一个 `integration-fix` 任务：

- 在 integration 分支内做最小修复。
- 单独提交并生成 diff package。
- 由独立 reviewer 做规格与质量审查。
- 重跑失败命令、相邻验证和该风险级要求的聚合验证。

如果修复说明原 lane 拆分错误，回到 lane 重组，不能把长期业务实现堆进 integration-fix。

## 阶段 4：结果与用户决策

### 4.1 results.md

每个修改型任务记录一行或一节，至少含：

```markdown
- task:
  lane:
  worktree:
  base SHA:
  head SHA:
  review:
  validation commands:
  exit status:
  unverified:
```

此外记录：

- lane 分支和最终 head。
- integration 分支、汇入顺序和最终 head。
- integration 聚合验证。
- P0/P1 裁决及 CRITICAL 入口/出口确认。
- 偏离 plan、熔断和仍需人工处理的事项。

### 4.2 最终边界

向用户报告：

1. 完成和未完成的任务。
2. 每个 lane 的提交与审查结论。
3. integration 组合验证及未验证项。
4. integration 分支相对目标 base 的 diff 摘要。
5. 可选的后续动作。

最终是否把 integration 合入目标分支由用户决定。未经新的明确授权，不 merge 目标分支、不 push、不清理分支或 worktree。

## ledger、恢复与 handoff

每次任务提交、审查、lane 推进、integration 合并和验证后立即更新 `ledger.md`。至少记录：

- 当前阶段和下一个安全动作。
- plan 版本与用户授权摘要。
- Agent 预算。
- lane/task 状态。
- 分支、worktree、base/head SHA。
- 最后一条验证命令和退出状态。
- 阻塞、未验证项和需要用户裁决的 P0/P1。

上下文压缩或会话恢复后，先读取 `context.md`、`plan.md`、`ledger.md`、`results.md`，再用 git 当前事实复核分支和 SHA；不凭记忆继续。

需要 handoff 时，交接包必须包含以上文件路径、当前阶段、剩余预算、已授权范围、禁止动作和唯一下一步。接收者复核事实后才能继续。

## 完成判定

只有同时满足以下条件才可说编排执行完成：

- 所有完成的 craft/docs 任务及修改产品文件的 self 任务都有提交和 diff package。
- 每个实现单元的规格与质量审查均通过；显式 `WAIVED` 只能报告为带风险交付，不能计入“全部审查通过”。
- 所有计划 lane 已按顺序组合到 integration，且没有未处理冲突。
- integration 已执行对应风险级的聚合验证。
- 所有未验证项、P0/P1 和偏离计划均已披露。
- `~/.agents`、用户目标分支和用户已有 worktree 未被擅自修改。
