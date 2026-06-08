# Phase 0 Probes —— 跑完再进 Phase 1

目的：在动真格改 settings.json 和写一堆脚本之前，先把三个未被官方文档明确说明、或风险较高的能力点拉通。

## 总开关

日志统一落 `/tmp/metacog_probe.log`。三个 probe 相互独立。

## Probe 1 — SessionStart additionalContext 注入

**不要直接跑脚本，它只是个 hook 载荷。**

1. 临时在 `~/.claude/settings.json` 的 `hooks` 节点里加一段：

```json
"SessionStart": [
  {
    "matcher": "",
    "hooks": [
      { "type": "command", "command": "/Users/<you>/.claude/scripts/metacog/probe/probe_session_start.sh" }
    ]
  }
]
```

2. **起一个全新的 Claude Code 会话**（新终端 / `claude`）。
3. 问一句：「你看到 TEST_METACOG_MARKER_4591 了吗？」
4. 观察：
   - **PASS**：回答里明确包含 `TEST_METACOG_MARKER_4591`
   - **FAIL**：回答说没看到 / 询问这是什么 → 退路到 UserPromptSubmit hook（见下）
5. `tail /tmp/metacog_probe.log` 至少能看到 "SessionStart probe fired"，说明 hook 至少被触发；FAIL 时说明事件触发了但 additionalContext 没生效。
6. **验证完务必从 settings.json 删掉这段临时 SessionStart**。

### FAIL 时的退路

用 `UserPromptSubmit` hook 拦截用户的每条消息，在 stdout 里 `echo` 注入文本——它走的是另一个 additionalContext 字段。脚本稍后补。

## Probe 2 — SessionEnd 事件是否存在

1. 临时在 `~/.claude/settings.json` 的 `hooks` 里加：

```json
"SessionEnd": [
  {
    "matcher": "",
    "hooks": [
      { "type": "command", "command": "/Users/<you>/.claude/scripts/metacog/probe/probe_session_end.sh" }
    ]
  }
]
```

2. 起一个会话，随便问一句，然后 `/exit` 或关终端。
3. `grep "SessionEnd fired" /tmp/metacog_probe.log`
4. 观察：
   - **PASS**：log 有追加
   - **FAIL**：log 没变化 → 退路到 `Stop` hook（每次 Claude 回答完就触发，需要在 quick_tag.sh 里记录最后处理过的 messageId 避免重复入队）
5. **验证完删掉 SessionEnd**。

## Probe 3 — Headless claude 读写文件

直接跑：
```bash
bash /Users/<you>/.claude/scripts/metacog/probe/probe_headless.sh
```

退出码 0 = PASS；非 0 = FAIL。FAIL 时退路到 `claude -p` 不走 bare，或改用本地 python 脚本做反思合并（reflect.sh 中 claude 那一步改为模板拼接 + 人工 review）。

## Go/No-Go 汇总

写一份最简记录到 `/tmp/metacog_phase0.md`：

```
probe1 SessionStart additionalContext: PASS / FAIL(退路=X)
probe2 SessionEnd: PASS / FAIL(退路=X)
probe3 headless claude: PASS / FAIL(退路=X)
```

三个都 PASS → 进 Phase 1 全速铺开。
有 FAIL → 回来调整 Phase 1/2/3 方案（具体退路见上文）。
