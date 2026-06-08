---
name: enforce-workflow-schema
description: 把"开始做需求"落到 .workflow/<task-id>/ 标准目录，强制 spec.md（含排除范围）+ plan.md（含验证证据），衔接 writing-plans / subagent-driven-development / verification-before-completion / <domain-feature>。触发：消息含 Jira 号（PROJECT-数字）、`.workflow/` 路径，或说"开始做需求/接需求/实现这个功能/重构 X/接 X 链/加 X 平台"且跨 3+ 文件。不适用：纯 bug 排查（diagnose）、单文件小改、纯讨论方案、查埋点查交易。
---

# enforce-workflow-schema：规格驱动开发的本地执行器

## 为什么有这个 Skill

本地协作的两类常见失败：
- **方向错**：AI 实现到一半"自由发挥"，做出与需求对不上的功能
- **做错**：声明完成但没跑验证命令，造成隐患

解法是把 `~/projects/your-app/.workflow/<task-id>/` 这个**已经在用的目录约定**升级成强 schema，并把"排除范围"和"验证证据"这两件最常被跳的事变成必填。

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
- "排除范围"是硬要求 — 不写清楚"不做什么"，AI 会"好心"多做（A2 文章坑 #2 / 坑 #5 的根因）
- 长度控制：spec.md ≤ 200 行；超出说明需求过大，先拆

### 步骤 5：写 plan.md（4 区块强制）
- **A. 技术决策** — 关键选型 + 理由（不是 KV 列表，是简短论述）
- **B. 任务拆分** — checklist 形式，每条粒度 ≤ 1 个 Session 可完成（参考已有 PROJ-6491/plan.md 的 Task 风格）
- **C. 排除范围回引** — 引用 spec.md 的"排除范围"，让审查代理可对照
- **D. 验证证据** — 完成声明前必填，区块格式见模板。每条 task 的退出条件是这里贴出实际命令输出

### 步骤 6：衔接已有 skill
- 用户开始执行任务 → 调用 `subagent-driven-development` 或 `executing-plans`
- 每个 task 完成 → 调用 `verification-before-completion`，把命令输出写入 plan.md 的 D 区块
- 在 your-app 项目 → `<domain-feature>` skill 应同时被触发，不要重复执行其逻辑
- 全部 task 完成 → 调用 `finishing-a-development-branch` 收尾

### 步骤 7：归档（可选）
功能合并后，由用户决定是否 `mv .workflow/<task-id> .workflow/_archive/<task-id>`。本 skill 不主动归档（避免污染历史 git）。

## 与已有 skill 的边界

| Skill | 边界 |
|---|---|
| `writing-plans` | 它写计划，本 skill 把计划落到 `.workflow/<task-id>/plan.md` 的 B 区块 |
| `subagent-driven-development` | 执行每个 task，本 skill 不重复其工作 |
| `verification-before-completion` | 它要求跑验证，本 skill 要求把验证证据落盘到 D 区块 |
| `<domain-feature>` | 项目级领域知识注入，本 skill 不覆盖 |
| `auto-orchestrate` | 编排器，本 skill 是它的子环节（提供 schema） |

## 反触发场景（不要用）
- 单文件单行 bug 修复（直接改）
- 纯方案讨论 / 架构评估（用 think-rigorously / brainstorming）
- 查埋点 / 查交易 / 查配置（用对应 investigate-* skill）
- 纯 code review（用 code-review-expert）
- 未提交但已写好的代码做 review（用 code-review-expert）

## 模板位置
- 创建文件时优先复制 `~/.claude/skills/enforce-workflow-schema/templates/spec.md` 和 `plan.md`
- 模板已留好占位符，按实际填充

## 与 loss-analysis 报告的对应

本 skill 解决以下基线痛点（来源：`~/Documents/md/2026-05-26-claude-task-loss-analysis.md`）：
- 痛点 #1（84 次完成声明无验证）→ plan.md 的 D 区块强制
- 痛点 #4（38 次自动压缩丢约束）→ spec.md 落盘成项目内文件，新会话可重读
- A2 文章坑 #2 / #5 → spec.md 的"排除范围"区块强制

## 失败回退
- 用户明确说"这次不写 spec/plan"→ 跳过本 skill，但要求本轮结束前**至少**贴出验证命令输出
- 项目根没有 `.workflow/` 目录传统 → 询问用户是否启用，不强行创建
