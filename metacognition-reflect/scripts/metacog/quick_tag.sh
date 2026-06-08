#!/usr/bin/env bash
# SessionEnd hook（若 SessionEnd 不可用则挂 Stop，用 messageId 去重）
# 扫描 transcript 的最后 N 条消息，命中元认知相关模式就把片段写入 pending_reflection/
# 目标：< 1 秒返回，不做深分析、不调 claude

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_lib.sh"

trap 'metacog_log "quick_tag FAILED at line $LINENO"; exit 0' ERR

INPUT="$(metacog_read_stdin_capped 32768)"
CWD="$PWD"
TRANSCRIPT=""
SESSION_ID=""

if metacog_has_jq && [ -n "$INPUT" ]; then
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
  SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
  [ -z "$CWD" ] && CWD="$PWD"
fi

MEMDIR="$(metacog_memdir_for_cwd "$CWD")"
PENDING="$MEMDIR/metacognition/pending_reflection"
mkdir -p "$PENDING" 2>/dev/null || { metacog_log "quick_tag: cannot mkdir $PENDING"; exit 0; }

# 如果没有 transcript 路径，尝试在 ~/.claude/projects 下按 session_id 找最新 jsonl
if [ -z "$TRANSCRIPT" ] || [ ! -s "$TRANSCRIPT" ]; then
  if [ -n "$SESSION_ID" ]; then
    TRANSCRIPT="$(ls -t "$HOME/.claude/projects"/*/*"$SESSION_ID"*.jsonl 2>/dev/null | head -1 || true)"
  fi
fi

if [ -z "$TRANSCRIPT" ] || [ ! -s "$TRANSCRIPT" ]; then
  metacog_log "quick_tag: no transcript available (session=$SESSION_ID)"
  exit 0
fi

# 只扫最后 200 行（上下文够用，速度够快）
TAIL_LINES=200
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
tail -n "$TAIL_LINES" "$TRANSCRIPT" > "$TMP"

# 抓四类标签
# 使用 jq 解析每条 JSONL，只看 user / assistant 的 text 内容
hits="$(mktemp)"
trap 'rm -f "$TMP" "$hits"' EXIT

if ! metacog_has_jq; then
  metacog_log "quick_tag: jq not available, skipping"
  exit 0
fi

# 逐行 jq 抽文本（允许单条失败）
while IFS= read -r line; do
  # 抽 user content.text 或 assistant content[].text
  role="$(echo "$line" | jq -r '.message.role // .type // empty' 2>/dev/null || true)"
  text="$(echo "$line" | jq -r '
    .message.content as $c |
    if ($c | type) == "string" then $c
    elif ($c | type) == "array" then
      [$c[] | select(.type == "text") | .text] | join("\n")
    else empty end' 2>/dev/null || true)"
  [ -z "$text" ] && continue

  tag=""
  if [ "$role" = "user" ]; then
    # 用户纠正
    if echo "$text" | grep -qE '不对|错了|理解错|你搞错|重新|别这么|不是这|你理解偏' ; then
      tag="CORRECTION"
    # 用户确认（粗标，reflect 阶段再甄别）
    elif echo "$text" | grep -qE '^(对|ok|正确|完美|就是这|可以|1|同意)[。.!！]?$' ; then
      tag="CONFIRMATION"
    fi
  elif [ "$role" = "assistant" ]; then
    # 结构化判断：「假设」+「证据」+「置信度」三词共现才算
    if echo "$text" | grep -q '假设' && echo "$text" | grep -qE '证据|verify|验证' && echo "$text" | grep -q '置信度' ; then
      tag="STRUCTURED_JUDGMENT"
    fi
    # 验证失败：tsc / error / 测试 fail
    if echo "$text" | grep -qE 'tsc.*error|TypeScript error|测试失败|test.*fail|FAIL|throw new Error' ; then
      tag="${tag:-VERIFICATION_FAIL}"
    fi
  fi

  if [ -n "$tag" ]; then
    # 片段限 800 字以内
    snippet="$(echo "$text" | head -c 800)"
    printf '{"tag":%s,"role":%s,"snippet":%s}\n' \
      "$(printf '%s' "$tag" | jq -Rs .)" \
      "$(printf '%s' "$role" | jq -Rs .)" \
      "$(printf '%s' "$snippet" | jq -Rs .)" >> "$hits"
  fi
done < "$TMP"

hit_count="$(wc -l < "$hits" | tr -d ' ')"
if [ "$hit_count" -eq 0 ]; then
  metacog_log "quick_tag: no hits in $TRANSCRIPT"
  exit 0
fi

# 生成 pending 文件
ts="$(date -u +%Y%m%dT%H%M%SZ)"
[ -z "$SESSION_ID" ] && SESSION_ID="unknown_$ts"
OUT="$PENDING/${ts}_${SESSION_ID}.json"

# 汇总成一个 JSON
jq -s '{session_id: $sid, cwd: $cwd, transcript: $tp, recorded_at: $ts, hits: .}' \
  --arg sid "$SESSION_ID" \
  --arg cwd "$CWD" \
  --arg tp "$TRANSCRIPT" \
  --arg ts "$ts" \
  "$hits" > "$OUT" 2>/dev/null || {
    metacog_log "quick_tag: failed to write $OUT"
    exit 0
  }

metacog_log "quick_tag: wrote $OUT (hits=$hit_count)"
exit 0
