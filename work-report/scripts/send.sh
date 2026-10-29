#!/bin/bash
# 把当天的工作报告草稿发到 Slack。
#
# 用法：send.sh [daily|weekly|--check]（--check 只报 token 是否已配置）
#   daily  → #team-web-前端 当天的「每日工作任务统计」thread（团队既有惯例）
#   weekly → 默认不发。周报没有既有 thread 惯例，落点未定；配好
#            WORK_REPORT_WEEKLY_CHANNEL 与 WORK_REPORT_WEEKLY_THREAD_MARKER 后才启用。
#
# 为什么不复用 Claude Code 的 Slack MCP（2026-08-24 实测，别再重试）：
#   - 在交互 CC 会话里跑 `claude -p --allowedTools mcp__plugin_slack_slack__*` 是能用的
#     （sonnet/默认档；haiku 档拿不到 MCP 工具），所以很容易误判成 headless 可行；
#   - 但用临时 plist 在真实 launchd 里跑同一条命令，报「Slack MCP 需要先授权，当前会话
#     无法完成 OAuth 流程」。补齐 launchd 缺的候选环境变量（__CF_USER_TEXT_ENCODING /
#     ANTHROPIC_BASE_URL / NODE_EXTRA_CA_CERTS / COMMAND_MODE 等）后仍然 UNAVAILABLE。
#   MCP 授权只在交互会话派生的进程里继承，定时任务拿不到，所以走独立 token + Slack Web API。
set -uo pipefail

SECRETS="$HOME/.claude/.secrets/slack-daily-report.env"

# send.sh --check：只报 token 是否已配置，不输出任何 token 字符。
# 会话里想确认配置状态时用它，直接 sed/cat 凭证文件会被 auto mode 拦截。
if [ "${1:-}" = "--check" ]; then
  if [ ! -f "$SECRETS" ]; then
    echo "token 文件不存在: $SECRETS"
    exit 1
  fi
  # shellcheck disable=SC1090
  SLACK_TOKEN="$( . "$SECRETS" >/dev/null 2>&1; printf '%s' "${SLACK_TOKEN:-}" )"
  if [ -n "$SLACK_TOKEN" ]; then
    echo "SLACK_TOKEN 已配置"
    exit 0
  fi
  echo "$SECRETS 存在，但 SLACK_TOKEN 为空"
  exit 1
fi

PERIOD="${1:-${WORK_REPORT_PERIOD:-daily}}"

case "$PERIOD" in
  daily)
    DEFAULT_REPORT_DIR="$HOME/.claude/reports/daily"
    KIND_LABEL="日报"
    CHANNEL_ID="${WORK_REPORT_CHANNEL:-C0XXXXXXXXX}"           # #team-web-前端
    THREAD_AUTHOR="${WORK_REPORT_THREAD_AUTHOR:-U0LEADXXXXX}"   # 主管，日报 thread 发起人
    THREAD_MARKER="${WORK_REPORT_THREAD_MARKER:-每日工作任务统计}"
    ;;
  weekly)
    DEFAULT_REPORT_DIR="$HOME/.claude/reports/weekly"
    KIND_LABEL="周报"
    CHANNEL_ID="${WORK_REPORT_WEEKLY_CHANNEL:-}"
    THREAD_AUTHOR="${WORK_REPORT_WEEKLY_THREAD_AUTHOR:-}"
    THREAD_MARKER="${WORK_REPORT_WEEKLY_THREAD_MARKER:-}"
    ;;
  *) echo "send.sh: 未知周期 '$PERIOD'（只接受 daily / weekly）" >&2; exit 2 ;;
esac

REPORT_DIR="${WORK_REPORT_DIR:-$DEFAULT_REPORT_DIR}"
LOG="$HOME/.claude/logs/work-report.log"
TODAY="$(date +%Y-%m-%d)"
DRAFT="$REPORT_DIR/$TODAY.md"
SENT_MARK="$REPORT_DIR/.sent-$TODAY"

DRYRUN="${WORK_REPORT_SEND_DRYRUN:-0}"
# 找不到 thread 时的重试（日报 thread 平时 17:00 发出，偶尔晚发）
RETRIES="${WORK_REPORT_SEND_RETRIES:-3}"
RETRY_GAP="${WORK_REPORT_SEND_RETRY_GAP:-300}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$PERIOD][send] $*" >> "$LOG"; }

