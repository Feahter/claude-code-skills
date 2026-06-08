#!/usr/bin/env bash
# 每日反思：汇总 pending_reflection → headless claude 生成 diff → apply_reflection.py 应用
# 也可手动调用：bash reflect.sh [memdir]
#
# 默认走并发分桶路径（METACOG_PARALLEL=1）：
#   - 按 hits[].tag 把 pending 拆成两个桶：
#       judgments: STRUCTURED_JUDGMENT / VERIFICATION_FAIL / TECH_DISCOVERY
#       biases:    CORRECTION / CONFIRMATION
#   - 两个桶并发调 headless claude 生成各自的 diff JSON
#   - 串行喂给 apply_reflection.py（复用现成幂等逻辑）
# 关掉并发走原单桶：METACOG_PARALLEL=0 bash reflect.sh

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_lib.sh"

MEMDIR="${1:-}"
[ -z "$MEMDIR" ] && MEMDIR="$(metacog_default_memdir)"
PENDING="$MEMDIR/metacognition/pending_reflection"
TECH="$MEMDIR/metacognition/tech_facts.jsonl"
BIASES="$MEMDIR/metacognition/biases.md"

mkdir -p "$PENDING"

if ! compgen -G "$PENDING/*.json" > /dev/null 2>&1; then
  metacog_log "reflect: no pending items, exit"
  exit 0
fi

