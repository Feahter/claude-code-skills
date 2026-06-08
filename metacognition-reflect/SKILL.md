---
name: metacognition-reflect
description: 对当前会话做元认知复盘——把本轮关键判断（假设/证据/置信度）、用户纠正与确认、tsc/测试验证失败事件抽成结构化 JSON 入队，并调 reflect.sh 合并到 memory/metacognition/。触发：用户说"复盘/复盘本次对话/沉淀本轮认知/总结本次协作/reflect"，或"以后别再这样/记下这个坑/这个偏差记一下"。不适用：纯代码审查（code-review-expert）、常规 commit 生成、会话过短（<5 轮）且无明显判断。
---

# metacognition-reflect

在当前会话结束前做一次元认知复盘，把判断、偏差、已验证事实沉淀到 `~/.claude/projects/<slug>/memory/metacognition/`。

## 何时主动触发

用户消息命中以下任一：
- "复盘一下"、"总结本次"、"沉淀认知"、"/reflect"
- "记下这个坑"、"别再犯这个错"、"这个偏差记一下"
- 会话即将结束，用户说"没什么了 / 收工 / 结束"——本轮改动大（> 5 次 Edit/Write）时主动建议复盘

## 执行流程

### 1. 扫当前会话 transcript

用 `Bash` 找最新 jsonl：

```bash
ls -t ~/.claude/projects/-Users-you-projects-your-app/*.jsonl | head -1
```

（slug 按当前项目 cwd 推导；也可跳过这一步直接从你记忆中提取本轮关键事件）

### 2. 抽取候选条目

从 transcript 和你自己的记忆里，把这几类事件挑出来，合成一个 `hits` 数组：

| tag | 触发 | 抽取要点 |
|---|---|---|
| `CORRECTION` | 用户纠正你的判断 | 用户原话片段 + 你被纠正前的断言 |
| `CONFIRMATION` | 用户明确认可非显然的判断 | 你的判断 + 用户的确认原话 |
| `STRUCTURED_JUDGMENT` | 你产出了"假设+证据+置信度"结构 | 主题 / 假设 / 证据引用 / 置信度 / 结论 |
| `VERIFICATION_FAIL` | tsc / 测试 / build / grep 结果和你预期不符 | 预期 vs 实际 / 文件:行 |
| `TECH_DISCOVERY` | 通过 Read/grep/context7 验证了某个可复用的技术事实 | scope / topic / claim / evidence |

### 3. 写入 pending

把 hits 写到 `<memdir>/metacognition/pending_reflection/<ts>_manual_<sessionId>.json`，结构同 quick_tag.sh 产物：

```json
{
  "session_id": "...",
  "cwd": "...",
  "transcript": "...",
  "recorded_at": "YYYYMMDDTHHMMSSZ",
  "hits": [ ... ]
}
```

### 4. 触发 reflect.sh

```bash
bash ~/.claude/scripts/metacog/reflect.sh
```

脚本会：
- 聚合 pending
- 用 headless claude 按 reflect_prompt.md 产生 diff JSON
- 跑 apply_reflection.py 写入 memory
- 把 pending 移到 _archive/

如果 reflect.sh 因为网络 / token 预算问题失败，**不要重试**。告诉用户：「pending 已入队，下次自动批处理会处理到。」

### 5. 汇报

只报 apply_reflection 的 metrics 数字（judgments_added / tech_facts_added / biases_changed），外加一句自然语言总结"这次主要沉淀了 X"。不要贴大段 JSON。

## 铁律

- **不要伪造 hit**。transcript 和上下文里确实没有的，不补。宁可少记也不能污染。
- **不要在本 skill 里直接改 biases.md**。所有更新走 apply_reflection.py，保持单一入口。
- **CONFIRMATION 要谨慎**。用户随口 "ok" 不是背书，reflect_prompt.md 里已有规则，本 skill 只需如实抽取。
- **高置信度判断被纠正 → 高优先级标记**。在 hits 里明确标注，让反思员能识别"过度自信"模式。

## 相关文件

- 数据层：`~/.claude/projects/-Users-you-projects-your-app/memory/metacognition/`
- 反思员 prompt：`~/.claude/scripts/metacog/reflect_prompt.md`
- 应用脚本：`~/.claude/scripts/metacog/apply_reflection.py`
- 手动入口：`~/.claude/scripts/metacog/reflect.sh`
- 自动入队（SessionEnd hook）：`~/.claude/scripts/metacog/quick_tag.sh`