notify() {
  local title="$1" body="$2"
  osascript -e "display notification \"${body//\"/\\\"}\" with title \"${title//\"/\\\"}\" sound name \"Basso\"" 2>/dev/null || true
}

fail() {
  log "FAIL: $1"
  notify "⚠️ ${KIND_LABEL}自动发送失败" "$1（草稿仍在 ${DRAFT}，可人工发）"
  exit 1
}

# --- 前置检查 ---------------------------------------------------------------

# 未配置发送目标（周报默认如此）：不是失败，只落草稿由人工过目再发。
if [ -z "$CHANNEL_ID" ] || [ -z "$THREAD_MARKER" ]; then
  log "未配置发送目标（channel 或 thread 标记为空），只落草稿，不发送。"
  exit 0
fi

[ -f "$DRAFT" ] || fail "今日草稿不存在: $DRAFT"

# 幂等：同一天同周期只发一次，防 launchd 重跑或手动叠加导致群里重复
if [ -f "$SENT_MARK" ] && [ "$DRYRUN" != "1" ]; then
  log "今日已发送过（$(cat "$SENT_MARK")），跳过。"
  exit 0
fi

if [ "$DRYRUN" != "1" ]; then
  [ -f "$SECRETS" ] || fail "缺少 Slack token 文件: $SECRETS"
  # shellcheck disable=SC1090
  . "$SECRETS"
  [ -n "${SLACK_TOKEN:-}" ] || fail "$SECRETS 里未设置 SLACK_TOKEN"
fi

# --- 1. 草稿正文提取（剥掉本地标题与自动生成注脚）---------------------------

BODY="$(python3 - "$DRAFT" <<'PY'
import sys
raw = open(sys.argv[1], encoding='utf-8').read()
lines = raw.splitlines()
# 去掉 "# 日报草稿 / # 周报草稿 YYYY-MM-DD" 标题行
if lines and lines[0].startswith('#'):
    lines = lines[1:]
# 去掉末尾 "---" 分隔线及其后的本地注脚
for i in range(len(lines) - 1, -1, -1):
    if lines[i].strip() == '---':
        lines = lines[:i]
        break
body = '\n'.join(lines).strip()
# 归纳失败回退成原始素材时体积巨大且含文件名，不适合直接发群
if body.startswith('>') and '归纳失败' in body[:200]:
    sys.exit(3)
if not body:
    sys.exit(4)
# 署名规范化：归纳模型偶尔漏写，或写成 @TeamBot（那是 主管 bot 的标记）。
# 统一剔除已有署名行后补上本人使用的 Claude 署名。
SIGN = '*发送工具* <@U0CLAUDEXXX|Claude>'
kept = [ln for ln in body.splitlines() if '发送工具' not in ln]
body = '\n'.join(kept).rstrip() + '\n\n' + SIGN
print(body)
PY
)"
EXTRACT_RC=$?

case "$EXTRACT_RC" in
  3) fail "草稿是归纳失败的原始素材回退版，拒绝自动发群，请人工整理" ;;
  4) fail "草稿正文为空" ;;
  0) : ;;
  *) fail "草稿解析异常 rc=$EXTRACT_RC" ;;
esac

