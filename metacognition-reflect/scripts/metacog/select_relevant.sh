#!/usr/bin/env bash
# SessionStart hook: 按当前项目 scope 选出最相关的元认知卡，注入系统提示
# 输入：stdin JSON { "session_id": "...", "cwd": "...", "transcript_path": "..." }
# 输出：stdout JSON { "hookSpecificOutput": { "hookEventName": "SessionStart", "additionalContext": "..." } }
#
# 预算：注入文本 < 400 字。超过时按 hit_count / 新鲜度截断。

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_lib.sh"

# 有 bug 也不能阻塞会话启动 → 任何失败都走 fallback 静默
trap 'metacog_log "select_relevant FAILED at line $LINENO"; echo "{}"; exit 0' ERR

INPUT="$(metacog_read_stdin_capped 16384)"
CWD="$PWD"
if metacog_has_jq && [ -n "$INPUT" ]; then
  maybe_cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  [ -n "$maybe_cwd" ] && CWD="$maybe_cwd"
fi

MEMDIR="$(metacog_memdir_for_cwd "$CWD")"
if [ ! -d "$MEMDIR/metacognition" ]; then
  # 当前项目还没建元认知层，直接静默
  echo "{}"
  exit 0
fi

TECH="$MEMDIR/metacognition/tech_facts.jsonl"
BIAS="$MEMDIR/metacognition/biases.md"

# 取 tech_facts 最近 30 天 verified 的前 3 条（按 verified_at 倒序）
tech_lines=""
if [ -s "$TECH" ] && metacog_has_jq; then
  cutoff="$(date -u -v-30d +%Y-%m-%d 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%d 2>/dev/null || echo '1970-01-01')"
  tech_lines="$(jq -r --arg cut "$cutoff" \
    'select(.superseded_by == null) | select(.verified_at != null) | select(.verified_at >= $cut) | "- " + .claim' \
    "$TECH" 2>/dev/null | head -n 3)"
fi

# 取 biases.md 中 🔴 active 的前 2 条（按 "- **pattern**:" 粗匹配）
bias_lines=""
if [ -s "$BIAS" ]; then
  bias_lines="$(awk '
    /^### 🔴 active/ { active=1; next }
    /^### 🟡 watching|^### ⚪ dormant|^## / { active=0 }
    active && /^- \*\*pattern\*\*:/ {
      sub(/^- \*\*pattern\*\*:[ ]*/, "");
      print "- " $0;
    }
  ' "$BIAS" | head -n 2)"
fi

# 没内容就静默，别给会话加噪音
if [ -z "$tech_lines" ] && [ -z "$bias_lines" ]; then
  echo "{}"
  exit 0
fi

{
  echo "## 元认知提醒（仅高风险场景参考）"
  if [ -n "$tech_lines" ]; then
    echo ""
    echo "**本项目已验证事实**:"
    echo "$tech_lines"
  fi
  if [ -n "$bias_lines" ]; then
    echo ""
    echo "**最近常犯偏差**:"
    echo "$bias_lines"
  fi
} > /tmp/metacog_injection.txt

# 截到 1200 字节（约 400 汉字）以内
head -c 1200 /tmp/metacog_injection.txt > /tmp/metacog_injection_capped.txt

if metacog_has_jq; then
  jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' \
    < /tmp/metacog_injection_capped.txt
else
  # 无 jq 兜底：手工转义
  content="$(cat /tmp/metacog_injection_capped.txt | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$content"
fi

metacog_log "select_relevant injected tech=$(echo "$tech_lines" | wc -l | tr -d ' ') bias=$(echo "$bias_lines" | wc -l | tr -d ' ')"
exit 0
