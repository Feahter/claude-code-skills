#!/usr/bin/env bash
# 一键启用元认知 harness：加 hooks 到 ~/.claude/settings.json 并 load LaunchAgent
# 反向：disable.sh
# 前提：Phase 0 probe 已 PASS

set -euo pipefail
SETTINGS="$HOME/.claude/settings.json"
PLIST="$HOME/Library/LaunchAgents/com.fez.claude-metacog.plist"
BACKUP="$SETTINGS.bak-metacog-enable-$(date +%Y%m%d-%H%M%S)"

[ -f "$SETTINGS" ] || { echo "settings.json 不存在：$SETTINGS"; exit 1; }
command -v jq >/dev/null || { echo "需要 jq"; exit 1; }

cp "$SETTINGS" "$BACKUP"
echo "已备份到 $BACKUP"

# 用 jq 合并 hooks（保留已有 Stop/PostToolUse，追加 SessionStart/SessionEnd）
tmp="$(mktemp)"
jq '
  .hooks.SessionStart = (
    (.hooks.SessionStart // []) +
    [{"matcher":"","hooks":[{"type":"command","command":"'"$HOME"'/.claude/scripts/metacog/select_relevant.sh"}]}]
    | unique_by(.hooks[0].command)
  )
  | .hooks.SessionEnd = (
    (.hooks.SessionEnd // []) +
    [{"matcher":"","hooks":[{"type":"command","command":"'"$HOME"'/.claude/scripts/metacog/quick_tag.sh"}]}]
    | unique_by(.hooks[0].command)
  )
' "$SETTINGS" > "$tmp"

# 合法性校验
jq empty "$tmp" && mv "$tmp" "$SETTINGS"
echo "settings.json 已更新，新增 SessionStart / SessionEnd hook"

# 如果 SessionEnd 在 Phase 0 probe 中验证不可用，用户应该手工把 SessionEnd 改成 Stop 并在 quick_tag.sh 里加去重
# 本脚本默认认为 SessionEnd 可用

# LaunchAgent
if [ -f "$PLIST" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load -w "$PLIST"
  echo "LaunchAgent 已加载：每天 03:00 跑 reflect.sh"
else
  echo "⚠️  plist 不存在：$PLIST，LaunchAgent 未启用"
fi

echo ""
echo "完成。查看状态：launchctl list | grep com.fez.claude-metacog"
echo "查看日志：tail -f /tmp/metacog.log"
echo "停用：bash ~/.claude/scripts/metacog/disable.sh"
