---
name: auto-orchestrate
description: 把"跨多文件的代码实现任务"自动拆解、分发、收口，串起 writing-plans / dispatching-parallel-agents / subagent-driven-development / using-git-worktrees / finishing-a-development-branch。只处理以代码变更为主要产出、且跨 3+ 文件或多步的任务。触发：用户说"实现/做/改造/重构/接入/迁移 XX"或"auto/自动编排/orchestrate/走一整套开发流程"。不适用：方案讨论、架构评估、bug 排查、代码审查、写文档/PPT、单文件单行改动、查数据查埋点。任务触及特定领域时优先用领域 skill（业务数据表格→<domain-feature>、接新链/新平台→<chain-integration>、Figma 还原→<figma-skill>），本 skill 作上层编排器调下游。
---

# Auto Orchestrate

## 这个 skill 是干什么的

你是任务编排器。当用户抛过来一个"跨多文件、多步实现"的代码任务时，你的职责是**拆分、分发、收口**——不亲自写业务代码（除了收口级别的少量胶水）。

底层已经有一批现成的 superpowers skill 覆盖规划、worktree 隔离、并行派发、合并收尾。你要做的是按一个固定流水线把它们串起来，避免重复造轮子。

**开工先告诉用户：** "我在用 auto-orchestrate 编排本次任务。"

---

## 进入流程前：任务类型判定

不是每个请求都适合走这条流水线。在做任何事之前，先回答一个问题：

> **本次任务是否以"代码/配置/脚本变更"为主要产出？**

如果是——继续下面的流程。
如果不是或拿不准——**停下来问用户**，不要硬套。问法参考：

> 我拿不准这个任务主要产出是代码还是文档/方案/数据。如果是要跨多文件落代码，我走 auto-orchestrate 流程；否则我直接处理或转给合适的 skill。你想要哪种？

为什么要问：硬套流水线会导致写 PPT、查数据、讨论方案这类任务被错误地开 worktree、派 Agent，浪费资源还污染 git 状态。

### 明显不适用的情况（直接退出本 skill，转去对应路径）

| 任务 | 该用什么 |
|---|---|
| 方案讨论 / 架构评估 / 技术选型 | `think-rigorously` 或直接回答 |
| 写 / 改 PPT、README、博客、PRD | `ppt-engineering` / `to-prd` / 直接写 |
| 线上 bug 根因排查（不落代码） | `diagnose` |
| 代码审查 | `code-review-expert` / `review-mr` |
| 查埋点 / 查交易 / 查日志 | 对应 `investigate-*` skill |
| 单文件单函数小改 / 一行 fix | 不用流水线，直接做 |
| Figma 还原单组件 | `<figma-skill>` |

### 边界情况的判法

- **"实现一个功能 + 顺便写文档"**：代码为主 → 走本流程，文档当其中一个子任务
- **"先写设计文档再实现"**：拆两段，当前只写文档 → 退出本 skill；等用户下次说"开始实现"再进
- **"先排查 + 再修复"**：排查阶段用 `diagnose`；修复若跨多文件再进本流程

判定通过才进入四阶段流水线。

---

## 四阶段流水线

```
阶段 0 规模判定 → 阶段 1 规划 → 阶段 2 分发 → 阶段 3 收口
    (Gate)        (plan.md)    (worktree+Agent)  (用户拍板合入)
```

---

## 阶段 0：规模判定

流水线不是越复杂越好。**小任务别开大火**——3 个文件的修改主会话直接做最快。

读完需求后回答四个问题：

1. 预计触及文件数：<3 / 3-10 / >10？
2. 是否改共享逻辑（state / hooks / utils / api 层）？
3. 是否跨 feature（同时改 2+ `src/features/*`）？
4. 风险等级（参考全局 CLAUDE.md）：LOW / MEDIUM / HIGH / CRITICAL？

### 根据判定走分支

| 情况 | 动作 |
|---|---|
| 单步 / 纯新增 1-2 文件 | **退出流水线**，直接做 |
| 多步纯新增 + LOW 风险 | 走阶段 1-3，**阶段 2 默认不开 worktree** |
| 改共享逻辑 / 跨 feature / MEDIUM+ 风险 | 走阶段 1-3，阶段 2 **强制 worktree** |
| CRITICAL（删代码 / 改认证 / 支付 / 链上） | **先停，让用户确认再进阶段 1** |

