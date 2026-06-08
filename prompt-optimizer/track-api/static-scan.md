# API track · Anthropic SDK prompt 静态扫

用户贴进来的是发给 Anthropic API 的 prompt 文本（通常是 system prompt 正文）。

**能力边界**：
- 只扫 prompt **文本本身**，不读代码、不要样本、不诊断症状（JSON 崩、输出漂移等）
- 只指出**静态缺陷**，不承诺解决运行时问题
- 用户有症状和样本 → 建议走 `diagnose` skill 或升级到带样本的诊断模式（暂未实现）

## 诊断维度（五条）

### α 角色定义

system prompt 开头有没有明确身份 + 任务范围？

- **通过条件**：前几句话说清楚"你是 X 领域的助手，负责 Y 类任务"
- **失败表现**：直接进入指令，没交代身份
- **修法模板**：`You are a <role> specialized in <domain>. Your task is to <scope>.`
- **对称**：这对应 CC track 的 D（动作-对象结构）

### β 结构分区

prompt 里有没有用 XML tag / markdown / 分隔符**区分不同内容块**？

- **典型块**：`<instructions>` 指令、`<examples>` 示例、`<context>` 背景、`<output_format>` 输出格式、`<user_input>` 待处理输入
- **失败表现**：一整段文本把指令和示例混在一起，模型可能把示例当真实输入执行
- **修法**：用 XML tag 分块（Anthropic 官方强烈推荐）
- **示例**：
  ```
  <instructions>分析下面的代码</instructions>
  <examples>...</examples>
  <code>{user_code}</code>
  ```

### γ 输出格式约束

有没有明确输出的格式？

- **通过条件**：给出 JSON schema / 字段列表 / 分隔符 / 长度限制
- **失败表现**：只说"输出结果"，不说格式
- **修法**：
  ```
  Output strictly as JSON matching this schema:
  {
    "summary": string,    // 100字以内
    "issues": string[]    // 每条一行
  }
  Do not include any text outside the JSON block.
  ```
- **硬建议**：要 JSON 时，**同时**设 `stop_sequences` 和用 `assistant` 前缀 `{` 做 prefill（这条属于代码层，超出静态扫但值得提醒）

### δ Negative examples / 禁止项

有没有写"不要做什么"？

- **通过条件**：出现 "Do not" / "Never" / "禁止" / "避免" 至少 1 处
- **失败表现**：全是正向指令，模型在灰色地带自由发挥
- **修法**：每条核心指令配对禁止项
  - ✅ `输出只能是 JSON。Do not add prose before or after.`
  - ✅ `分析要基于给出的代码。Never invent functions or files that don't appear in the input.`

### ε Few-shot 质量

prompt 里带了示例吗？质量如何？

- **通过条件**：
  - 示例数量 ≥ 2 条（1 条不够泛化）
  - 示例多样性（不全是同一种模式）
  - 有正有反（正例 + 易混淆的反例）
  - 示例和任务描述**一致**，不自相矛盾
- **失败表现**：
  - 完全没有示例（冷启动风险）
  - 只有 1 条示例 → 模型过拟合
  - 示例格式和指令要求的输出格式不一致
- **修法**：加 2-3 条覆盖典型 + 边界场景的示例；至少留 1 条反例

---

## 输出模板

```markdown
## 诊断结论

- [α 角色定义] ❌ 缺失：开头直接进入"请你帮我..."，没有身份声明
- [β 结构分区] ⚠️ 部分：指令和示例混在同一段，没有 XML tag 分块
- [γ 输出格式] ❌ 缺失：没说输出是什么格式
- [δ 禁止项] ❌ 缺失：全是正向指令
- [ε Few-shot] ⚠️ 不足：只有 1 条示例

## 改写版

<原 prompt>

改写后：
You are a code review assistant specialized in TypeScript. [α 新增]

<instructions>
对用户提供的代码做审查，按下面格式输出。
</instructions>

<output_format>
输出严格的 JSON，schema 如下：
{
  "severity": "high" | "medium" | "low",
  "issues": string[]
}
不要输出任何 JSON 以外的文字。Do not add prose. [γ 新增][δ 新增]
</output_format>

<examples>
<example>
Input: ...
Output: {"severity": "high", "issues": ["...", "..."]}
</example>
<example>  // 边界示例：无问题时返回空数组
Input: ...
Output: {"severity": "low", "issues": []}
</example>
</examples>  [β 新增][ε 补充]

<code_to_review>
{user_code}
</code_to_review>  [β 新增]
```

---

## 常见反模式

| 反模式 | 修法 |
|---|---|
| 整段散文式指令 | 用 XML tag 分块 |
| 只写"输出结果" | 明确 JSON schema + 禁止任何其他文字 |
| 示例和指令格式不一致 | 先对齐格式再给示例 |
| 只有 1 条示例 | 加到 2-3 条含边界 |
| 全是正向指令无禁止项 | 每条核心规则配 `Do not X` |
| 在 user message 里重复 system 指令 | 指令只放 system，user 只放数据 |

## 代码层建议（超出静态扫，仅提醒）

如果用户同时贴了调用代码，额外关注（但本 skill 不深入诊断）：

- `temperature`：要稳定输出就压低到 0 或 0.2
- `stop_sequences`：输出 JSON 时应设为 `["\n\n", "```"]` 之一
- `cache_control`：长 system prompt 记得加 `cache_control: {type: "ephemeral"}` 做 prompt caching
- **assistant prefill**：要 JSON 时在 messages 末尾加 `{"role": "assistant", "content": "{"}` 强制从 `{` 开始

这些属于 `claude-api` skill 的领域，复杂场景转那个 skill。
