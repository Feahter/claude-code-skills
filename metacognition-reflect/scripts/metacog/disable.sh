#!/usr/bin/env bash
# 反向：从 settings.json 移除元认知 hooks，unload LaunchAgent
# 不删除数据层，不删除脚本本身

set -euo pipefail
SETTINGS="$HOME/.claude/settings.json"
PLIST="$HOME/Library/LaunchAgents/com.fez.claude-metacog.plist"
BACKUP="$SETTINGS.bak-metacog-disable-$(date +%Y%m%d-%H%M%S)"

[ -f "$SETTINGS" ] || { echo "settings.json 不存在"; exit 1; }
command -v jq >/dev/null || { echo "需要 jq"; exit 1; }

cp "$SETTINGS" "$BACKUP"
echo "已备份到 $BACKUP"

tmp="$(mktemp)"
jq '
  (.hooks.SessionStart // []) as $s |
  (.hooks.SessionEnd // []) as $e |
  .hooks.SessionStart = ($s | map(select(.hooks[0].command | test("metacog/select_relevant") | not)))
  | .hooks.SessionEnd = ($e | map(select(.hooks[0].command | test("metacog/quick_tag") | not)))
  | if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end
  | if (.hooks.SessionEnd | length) == 0 then del(.hooks.SessionEnd) else . end
' "$SETTINGS" > "$tmp"

jq empty "$tmp" && mv "$tmp" "$SETTINGS"
echo "settings.json 的元认知 hooks 已移除（Stop / PostToolUse 保留）"

if launchctl list 2>/dev/null | grep -q com.fez.claude-metacog; then
  launchctl unload "$PLIST" 2>/dev/null || true
  echo "LaunchAgent 已卸载"
fi

echo "完成。数据层和脚本本身未动——如需彻底清理，手动删除 ~/.claude/scripts/metacog/ 和 memory/metacognition/"
