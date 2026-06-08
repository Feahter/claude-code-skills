#!/usr/bin/env bash
# Phase 0 probe #3: 验证 headless `claude -p` 能在非交互模式读写文件
# 直接跑即可，不需要改 settings.json

set -eu

LOG=/tmp/metacog_probe.log
TESTDIR=/tmp/metacog_headless_test
rm -rf "$TESTDIR" && mkdir -p "$TESTDIR"
echo "initial line" > "$TESTDIR/input.md"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] headless probe START" >> "$LOG"

# 尝试最严格的 bare 模式：禁 skill/MCP 自动加载、限工具
# 若 claude CLI 不支持 --bare，降级到只 --print
OUT=""
if claude --help 2>/dev/null | grep -q -- '--bare'; then
  OUT=$(claude -p --bare --no-session-persistence \
        --allowedTools "Read,Write" \
        --permission-mode bypassPermissions \
        "读取 $TESTDIR/input.md 的内容，然后在 $TESTDIR/output.md 中写入：HEADLESS_OK 后跟 input.md 里的第一行内容。不要做其他事。" 2>&1)
else
  OUT=$(claude -p --no-session-persistence \
        --allowedTools "Read,Write" \
        --permission-mode bypassPermissions \
        "读取 $TESTDIR/input.md 的内容，然后在 $TESTDIR/output.md 中写入：HEADLESS_OK 后跟 input.md 里的第一行内容。不要做其他事。" 2>&1)
fi

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] headless probe END" >> "$LOG"
echo "--- output.md ---" >> "$LOG"
cat "$TESTDIR/output.md" 2>/dev/null >> "$LOG" || echo "(output.md not created)" >> "$LOG"
echo "--- stdout tail ---" >> "$LOG"
echo "$OUT" | tail -c 500 >> "$LOG"
echo "" >> "$LOG"

if [ -f "$TESTDIR/output.md" ] && grep -q "HEADLESS_OK" "$TESTDIR/output.md"; then
  echo "PASS: headless claude 能读写文件。日志见 $LOG"
  exit 0
else
  echo "FAIL: headless claude 未写出期望的 output.md。日志见 $LOG"
  exit 1
fi
