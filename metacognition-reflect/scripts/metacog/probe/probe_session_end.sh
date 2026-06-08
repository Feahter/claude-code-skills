#!/usr/bin/env bash
# Phase 0 probe #2: 验证 SessionEnd hook 是否真的会触发
# 用法：
#   1. 临时在 ~/.claude/settings.json 的 hooks 里加：
#        "SessionEnd": [{"matcher":"","hooks":[{"type":"command","command":"~/.claude/scripts/metacog/probe/probe_session_end.sh"}]}]
#   2. 正常起一个会话，随便问一句，然后 /exit 或关闭终端
#   3. 看 /tmp/metacog_probe.log 是否追加了 "SessionEnd fired" → 有则 PASS
#   4. 如果 SessionEnd 不触发 → 退路到 Stop hook（每轮响应结束都会触发，需去重）

set -eu

# 把 stdin 里的 session 元信息也记下来（若有）
INPUT="$(cat 2>/dev/null || true)"
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SessionEnd fired | stdin_bytes=${#INPUT}" >> /tmp/metacog_probe.log
if [ -n "$INPUT" ]; then
  echo "--- stdin payload ---" >> /tmp/metacog_probe.log
  echo "$INPUT" | head -c 500 >> /tmp/metacog_probe.log
  echo "" >> /tmp/metacog_probe.log
fi

exit 0
