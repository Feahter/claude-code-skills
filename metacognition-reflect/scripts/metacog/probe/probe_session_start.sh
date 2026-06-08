#!/usr/bin/env bash
# Phase 0 probe #1: 验证 SessionStart hook 能否通过 additionalContext 注入系统提示
# 用法：
#   1. 临时在 ~/.claude/settings.json 的 hooks 里加：
#        "SessionStart": [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/scripts/metacog/probe/probe_session_start.sh"}]}]
#   2. 起一个新会话，问 Claude：「你看到 TEST_METACOG_MARKER_4591 了吗？」
#   3. 如果回答里明确提到这个 marker → additionalContext 机制可用 → PASS
#   4. 验证完记得把临时加的 SessionStart 从 settings.json 删除

set -eu

# 记录触发本身（证明 hook 至少被调起来了）
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SessionStart probe fired" >> /tmp/metacog_probe.log

# 吞掉 stdin 防 SIGPIPE
cat >/dev/null 2>&1 || true

# 按官方 schema 输出 additionalContext
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"=== METACOG PROBE ===\nTEST_METACOG_MARKER_4591\n如果你在会话中看到这行文本，请明确回复该 marker，用于验证 SessionStart additionalContext 注入是否生效。\n===================="}}
JSON
