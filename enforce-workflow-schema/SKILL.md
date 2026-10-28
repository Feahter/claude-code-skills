---
name: enforce-workflow-schema
description: 把"开始做需求"落到 .workflow/<task-id>/ 标准目录，强制 spec.md（含排除范围）+ plan.md（含验证证据），衔接 writing-plans / subagent-driven-development / verification-before-completion / <domain-feature>。触发：消息含 Jira 号（PROJECT-数字）、`.workflow/` 路径，或说"开始做需求/接需求/实现这个功能/重构 X/接 X 链/加 X 平台"且跨 3+ 文件。不适用：纯 bug 排查（diagnose）、单文件小改、纯讨论方案、查埋点查交易。按**谁执行**分流：本会话自己动手实现走本 skill；要写一份任务书交给**另一个 agent 独立跑完**（目标模式、无人值守、每周重复的活）→ `goal-plan`。
---

# enforce-workflow-schema：规格驱动开发的本地执行器

## 为什么有这个 Skill

本地协作的两类常见失败：
- **方向错**：AI 实现到一半"自由发挥"，做出与需求对不上的功能
- **做错**：声明完成但没跑验证命令，造成隐患

解法是把项目仓根下 `.workflow/<task-id>/` 这个**已经在用的目录约定**升级成强 schema，并把"排除范围"和"验证证据"这两件最常被跳的事变成必填。

## 触发后必须做什么

### 步骤 1：识别 task-id
按优先级：
1. 用户消息有 Jira 号（如 `PROJ-7069` / `PROJ-1234`）→ 用工单号
2. 用户给出明确功能名 → 用短横线连接的功能名（如 `add-token-filter`）
3. 都没有 → 用 `YYYY-MM-DD-<topic>` 兜底

### 步骤 2：确认 .workflow 根
- 当前 cwd 是某个项目仓 → 在该项目下 `.workflow/<task-id>/`
- 不在项目仓 → 询问用户目标项目根

### 步骤 3：检查目录是否存在
- 已存在 → 复用现有 spec.md / plan.md，不覆盖
- 不存在 → 创建目录 + 复制 templates/ 下两份模板

### 步骤 4：写 spec.md
- 必含 5 个区块：**需求摘要 / 输入输出 / 排除范围 / 验收口径 / 依赖与风险**
- "排除范围"是硬要求 — 不写清楚"不做什么"，AI 会"好心"多做
- 长度控制：spec.md ≤ 200 行；超出说明需求过大，先拆

### 步骤 5：写 plan.md（4 区块强制）
- **A. 技术决策** — 关键选型 + 理由（不是 KV 列表，是简短论述）
- **B. 任务拆分** — checklist 形式，每条粒度 ≤ 1 个 Session 可完成（Task 风格见 `templates/plan.md`）
- **C. 排除范围回引** — 引用 spec.md 的"排除范围"，让审查代理可对照
- **D. 验证证据** — 完成声明前必填，区块格式见模板。每条 task 的退出条件是这里贴出实际命令输出

### 步骤 6：衔接已有 skill
- 用户开始执行任务 → 调用 `subagent-driven-development` 或 `executing-plans`
- 每个 task 完成 → 调用 `verification-before-completion`，把命令输出写入 plan.md 的 D 区块
- 在 your-app 项目 → `<domain-feature>` skill 应同时被触发，不要重复执行其逻辑
- 全部 task 完成 → 调用 `finishing-a-development-branch` 收尾

### 目录约定（`.workflow/<task-id>/` 的唯一定义）

其他 skill 往这个目录写文件时以本表为准，不另立结构。

| 文件 | 何时有 | 内容 | 写入方 |
|---|---|---|---|
| `spec.md` | 必有 | 五区块：需求摘要 / 输入输出 / 排除范围 / 验收口径 / 依赖与风险 | 本 skill |
| `plan.md` | 必有 | A–D 四区块。编排任务在 B 区块的 Task 标题下加 `[deps][owner][lane][isolate][risk]` 标签 | 本 skill；auto-orchestrate 加标签 |
| `decisions.md` | 跑过 auto-grill 时 | D1、D2… 编号的决策树，是重对齐的正本；spec.md 的需求摘要和排除范围引用这些编号 | auto-grill |
| `context.md` | 编排时 | 侦察事实：调用关系、API 查证、验证入口。需求本身不写这里，写 spec.md | auto-orchestrate |
| `ledger.md` | 编排时 | 运行进度和恢复点 | auto-orchestrate |
| `results.md` | 编排时 | 逐任务的 SHA、审查、验证明细；plan.md 的 D 区块写聚合结论并指向它 | auto-orchestrate |

auto-grill 的 D 编号指决策，和 plan.md 的「D. 验证证据」区块不是一回事，引用时写全「决策 D3」。

### 步骤 7：归档（可选）
功能合并后，由用户决定是否 `mv .workflow/<task-id> .workflow/_archive/<task-id>`。本 skill 不主动归档（避免污染历史 git）。

## 与已有 skill 的边界

| Skill | 边界 |
|---|---|
| `writing-plans` | 它写计划，本 skill 把计划落到 `.workflow/<task-id>/plan.md` 的 B 区块 |
| `subagent-driven-development` | 执行每个 task，本 skill 不重复其工作 |
| `verification-before-completion` | 它要求跑验证，本 skill 要求把验证证据落盘到 D 区块 |
| `<domain-feature>` | 项目级领域知识注入，本 skill 不覆盖 |
| `auto-orchestrate` | 编排器。它在本 skill 的 spec.md、plan.md 之上加 context / ledger / results 三个文件和任务标签，见「目录约定」 |
| `auto-grill` | 拷问结论落 `decisions.md`，见「目录约定」 |

## 反触发场景（不要用）
- 单文件单行 bug 修复（直接改）
- 纯方案讨论 / 架构评估（用 think-rigorously / brainstorming）
- 查埋点 / 查交易 / 查配置
- 纯 code review（用 open-code-review）
- 未提交但已写好的代码做 review（用 open-code-review）

## 模板位置
- 创建文件时优先复制 `~/.claude/skills/enforce-workflow-schema/templates/spec.md` 和 `plan.md`
- 模板已留好占位符，按实际填充

## 为什么这样设计

- plan.md 的 D 区块强制贴验证证据，因为完成声明最常缺的就是验证。
- spec.md 落盘成项目内文件，自动压缩丢掉约束后新会话可以重读。

## 失败回退
- 用户明确说"这次不写 spec/plan"→ 跳过本 skill，但要求本轮结束前**至少**贴出验证命令输出
- 项目根没有 `.workflow/` 目录传统 → 询问用户是否启用，不强行创建