# 体积保险：正常报告几百字，异常膨胀说明归纳跑偏了（回退成原始素材时有几万字）。
# 周报另给一档：明细段自 2026-09-20 起不设条数上限，正常体积比日报大一截。
BODY_BYTES=${#BODY}
if [ "$PERIOD" = "weekly" ]; then
  BODY_LIMIT="${WORK_REPORT_BODY_LIMIT:-6000}"
else
  BODY_LIMIT="${WORK_REPORT_BODY_LIMIT:-4000}"
fi
if [ "$BODY_BYTES" -gt "$BODY_LIMIT" ]; then
  fail "草稿正文 ${BODY_BYTES} 字节，超出${KIND_LABEL}正常体积（上限 ${BODY_LIMIT}），疑似归纳跑偏，拒绝自动发群"
fi

if [ "$DRYRUN" = "1" ]; then
  echo "===== DRY RUN：待发正文（${BODY_BYTES} 字节）====="
  echo "$BODY"
  echo "===== 目标频道: $CHANNEL_ID ====="
fi

# --- 2. 定位当天的报告 thread ------------------------------------------------

# 今天 00:00 的 unix 时间戳（BSD date）
DAY_START="$(date -j -f '%Y-%m-%d %H:%M:%S' "$TODAY 00:00:00" +%s 2>/dev/null)"
[ -n "$DAY_START" ] || fail "无法计算当天起始时间戳"

find_thread_ts() {
  local resp
  resp="$(curl -sS -X GET "https://slack.com/api/conversations.history" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    --get \
    --data-urlencode "channel=$CHANNEL_ID" \
    --data-urlencode "oldest=$DAY_START" \
    --data-urlencode "limit=100" 2>/dev/null)"
  [ -n "$resp" ] || return 1
  THREAD_TS="$(printf '%s' "$resp" | python3 - "$THREAD_AUTHOR" "$THREAD_MARKER" <<'PY'
import json, sys
author, marker = sys.argv[1], sys.argv[2]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not d.get('ok'):
    print('SLACK_ERR:' + str(d.get('error')), file=sys.stderr)
    sys.exit(2)
msgs = d.get('messages', [])
# 那条 thread 是通过 TeamBot bot 代发的，bot 代发时 user 字段不保证等于发起人，
# 所以先按 作者+标记 精确匹配，失配再退化为只按标记匹配（标记文本足够特异，不会误命中）。
# author 为空时直接走标记匹配。
if author:
    for m in msgs:
        if m.get('user') == author and marker in (m.get('text') or ''):
            print(m['ts'])
            sys.exit(0)
for m in msgs:
    if marker in (m.get('text') or ''):
        print(m['ts'])
        sys.exit(0)
sys.exit(3)
PY
)"
  return $?
}

if [ "$DRYRUN" = "1" ]; then
  if [ -f "$SECRETS" ]; then
    # shellcheck disable=SC1090
    . "$SECRETS"
  fi
  if [ -n "${SLACK_TOKEN:-}" ]; then
    if find_thread_ts; then
      echo "===== 已定位今日 thread: $THREAD_TS ====="
    else
      echo "===== 未定位到今日 thread（发起人可能还没发）====="
    fi
  else
    echo "===== 无 token，跳过 thread 定位 ====="
  fi
  exit 0
fi

THREAD_TS=""
attempt=0
while [ "$attempt" -le "$RETRIES" ]; do
  if find_thread_ts && [ -n "$THREAD_TS" ]; then
    break
  fi
  THREAD_TS=""
  attempt=$((attempt + 1))
  if [ "$attempt" -le "$RETRIES" ]; then
    log "未找到今日「${THREAD_MARKER}」thread，第 $attempt 次重试将在 ${RETRY_GAP}s 后进行。"
    sleep "$RETRY_GAP"
  fi
done

if [ -z "$THREAD_TS" ]; then
  # 兜底不发顶层消息：这个群里顶层消息是「有事找人」的语义，报告发顶层不合惯例
  fail "重试 ${RETRIES} 次仍未找到今日「${THREAD_MARKER}」thread，未发送"
fi

log "定位到今日 thread: $THREAD_TS"

# --- 3. 发送到 thread --------------------------------------------------------

PAYLOAD="$(BODY_TEXT="$BODY" python3 - "$CHANNEL_ID" "$THREAD_TS" <<'PY'
import json, sys, os
print(json.dumps({
    "channel": sys.argv[1],
    "thread_ts": sys.argv[2],
    "text": os.environ["BODY_TEXT"],
    "mrkdwn": True,
}, ensure_ascii=False))
PY
)"

RESP="$(curl -sS -X POST "https://slack.com/api/chat.postMessage" \
  -H "Authorization: Bearer $SLACK_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-binary "$PAYLOAD" 2>/dev/null)"

RESULT="$(printf '%s' "$RESP" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print('PARSE_FAIL'); sys.exit(0)
print('OK ' + d.get('ts', '') if d.get('ok') else 'ERR ' + str(d.get('error')))
")"

case "$RESULT" in
  OK*)
    SENT_TS="${RESULT#OK }"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ts=$SENT_TS thread=$THREAD_TS" > "$SENT_MARK"
    log "已发送到 thread ${THREAD_TS}，消息 ts=${SENT_TS}"
    notify "✅ ${KIND_LABEL}已自动发送" "$TODAY · 频道 $CHANNEL_ID"
    ;;
  *)
    fail "chat.postMessage 失败: $RESULT"
    ;;
esac