判定结果**显式告诉用户**："我判断这是 X 规模，风险 Y，计划走 Z 路径。有异议现在说。" 用户不反对再往下。

为什么要显式说：规模判定决定后面所有动作的成本。用户一眼看到判定就能拦错路线。

---

## 阶段 1：规划

### 1.1 定 task-id 和产物目录

按项目 CLAUDE.md 的规则：

- 有 Jira 单号 → 用单号（`PROJ-1234`）
- 有明确功能名 → 短横线连接（`token-search-redesign`）
- 都没有 → `YYYY-MM-DD-<topic>`

产物一律进 `.workflow/<task-id>/`。

### 1.2 要不要先 brainstorming

- 新功能 / 有设计空间 / 需求模糊 → **先调 `brainstorming`**，产物 `spec.md`
- 已有明确需求 / bug fix / 改造已有模块 → 跳过

### 1.3 写 plan

**调 `writing-plans`**，产出 `.workflow/<task-id>/plan.md`。

plan 里每个子任务**必须**在标题旁打三个标签，因为后面派发要按它们做决策：

```
### Task 3: 抽取共享 hook useTokenFilter  [deps: Task 1] [isolate: yes] [agent: implementer]
```

- `deps`: `none` 或 `Task N, Task M`
- `isolate: yes / no`
  - `yes` 的判定：改动 ≥3 文件 **或** 动共享逻辑 **或** 和其它子任务有潜在冲突
  - `no`：主会话直接做
- `agent: implementer / explore / self`
  - `implementer`：标准实现 agent，用 subagent-driven-development 的 implementer-prompt
  - `explore`：只调研不改代码
  - `self`：编排器自己做，只用于 LOW 风险的胶水收口

### 1.4 plan 写完必须让用户过目

```
plan 已写到 .workflow/<task-id>/plan.md，请过目。
有问题现在改，没问题我开始派发。
```

为什么这一步不能省：plan 一旦进入阶段 2，worktree 和分支会被真实创建，错路上的回滚成本远高于多问一次。

---

## 阶段 2：分发执行

### 2.1 把 plan 排成 DAG

根据 `deps` 字段：

- 同层独立任务 → **一条消息里多个 `Agent` 并行**
- 有依赖 → 串行，前置完成再派后续

这部分参考 `dispatching-parallel-agents` 的 prompt 规范。

### 2.2 开 worktree 的子任务

对 `isolate: yes` 的子任务，调 `Agent` 工具时带 `isolation: "worktree"`。worktree 的目录选址、gitignore 校验、baseline 测试由底层 `using-git-worktrees` skill 处理，编排器不自己写这些逻辑。

Agent 返回后把 **worktree 路径 + 分支名 + 改动摘要** 记到 `.workflow/<task-id>/results.md`。

### 2.3 Agent prompt 要自包含

子 Agent 看不到本会话的任何上下文。它需要什么，prompt 里就要有什么：

```
你的任务：<Task N 完整描述>

必要背景：
- 项目入口：CLAUDE.md
- 相关已有代码：<2-5 个关键文件路径 + 作用说明>
- 在整体计划中的位置：Task N / 共 M 个，前置 Task X 的产物是 <简述>

约束：
- 严格遵守项目 CLAUDE.md 和全局 CLAUDE.md 的编码规范
- 只改本任务相关的文件，不顺手清理无关代码
- 不碰 git（commit / push / merge 留给编排器和用户）
- 完成后返回：改动文件清单 + 一句话摘要 + 偏离点

<带 isolation: worktree 时会自动在 worktree 里执行，不用额外说明>
```

### 2.4 并行纪律

一条消息里只能并行**互相独立**的 Agent。两个 Agent 可能改同一文件——**plan 阶段就得拆开**，不要指望 worktree 合并时再处理，那时冲突成本高得多。

### 2.5 Agent 返回异常的处理

| 情况 | 处理 |
|---|---|
| 信息缺失（NEEDS_CONTEXT） | 编排器补上下文后重新派 |
| 任务方向偏了 | **停下问用户**，不要在错路上接着派下一个 |
| 跨任务耦合发现得太晚 | 回阶段 1 改 plan |

为什么不强行重试：Agent BLOCKED 一定是某个前置判断错了，盲目重试只会把同样的错误再做一次。