# 超过 20 条时分批
files=($(ls -t "$PENDING"/*.json 2>/dev/null | head -n 20))
metacog_log "reflect: processing ${#files[@]} pending files"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

PENDING_AGG="$WORKDIR/pending.json"
if metacog_has_jq; then
  jq -s '.' "${files[@]}" > "$PENDING_AGG"
else
  echo "[" > "$PENDING_AGG"
  for f in "${files[@]}"; do cat "$f"; echo ","; done >> "$PENDING_AGG"
  echo "null]" >> "$PENDING_AGG"
fi

TECH_RECENT="$WORKDIR/tech_recent.txt"
tail -n 20 "$TECH" 2>/dev/null > "$TECH_RECENT" || true

# 尝试 --bare，不支持则降级
BARE_FLAG=""
if claude --help 2>/dev/null | grep -q -- '--bare'; then
  BARE_FLAG="--bare"
fi

PARALLEL="${METACOG_PARALLEL:-1}"

# ---------- 并发分桶路径 ----------
run_bucket() {
  # $1: bucket name (judgments|biases)
  # $2: bucket pending file
  # $3: 给 prompt 的桶标签（中文）
  # $4: 输出 diff json 的路径
  local name="$1" bucket_file="$2" label="$3" out="$4"
  local err="$WORKDIR/reflect_${name}.err"
  local prompt="$WORKDIR/prompt_${name}.txt"

  {
    echo "=== PENDING (本轮仅含 ${label} 相关片段) ==="
    cat "$bucket_file"
    echo ""
    echo "=== EXISTING BIASES ==="
    cat "$BIASES" 2>/dev/null || echo "(empty)"
    echo ""
    echo "=== EXISTING TECH FACTS (recent 20) ==="
    cat "$TECH_RECENT"
    echo ""
    echo "=== TASK ==="
    echo "按照你的 system prompt 规定，**本轮只处理 ${label} 相关条目**。"
    echo "与本桶无关的字段一律返回空：数组给 []，decisions_append 给空字符串。"
    echo "只输出一个合法 JSON 对象，不要任何解释。"
  } > "$prompt"

  if claude -p $BARE_FLAG --no-session-persistence \
       --allowedTools "Read" \
       --permission-mode bypassPermissions \
       --append-system-prompt "$(cat "$SCRIPT_DIR/reflect_prompt.md")" \
       "$(cat "$prompt")" > "$out" 2>"$err"; then
    :
  else
    # 有些版本把响应塞到 stderr
    [ -s "$out" ] || cp "$err" "$out"
  fi
}

if [ "$PARALLEL" = "1" ] && metacog_has_jq; then
  JUDG_BUCKET="$WORKDIR/bucket_judgments.json"
  BIAS_BUCKET="$WORKDIR/bucket_biases.json"

  # 每条 session 保留 meta，按 tag 过滤其 hits；空 hits 的 session 丢弃
  jq '[ .[] | . as $s
        | { session_id: $s.session_id, cwd: $s.cwd, recorded_at: $s.recorded_at,
            hits: [ $s.hits[]? | select(.tag=="STRUCTURED_JUDGMENT" or .tag=="VERIFICATION_FAIL" or .tag=="TECH_DISCOVERY") ] }
        | select(.hits | length > 0) ]' "$PENDING_AGG" > "$JUDG_BUCKET"

  jq '[ .[] | . as $s
        | { session_id: $s.session_id, cwd: $s.cwd, recorded_at: $s.recorded_at,
            hits: [ $s.hits[]? | select(.tag=="CORRECTION" or .tag=="CONFIRMATION") ] }
        | select(.hits | length > 0) ]' "$PENDING_AGG" > "$BIAS_BUCKET"

  bucket_specs=()
  [ "$(jq 'length' "$JUDG_BUCKET" 2>/dev/null || echo 0)" -gt 0 ] \
    && bucket_specs+=("judgments|$JUDG_BUCKET|判断与技术事实")
  [ "$(jq 'length' "$BIAS_BUCKET" 2>/dev/null || echo 0)" -gt 0 ] \
    && bucket_specs+=("biases|$BIAS_BUCKET|偏差")

  if [ ${#bucket_specs[@]} -eq 0 ]; then
    metacog_log "reflect: parallel path but all buckets empty, nothing to do"
    # 仍然归档 pending，避免反复扫
  else
    pids=()
    diff_files=()
    for spec in "${bucket_specs[@]}"; do
      IFS='|' read -r name file label <<< "$spec"
      out="$WORKDIR/reflect_${name}.json"
      diff_files+=("$name|$out")
      metacog_log "reflect: launching bucket=$name"
      run_bucket "$name" "$file" "$label" "$out" &
      pids+=($!)
    done

    for pid in "${pids[@]}"; do wait "$pid" || true; done
    metacog_log "reflect: all ${#pids[@]} buckets completed"

    # 串行 apply（apply_reflection.py 是幂等的，顺序喂即可）
    any_applied=0
    for spec in "${diff_files[@]}"; do
      IFS='|' read -r name out <<< "$spec"
      [ -s "$out" ] || { metacog_log "reflect: bucket=$name produced empty diff, skip"; continue; }
      if APPLY_OUT="$(python3 "$SCRIPT_DIR/apply_reflection.py" "$MEMDIR" "$out" 2>&1)"; then
        metacog_log "reflect: bucket=$name applied -> $APPLY_OUT"
        any_applied=1
      else
        metacog_log "reflect: bucket=$name apply FAILED: $APPLY_OUT"
      fi
    done

    if [ "$any_applied" -eq 0 ]; then
      metacog_log "reflect: no bucket applied successfully, keeping pending for retry"
      exit 2
    fi
  fi

# ---------- 原单桶路径（fallback） ----------
else
  PROMPT="$WORKDIR/prompt.txt"
  {
    echo "=== PENDING ==="
    cat "$PENDING_AGG"
    echo ""
    echo "=== EXISTING BIASES ==="
    cat "$BIASES" 2>/dev/null || echo "(empty)"
    echo ""
    echo "=== EXISTING TECH FACTS (recent 20) ==="
    cat "$TECH_RECENT"
    echo ""
    echo "=== TASK ==="
    echo "按照你的 system prompt 规定，产出唯一一个 JSON 对象，不要任何解释文本。"
  } > "$PROMPT"

  REFLECT_JSON="$WORKDIR/reflect.json"
  metacog_log "reflect: calling headless claude (single bucket)"

  if ! claude -p $BARE_FLAG --no-session-persistence \
       --allowedTools "Read" \
       --permission-mode bypassPermissions \
       --append-system-prompt "$(cat "$SCRIPT_DIR/reflect_prompt.md")" \
       "$(cat "$PROMPT")" > "$REFLECT_JSON" 2>"$WORKDIR/reflect.err"; then
    metacog_log "reflect: claude call failed"
    cat "$WORKDIR/reflect.err" >> "$METACOG_LOG"
    exit 1
  fi
  [ -s "$REFLECT_JSON" ] || cp "$WORKDIR/reflect.err" "$REFLECT_JSON"

  metacog_log "reflect: applying diff (bytes=$(wc -c < "$REFLECT_JSON" | tr -d ' '))"
  APPLY_OUT="$(python3 "$SCRIPT_DIR/apply_reflection.py" "$MEMDIR" "$REFLECT_JSON" 2>&1)" || {
    metacog_log "reflect: apply_reflection failed: $APPLY_OUT"
    exit 2
  }
  metacog_log "reflect: $APPLY_OUT"
fi

# 成功后把 pending 移到归档
DONE_DIR="$MEMDIR/metacognition/_archive/$(date +%Y-%m)/pending_processed"
mkdir -p "$DONE_DIR"
for f in "${files[@]}"; do
  mv "$f" "$DONE_DIR/" 2>/dev/null || true
done

metacog_log "reflect: done"
echo "ok (parallel=$PARALLEL, files=${#files[@]})"
