# CC track · slash command / hook 配置优化

settings.json 里的 hook 配置 或 `.claude/commands/` 下的 slash command 定义。

**能力边界**：轻量通用建议。核心毛病是"事件选错、matcher 粗糙、block 副作用"。

## 诊断清单（四条）

### ① 事件类型选对没

hook 事件类型有固定语义，选错就永远不触发或在错误时机触发。

- **常见事件**：`UserPromptSubmit`（用户提交前）、`PreToolUse`（工具调用前）、`PostToolUse`、`Stop`（回合结束）、`SubagentStop`
- **失败表现**：
  - 想在"Claude 要跑 Bash 之前拦截"，却挂在 `UserPromptSubmit`
  - 想在"Claude 回答完给提示"，却挂在 `PreToolUse`
- **诊断手段**：读 hook 的实际用途 → 对照事件语义

### ② matcher 精准度

hook 的 matcher 决定了什么情况下触发。

- **失败表现**：
  - matcher 写得太宽（`.*`）→ 所有工具调用都触发，性能炸
  - matcher 写得太窄（`exact tool name`）→ 漏掉变体
- **修法**：用具体的工具名或工具名前缀，避免正则通配

### ③ block / 中断副作用

hook 可以 block 执行（返回非零或 deny）。block 的场景选错会打断正常流程。

- **失败表现**：
  - 在 `Stop` 事件里 block → 强制 Claude 继续干活，可能陷入死循环
  - `PreToolUse` 无条件 block 某工具 → 整类任务做不了
- **修法**：block 要有**明确的触发条件**和**用户可见的提示**，不要静默拦截

### ④ settings 层级归属

hook 放在哪个层级决定了作用范围。

- **层级**：user settings（全局）→ project settings（项目级）→ local settings（不提交）
- **失败表现**：
  - 项目专属 hook 放进 user settings → 所有项目都受影响
  - 通用的权限 allowlist 写在 project settings → 换项目要重新配
- **修法**：按"专属度"放对应层；不确定时先放 local 验证

---

## 输出模板

```markdown
## 诊断结论

- [① 事件类型] ❌ 选错：用户想"工具调用前拦 Bash"，但 hook 挂在 `UserPromptSubmit`
- [② matcher 精准度] ⚠️ 过宽：matcher = `.*`，所有工具都触发
- [③ block 副作用] ⚠️ 风险：Stop 事件里 block 但没提示用户，可能陷入循环
- [④ 层级归属] ❌ 放错：项目专属 hook 写进了 ~/.claude/settings.json

## 改写版

<原始配置>

改写后：
- event: "PreToolUse" [① 调整]
- matcher: "Bash" [② 调整]
- 改到 <project-root>/.claude/settings.json [④ 调整]
- block 时输出一条用户可见提示："已拦截 rm -rf，请手动确认" [③ 调整]
```

---

## 常见反模式

| 反模式 | 修法 |
|---|---|
| hook 事件凭直觉猜 | 查官方文档确认事件语义 |
| matcher 写 `.*` 一把梭 | 用具体工具名/前缀 |
| 静默 block 无提示 | 任何 block 都要输出给用户 |
| 项目专属规则放全局 | 专属度越高放越靠下（user → project → local） |
| 一个 hook 干多件事 | 拆成多个单一职责 hook |

## 参考

对 settings.json 更系统的改动建议用 `update-config` skill 处理；本文档只覆盖"诊断配好了为什么不生效"这个维度。
