---
name: prompt-optimizer
description: 优化 prompt 文本（Claude Code 资产 或 Anthropic API 调用 prompt）。当用户说"优化这个 prompt"、"我这个 skill 怎么没触发"、"description 怎么写更好"、"帮我改写这段 system prompt"、"这个 agent prompt 有什么问题"、"诊断我的 prompt"、"prompt 优化"、"prompt 诊断"、"CLAUDE.md 没生效"时触发。输入是 prompt 文本本身，输出是诊断结论 + 带维度标签的改写版。不做 A/B 测试、不跑 eval、不涉及模型选型。
---

# prompt-optimizer

优化 prompt 文本。按 track 分流，按资产类型按需加载子文档。

## 入口判断（必做第一步）

用户贴进来的内容属于哪个 track？基于文本特征判断，**不确定就反问**。

### CC track（Claude Code 资产）强信号

- 出现 frontmatter（`---` 包住的 `name:` / `description:` 字段）
- 出现 `skill` / `agent` / `subagent` / `Task(` / `CLAUDE.md` / `settings.json` / `hook` / `slash command`
- 文件路径包含 `.claude/skills/` 或 `.claude/agents/` 或 `~/.claude/`
- 用户说"触发/没触发/误触发/被加载"

### API track（Anthropic SDK prompt）强信号

- 出现 `anthropic.messages.create` / `system=` / `messages=[`
- 代码片段包含 `temperature` / `cache_control` / `stop_sequences`
- 文本明显是"发给大模型的 system prompt 正文"但不带 frontmatter
- 用户说"system prompt" / "发给模型的 prompt" / "我在代码里这样写"

### 不确定信号 → 反问

只有一段纯文本、没有上下文线索时，问一次：

> 你要优化的是 **Claude Code 资产**（skill description / agent prompt / CLAUDE.md / slash command）还是 **Anthropic API 代码里的 system prompt**？

不要自己猜。判错一次整轮诊断就白费。

### 混合输入处理

用户一次贴了两种资产：不合并处理，让用户选先做哪一个。对称诊断结构但不共享改写。

---

## CC track 资产分流

判定是 CC track 后，进一步识别资产类型，加载对应子文档：

| 资产类型 | 识别信号 | 加载文档 |
|---|---|---|
| skill description | frontmatter `description:` 字段、问"skill 没触发" | `track-cc/skill-description.md` |
| agent prompt | `Task(prompt=...)` / `Agent(prompt=...)` / 子 agent 任务描述 | `track-cc/agent-prompt.md` |
| CLAUDE.md 指令 | 文件名 CLAUDE.md / 目录级指令 / 问"规则没生效" | `track-cc/claude-md.md` |
| slash command / hook | settings.json 配置 / hook 定义 / slash command 文件 | `track-cc/slash-command-hook.md` |

识别不出来时反问："这是 skill description / agent prompt / CLAUDE.md / slash command-hook 哪一类？"

---

## API track 分流

判定是 API track 后，加载 `track-api/static-scan.md`。

**能力边界**（先说清楚）：API track 只做 **prompt 文本静态扫描**，不诊断症状（输出崩、JSON 漂移、幻觉等），不跑样本。用户只要能贴出 prompt 文本就能扫。

---

## 通用输出规范（所有 track 统一遵守）

每次诊断输出**三段结构**：

```
## 诊断结论
逐条列出每个维度的命中情况（过 / 缺失 / 有问题 + 一句话说明）

## 改写版
贴出完整改写后的 prompt 文本。每处新增/修改的片段后面带维度标签 [X 新增] / [X 调整]。

## 可选深度诊断（仅 CC track 的 skill description 有此段）
询问用户是否跑 C（跨 skill 冲突扫描）/ J（负样本回放）
```

### 硬规则

1. **保留原始 prompt**，只产出建议版本，不主动替用户改文件
2. **改写版必须带维度标签**（如 `[A 新增]` / `[β 调整]`），用户能一眼看懂每处为什么改
3. **不伪装能力**——API track 不假装诊断症状级问题；CC track 的 agent-prompt/claude-md/slash-command-hook 是轻量通用建议，不如 skill-description 深入，要显式告知
4. **C/J 不主动跑**，用户显式同意后再执行
5. **混合贴入**：一次对话里贴了两种资产，分两轮处理，不交叉合并

---

## 跑完自检

产出改写版后，必做一次自检：

- 每处改动是否都能追溯到一个维度标签？没标签的改动删掉
- 改写版有没有改变用户的**原始意图**？如果有歧义，选更保守的一版并显式提醒
- 用户贴的是"半截片段"（比如只有 description 没有 frontmatter）时，改写版要**保持相同粒度**，不要自作主张补全上下文
