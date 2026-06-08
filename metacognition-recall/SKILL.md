---
name: metacognition-recall
description: 按需从本项目 memory/metacognition/ 召回与当前任务相关的技术事实、偏差、历史判断与决策。SessionStart 只注入静态 top-N，本 skill 补"带 query 语义检索记忆"。触发：用户说"查下记忆有没有 X/之前怎么处理的/有没有踩过这个坑/recall"，或任务涉及多模块、跨 feature、历史决策时。不适用：读当前代码（Read/grep）、读 CLAUDE.md、单关键字精确查找（直接 grep 记忆目录）。
---

# metacognition-recall

在会话中按需对 `~/.claude/projects/<slug>/memory/` 做一次语义召回，产出一块高密度注入供当前任务使用。本 skill 只读不写——沉淀走 `metacognition-reflect`。

## 何时触发

- 用户显式调用：`/recall`、"查下记忆"、"之前怎么处理的"、"有没有踩过这个坑"
- 任务启动前自检：涉及多 feature / 历史决策 / 看似踩过的坑时主动跑一次
- 注意：SessionStart 已注入 top-N 静态提醒，若本轮任务恰好被覆盖则跳过本 skill 避免重复

## 执行流程

### 1. 解析 query

从用户消息或当前任务中抽出 **主题关键词**（2–5 个）和 **召回意图**（事实 / 偏差 / 决策 / 全部）。

举例：
- "查下之前怎么接入新链的" → 主题=`[新链, blockchain, chain 接入]`，意图=`决策+事实`
- "有没有踩过 TanStack Query 的坑" → 主题=`[TanStack Query, query cache]`，意图=`偏差+事实`

### 2. 拆分独立检索单元（并发调度）

**独立**指两个子问题的答案不互相依赖。典型拆法：
- 按数据层拆：`tech_facts.jsonl` / `biases.md` / `decisions.md` / `judgments.jsonl`
- 按主题拆：多主题时每个主题一个子单元

**用 Agent 并行发起**（单条消息内多个 tool call）。每个子代理拿到：
- 数据文件绝对路径
- 主题关键词列表
- 输出上限：每子代理 ≤ 150 字中文摘要 + ≤ 3 条原文引用

### 3. 聚合去重

把子代理结果合并：
- 同一 claim 只保留最新 `verified_at` 的一条
- tech_fact 被 `superseded_by` 指向的不要输出
- bias 按状态优先级：🔴 active > 🟡 watching > ⚪ dormant
- 总输出 ≤ 600 字（大约 2000 字节），超过按 hit_count / recency 截断

### 4. 注入到当前工作流

把聚合结果以一段 markdown 回报给主 Agent 自己（也就是在本轮响应里引用），**不要写入 memory 文件**。格式：

```
## 记忆召回：<query 摘要>

**相关事实**（来自 tech_facts.jsonl）
- ...

**相关偏差**（来自 biases.md）
- ...

**相关历史决策**（来自 decisions.md）
- ...
```

若所有桶都空，回一句"记忆层无相关条目，按常规流程处理"即可，不要编造。

## 并发模板（抄这个，别每次都现想）

```
Agent(subagent_type=Explore, description="召回 tech_facts", prompt="读 ~/.claude/projects/<slug>/memory/metacognition/tech_facts.jsonl，筛出 claim / topic / scope 含关键词 [X, Y, Z] 的条目（忽略 superseded_by 非空的）。按 verified_at 倒序返回 ≤ 5 条，每条给 id + claim + evidence。≤ 150 字中文摘要。")

Agent(subagent_type=Explore, description="召回 biases", prompt="读 ~/.../biases.md 和 _biases_store.jsonl，筛出 pattern / counter / category 含关键词 [X, Y, Z] 的条目。优先返回 active 状态，其次 watching。每条给 pattern + counter + hit_count。≤ 150 字。")

Agent(subagent_type=Explore, description="召回 decisions", prompt="读 ~/.../decisions.md 和 judgments.jsonl，筛出与 [X, Y, Z] 相关的决策或判断。决策优先（更浓缩），judgments 只在决策空时补。≤ 150 字。")
```

三个 Explore 一条消息发完，等全部回来再聚合。

## 铁律

- **不污染**：本 skill 全程只读，不调 apply_reflection.py，不改任何 .md/.jsonl
- **不重复 SessionStart 注入**：若 SessionStart 已覆盖当前主题（看 `## 元认知提醒` 块），跳过本 skill
- **短**：最终注入 ≤ 600 字。宁可少给也不要塞满
- **诚实**：记忆层为空就说为空，不要用"通识"假扮记忆命中
- **子代理返回的内容可能过时**：若要据此给用户建议，按 CLAUDE.md 的"Before recommending from memory"规则，先 grep / Read 验证当前代码状态

## 与其它 skill 的分工

| 场景 | 用哪个 |
|---|---|
| 会话起点 top-N 静态提醒 | SessionStart hook（`select_relevant.sh`，自动） |
| 任务进行中按主题查记忆 | **本 skill** |
| 会话结尾沉淀新认知 | `metacognition-reflect` |
| 搜代码 / 文档 | Explore / grep，不走记忆层 |

## 相关路径

- 数据层：`~/.claude/projects/-Users-you-projects-your-app/memory/metacognition/`
- 静态注入脚本：`~/.claude/scripts/metacog/select_relevant.sh`
- 沉淀脚本：`~/.claude/scripts/metacog/reflect.sh`