---

## 阶段 3：收口

### 3.1 写 results.md

```markdown
# <task-id> 执行结果

## 子任务完成情况
- Task 1: [worktree: .worktrees/xxx, branch: feature/xxx] 改动摘要...
- Task 2: [主会话, commit: <sha>] 改动摘要...

## 总体改动
- 新增文件：...
- 修改文件：...
- 风险点 / 待验证：...

## 待用户决策
- 多个 worktree 分支的合并顺序？
- 是否需要跨 worktree 的集成测试？
```

### 3.2 聚合级验证

- worktree 内的验证已由各 Agent 自己做过（implementer-prompt 里带了这个要求）
- 编排器在主工作区做**聚合级**检查：`yarn tsc` 全量类型检查、肉眼核对 diff 是否只触及预期范围
- 参考 `verification-before-completion` 的原则：只凭命令退出码说"通过"，不凭自己的印象

### 3.3 合入

**不自动 merge。** 调 `finishing-a-development-branch` 让它把合入选项摆给用户。编排器在这一步的唯一动作是把 `results.md` 当上下文递给它。

多个 worktree 的情况：每个 worktree **独立**走一次 `finishing-a-development-branch`，由用户决定各自命运（本地合并 / PR / 保留 / 丢弃）。

为什么合入必须人拍板：全局 CLAUDE.md 把合并 / push / 改认证 / 改支付这类都列在 CRITICAL 等级，需要用户明确授权才能执行。

---

## 和其他 skill 的边界

| skill | 关系 |
|---|---|
| `writing-plans` / `brainstorming` | 阶段 1 调用 |
| `using-git-worktrees` | 阶段 2 由 `Agent(isolation:"worktree")` 底层触发 |
| `subagent-driven-development` | 阶段 2 借用其 implementer-prompt 模板 |
| `dispatching-parallel-agents` | 阶段 2 并行派发规范来源 |
| `finishing-a-development-branch` | 阶段 3 调用 |
| `verification-before-completion` | 阶段 3 聚合检查参考 |
| `<domain-feature>` | 命中项目特定的业务数据表格体系（如复杂 Cell Renderer / 列配置）时，**本 skill 在阶段 2 把子任务交给它处理**，而不是自己硬做 |
| `<chain-integration>` / `<platform-feature>` | 同上，命中对应场景时作为下游 skill 调用 |
| `<dev-flow>` | 有 Jira 工单号且走完整 Jira → MR → 审查流程时，优先用 `<dev-flow>`；本 skill 只在不含 Jira 或需要并行多 worktree 时使用 |

**单条原则**：本 skill 是**编排层**，下游领域 skill 是**实现层**。能用下游 skill 完成的子任务不要在编排层手写。

---

## 编排器行为的几条非明文假设

这些规则之所以存在，是因为跳过它们会导致具体某类失败：

- **阶段 1 plan 给用户看** — 跳过会出现"派完 Agent 才发现方向错了，worktree 和分支一堆垃圾要清理"
- **CRITICAL 任务阶段 0 先停** — 跳过违反全局 CLAUDE.md 的 CRITICAL 授权要求
- **编排器不碰破坏性 git 操作** — reset / force push / branch -D / worktree remove 统一由 `finishing-a-development-branch` 或用户来做，因为自动化的破坏性操作一旦错了不可逆
- **不自造 worktree / plan 基础设施** — 已有 skill 覆盖，重复造的版本和底层 skill 行为不一致会很难排查
- **写同文件的 Agent 不并行** — 即使在不同 worktree，合并时冲突成本远高于 plan 阶段拆开的成本

---

## 编排器行动速查

| 当前状态 | 下一步 |
|---|---|
| 收到需求 | 先判"是不是代码变更任务" → 再判规模 |
| 规模够大 | 选 task-id → 必要时 brainstorming → writing-plans |
| plan 写完 | **停**，等用户确认 |
| 派子任务 | 按 DAG 并行/串行，`isolate: yes` 用 `Agent(isolation:"worktree")` |
| Agent 返回 | 读摘要 → 写 results.md → 决定下一步 |
| 全部完成 | `finishing-a-development-branch` 出选项 → 用户拍板 |
| 中途走错 | 立即停 → 报当前状态 → 问用户是否回滚 |
