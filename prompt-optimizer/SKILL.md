---
name: prompt-optimizer
description: |
  **手工精修一份已有 prompt 的文本**——触发、结构和文风，改一次改到位，不跑自动循环。适用于 Codex / Claude Code 的 Skill description、agent prompt、AGENTS.md / CLAUDE.md、Output Style、command / hook，以及 Anthropic API prompt（按资产类型读对应方法卡）。用户要求"优化提示词""skill 没触发""规则没生效""改写 system 或 agent prompt""这段提示词帮我改改"，或直接给出 prompt 文件时使用；可直接改文件，也可只审计给建议，或结合失败样本做 eval。
  四方分流——skill 元工具只此四个，按**要什么动作**选：手工精修已有 prompt 文本 → 本 skill（单个 skill 触发不准、改一份 description、调 agent prompt 或 CLAUDE.md 都归这里）；从零新建 skill → `skill-creator`；要机器自动多轮迭代 + 独立 judge 打分 + 自动 keep/revert，或要按 rubric 出分数 → `darwin-skill`；把本次会话的反馈沉淀回 skill 正文 → `skill-evolution-manager`。
  不适用：**多个 skill 互抢触发、彼此边界模糊**——那不是文本问题，是资产架构决策，主会话直接重划分工，不要在这里逐个优化 description；模型选型；代码逻辑 bug。
---

# Prompt Optimizer

在不改变原始目标和能力边界的前提下，让 prompt 更明确、自然、精简且可验证。不要为了套用方法论而增加角色、标签、示例或禁止项。

## 先确定任务

结合用户措辞、文件路径和会话上下文判断资产类型，以及用户要只审计还是直接修改。

用户给出可访问文件并说“优化、修改、修复”时，默认读取并修改；用户说“分析、评审、看看问题”时，默认只给建议。只有资产类型无法判断且不同判断会明显改变结果，或缺少必要输入时，才询问用户。

多种资产可分别处理，不必要求用户先选一种。

## 按需读取

只读取当前资产对应的文档：

| 资产 | 识别信号 | 文档 |
|---|---|---|
| Skill description | `SKILL.md` frontmatter、触发/误触发问题 | `track-cc/skill-description.md` |
| Agent / subagent prompt | 委派任务、`Task`、`Agent`、spawn prompt | `track-cc/agent-prompt.md` |
| 常驻指令文件 | `AGENTS.md`、`CLAUDE.md`、项目或用户规则 | `track-cc/claude-md.md` |
| Output Style | `output-styles/*.md`、文风或回答格式 | `track-cc/output-style.md` |
| Slash command / hook | command 文件、`settings.json` hook | `track-cc/slash-command-hook.md` |
| Anthropic API prompt | `system`、`messages`、SDK 调用或应用 prompt | `track-api/static-scan.md` |

目录可能因 Codex、Claude Code 或共享 Skill 而不同；根据真实路径判断，不假设固定大小写。

## 工作流程

1. 读取完整 prompt，以及理解其作用所需的最少上下文。路径可访问时不要让用户重复粘贴内容。
2. 先确认目标行为、受众、输入来源和不可改变的约束。能从上下文可靠推断的内容直接采用。
3. 只报告会影响触发、正确性、可执行性、文风或 token 成本的问题。每个问题说明证据、影响和建议，避免逐项报“通过”。
4. 给出干净、可直接使用的改写版。修改理由放在正文外，不把 `[A 新增]` 等诊断标签写进 prompt。
5. 用户要求修改文件时，先保留可回滚副本，再做最小改动并验证语法、引用路径和关键约束。只审计时保留原文件不动。
6. 用户描述了实际失败、提供了样本或要求证明效果时，加入回放或新旧版本 eval；不要用静态检查冒充行为验证。

## 输出

只审计时先给关键发现和完整改写版；已修改文件时说明改动、验证和备份位置，不重复粘贴整份文件；信息不足时只问会阻塞结果的问题。不强制固定标题、三段式或维度编号。

## 质量底线

- 保留用户原始意图、必要能力、变量占位符、输出契约和安全边界。
- 删除重复、互相冲突、无法执行或只增强语气的规则。
- 不把角色定义、XML、few-shot、禁止项、JSON schema 当作所有 prompt 的必需品；只有它们能解决当前问题时才加入。
- 区分 prompt 文本问题、运行参数问题、工具权限问题和业务逻辑问题。
- 涉及具体 SDK、模型版本或产品机制时，先查当前官方文档，不沿用记忆中的参数技巧。
- 用户只提供片段时保持相同粒度，除非补全上下文是实现目标所必需的。
- 自己复读 prompt、检查断言或设想几个场景属于静态自检，不称为“回放、A/B、eval”或实际效果验证。

## 完成前检查

确认改写没有削弱能力，每项新增规则都解决明确问题，变量和引用仍有效，文本比原文更易读。声称改善实际效果时必须有样本或 eval 支持。
