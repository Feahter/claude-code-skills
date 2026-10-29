#!/bin/bash
# 采集工作报告素材，输出结构化文本到 stdout。除了先 git fetch 刷新 remote-tracking refs，
# 不改任何仓库状态（不动工作区和本地分支）。
#
# 用法：collect.sh [daily|weekly]
#
# 两个周期共用同一套 commit 采集、作者匹配与三档合并状态判定，差别只有三处：
#   1) 报告目录不同，因而增量窗口起点不同（各自接续自己上一份，不重不漏）；
#   2) 首次运行的兜底窗口不同（日报回退到今天 00:00，周报回退到本周一 00:00）；
#   3) 周报额外把本周已生成的日报草稿作为第一段素材——那些草稿已凝练过一次、
#      合并状态也已判定，比让模型从 commit 重推更准；commit 段留着补漏
#      （某天没跑日报，或日报限 3-6 条时被砍掉的次要工作）。
#
# 能算的都在这里算完，不留给模型：规模统计段给出每仓与每主题的提交数、新增行数与覆盖天数
# （模型从上百条记录里数容易错），仓库明细按工作量排好序输出（报告的分组顺序照抄即可），
# 每条 commit 的合并状态直接翻成报告该写的状态词。模型只负责归纳文字。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERIOD="${1:-${WORK_REPORT_PERIOD:-daily}}"
case "$PERIOD" in
  daily)  DEFAULT_REPORT_DIR="$HOME/.claude/reports/daily" ;;
  weekly) DEFAULT_REPORT_DIR="$HOME/.claude/reports/weekly" ;;
  *) echo "collect.sh: 未知周期 '$PERIOD'（只接受 daily / weekly）" >&2; exit 2 ;;
esac

# 跟版状态词按周期分：周报跨整周，不能写「今日」。
# commit body 行数也按周期分：周报的主线来自已凝练的日报草稿，body 只留两行做补漏提示，
# 省下的体积换归纳速度（2026-09-18 五天素材 63 KB 撞破 600 秒超时，body 是主要体积）。
if [ "$PERIOD" = "weekly" ]; then
  WORD_FOLLOW="【跟版中】"
  BODY_LINES=2
else
  WORD_FOLLOW="【今日跟版】"
  BODY_LINES=6
fi

PROJECTS_DIR="${WORK_REPORT_PROJECTS_DIR:-$HOME/projects}"
# 排除的仓库名（空格分隔）
EXCLUDE="${WORK_REPORT_EXCLUDE:-acme-agent cc-taskboard}"
REPORT_DIR="${WORK_REPORT_DIR:-$DEFAULT_REPORT_DIR}"
# 周报聚合日报草稿的来源目录（与 REPORT_DIR 分开：周报自己的目录是 weekly）
DAILY_DIR="${WORK_REPORT_DAILY_DIR:-$HOME/.claude/reports/daily}"

# 增量窗口（本地时区）：上一份同周期报告的生成时刻 → 现在，接续上一份、不重不漏。
# 取「上一份」按文件名日期排序，不用 ls -t：mtime 会被事后编辑草稿打乱顺序。
# 同时排除今天这份（重跑时不能把窗口起点设成自己）。
TODAY="$(date +%Y-%m-%d)"
LAST_REPORT="$(ls "$REPORT_DIR"/[0-9]*.md 2>/dev/null \
  | grep -v "/$TODAY\.md$" | sort | tail -1)"
if [ -n "$LAST_REPORT" ]; then
  SINCE="$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$LAST_REPORT" 2>/dev/null)"
  # mtime 可能因事后编辑晚于文件名日期，取两者较早者，避免窗口起点被推后而漏采
  NAME_DATE="$(basename "$LAST_REPORT" .md)"
  if [ "${SINCE%% *}" \> "$NAME_DATE" ]; then
    SINCE="$NAME_DATE 23:59:59"
  fi
fi
# 首次运行（该周期还没有任何历史报告）的兜底窗口
if [ -z "${SINCE:-}" ]; then
  case "$PERIOD" in
    daily)  SINCE="$TODAY 00:00:00" ;;
    # 本周一 00:00：date +%u 周一=1，回退 (u-1) 天。周报首跑不能用「今天 00:00」，
    # 否则只采到运行当天，整周工作全漏。
    weekly) SINCE="$(date -v-$(( $(date +%u) - 1 ))d +%Y-%m-%d) 00:00:00" ;;
  esac
fi
UNTIL="$(date '+%Y-%m-%d %H:%M:%S')"

# 陈旧工作的 author date 下限：窗口起点所在那一天的 00:00。
# 用于剔除 rebase / cherry-pick 刷新了 committer date 的历史工作（它们在原本那天已汇报过），
# 同时不影响窗口内正常提交——它们的 author date 必然晚于窗口起点当天 00:00。
STALE_CUTOFF="$(date -j -f '%Y-%m-%d %H:%M:%S' "${SINCE%% *} 00:00:00" '+%s' 2>/dev/null || echo 0)"

# 作者匹配：以邮箱为主标识。同一人在不同仓库可能配了不同 user.name
# （实测同一邮箱下同时存在 "fez" 和 "Zhuo Fu"），只按 name 匹配会漏掉一部分提交；
# 邮箱在各仓库间稳定，故用完整邮箱做主匹配，name 作为补充（覆盖邮箱不同但人相同的情况）。
# 匹配统一走 --regexp-ignore-case，避免 name 大小写写法不一致导致漏采。
GIT_NAME="$(git config --global user.name 2>/dev/null || echo '')"
GIT_EMAIL="$(git config --global user.email 2>/dev/null || echo '')"
AUTHOR_RE="${GIT_EMAIL:-$GIT_NAME}"
[ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ] && AUTHOR_RE="$GIT_EMAIL\|$GIT_NAME"

is_excluded() {
  local name="$1"
  for e in $EXCLUDE; do
    [ "$name" = "$e" ] && return 0
  done
  return 1
}

# 采集前先同步远端。经 TeamBot 等云端 agent 提交的 MR，commit 只在远端，本地不 fetch 就看不到
# （2026-10-12 实测：云端 16:26 推的 FOMO 子 tab 提交，本地 19:12 才被别的工具 fetch 到，
# 17:30 的日报漏采）。漏了也补不回来：下一份报告的窗口从这一份的生成时刻接续，
# committer date 早于它的提交此后永远进不了窗口。云端提交的 author 是本人邮箱、committer 是
# agent 或 root@ip-*，现有的按 author 匹配能命中，缺的只是 refs。
# fetch 顺带刷新 origin 上的主干和发版分支，合并状态判定也跟着变准。
# 不加 --prune：MR 合并后源分支被删，留着本地 ref 不影响判定。
# 各仓并行、整体限时；失败只写 stderr（进 work-report.log），按本地已有 refs 照常采集。
# GIT_TERMINAL_PROMPT=0：凭据取不到时直接失败，不在无终端的 launchd 里等输入。
FETCH_TIMEOUT="${WORK_REPORT_FETCH_TIMEOUT:-60}"
fetch_remotes() {
  local repo name pid alive i waited=0
  local -a pids=() names=()
  # set -m 让每个后台 fetch 自成进程组，超时按组杀：只杀 git 本身的话，
  # 它派生的 git-remote-http 会留在后台继续挂着（实测）。
  set -m
  for repo in "$PROJECTS_DIR"/*/; do
    [ -d "$repo/.git" ] || continue
    name="$(basename "$repo")"
    is_excluded "$name" && continue
    git -C "$repo" remote get-url origin >/dev/null 2>&1 || continue
    GIT_TERMINAL_PROMPT=0 git -C "$repo" fetch --quiet origin >/dev/null 2>&1 &
    pids+=("$!"); names+=("$name")
  done
  set +m
  # bash 3.2 下 set -u 展开空数组会报 unbound，先判空
  [ "${#pids[@]}" -eq 0 ] && return 0
  while :; do
    alive=0
    for pid in "${pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && alive=1
    done
    [ "$alive" -eq 0 ] && break
    if [ "$waited" -ge "$FETCH_TIMEOUT" ]; then
      for pid in "${pids[@]}"; do
        kill -TERM -- "-$pid" 2>/dev/null
      done
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  # wait 的 stderr 丢掉：被杀的 job 会让 bash 打一行「Terminated: 15」，下面已有自己的告警
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}" 2>/dev/null \
      || echo "collect.sh: ${names[$i]} fetch 失败或超时（rc=$?），云端提交可能缺失，按本地已有 refs 采集" >&2
  done
}

emitted_any=0

# 周报第一段素材：窗口内已生成的日报草稿正文。
# 只取归纳成功的那些——归纳失败的草稿本身就是原始 commit 素材（体积大、含文件名），
# 而那部分内容 commit 段已经覆盖，重复喂进去只会挤占归纳的注意力。
emit_daily_drafts() {
  local start_date="${SINCE%% *}"
  local found=0 f d body
  for f in "$DAILY_DIR"/[0-9]*.md; do
    [ -f "$f" ] || continue
    d="$(basename "$f" .md)"
    # YYYY-MM-DD 定长，字符串比较即日期比较
    [ "$d" \< "$start_date" ] && continue
    # 三步清洗：去掉本地标题行（历史草稿标题写法不一，只认「第一行以 # 开头」）、
    # 在正文末尾的 --- 分隔线处截断（丢掉自动生成注脚）、剥掉署名行
    # （素材里留着署名，归纳模型会照抄成周报正文的一部分）。
    body="$(sed '1{/^# /d;}' "$f" | awk '/^---$/{exit} {print}' \
      | grep -v '发送工具' | sed '/^[[:space:]]*$/d')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | head -3 | grep -q '归纳失败'; then
      continue
    fi
    if [ "$found" -eq 0 ]; then
      echo "## 本周日报草稿（已凝练、合并状态已判定，周报以这段为主线）"
      echo ""
      found=1
    fi
    echo "### $d"
    echo "$body"
    echo ""
  done
  [ "$found" -eq 1 ] && emitted_any=1
  return 0
}

commit_header_done=0
maybe_commit_header() {
  [ "$PERIOD" = "weekly" ] || return 0
  [ "$commit_header_done" -eq 1 ] && return 0
  echo "## 本周 commit 素材（补漏用：日报没覆盖的那天，或被日报条数上限砍掉的工作）"
  echo ""
  commit_header_done=1
}

# 每个仓库探测一次主干、发版分支与测试分支，结果放进 TRUNK / RELEASES / TESTING 供 merged_state 复用。
# 分开判是因为本地仓库的实际流程是 feature → pre（提测）→ 发版分支 → 主干（main-app 走 acme-<MMDD>），
# 只判主干会把「已跟上本次版本」的工作和「还在自己分支上改」混成同一档。
# pre 单列一档（2026-10-14 用户定的口径）：合到 pre 只说明在测，进了发版分支才算跟版。
TRUNK=""     # 已发布主干
RELEASES=""  # 发版分支，换行分隔，最近提交的在前
TESTING=""   # 测试分支（origin/pre），不存在时为空
detect_branches() {
  local repo="$1"
  TRUNK=""
  for cand in main master develop; do
    if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/$cand" >/dev/null 2>&1; then
      TRUNK="origin/$cand"; break
    elif git -C "$repo" rev-parse --verify --quiet "refs/heads/$cand" >/dev/null 2>&1; then
      TRUNK="$cand"; break
    fi
  done
  # 发版分支：远端上完整名形如 acme-<4 位日期> / release/* 的共享分支。
  # 必须锚定完整分支名（^...$）：仓库里存在 feat/security-lp-check-tip-acme-0824、
  # fix/trenches-tradebar-overlap-acme-0817 这类把版本号写进名字的特性分支，
  # 不锚定会把它们误判成发版分支，一条还在改的工作就会被标成已跟版。
  RELEASES="$(git -C "$repo" for-each-ref --sort=-committerdate \
    --format='%(refname:short)' refs/remotes/origin 2>/dev/null \
    | grep -E '^origin/(acme-[0-9]{4}|release/.+)$' \
    | grep -vx "$TRUNK")"
  TESTING=""
  if git -C "$repo" rev-parse --verify --quiet "refs/remotes/origin/pre" >/dev/null 2>&1; then
    TESTING="origin/pre"
  fi
}

# 四档合并状态，从已发布往未发布排，命中即止：
#   已在主干     → 已完成
#   已在发版分支 → 跟版（进了本次版本，等发布）
#   已在测试分支 → 测试中（合到了 pre，还没进发版分支）
#   仅在特性分支 → 开发中
merged_state() {
  local repo="$1" sha="$2" b=""
  if [ -n "$TRUNK" ] && git -C "$repo" merge-base --is-ancestor "$sha" "$TRUNK" 2>/dev/null; then
    echo "已在主干($TRUNK)"
    return
  fi
  while IFS= read -r b; do
    [ -z "$b" ] && continue
    if git -C "$repo" merge-base --is-ancestor "$sha" "$b" 2>/dev/null; then
      echo "已在发版分支($b)"
      return
    fi
  done <<< "$RELEASES"
  if [ -n "$TESTING" ] && git -C "$repo" merge-base --is-ancestor "$sha" "$TESTING" 2>/dev/null; then
    echo "已在测试分支($TESTING)"
    return
  fi
  if [ -z "$TRUNK" ]; then
    echo "未知主干"
  else
    echo "仅在特性分支(未进 ${TRUNK}、发版分支与测试分支)"
  fi
}

# 三档合并状态 → 报告该写的状态词。映射放脚本里，模型照抄，不再自己判：
# 2026-09-18 手工整理那份周报时发现，「已在发版分支」被写成【已完成】是最常见的越级。
state_word() {
  case "$1" in
    已在主干*)      echo "【已完成】" ;;
    已在发版分支*)  echo "$WORD_FOLLOW" ;;
    已在测试分支*)  echo "【测试中】" ;;
    *)              echo "【开发中】" ;;
  esac
}

# rebase / cherry-pick 到别的分支会留下多份 sha 不同的副本，--branches --remotes 会全部采到
# （2026-09-23 实测同一条 commit 在特性分支、发版分支上各一份，素材里重复 3 次）。
# 副本的作者时间和标题不变，按这两项去重；patch-id 不行，rebase 解过冲突后它会变。
# 同一组副本保留合并状态走得最远的那份（主干 > 发版分支 > 测试分支 > 特性分支）。
# stdin 每行 sha|作者时间戳|作者时间|标题，stdout 每行 作者时间戳|档位|sha|作者时间|合并状态|标题。
dedupe_commits() {
  local repo="$1" h at t s state rank
  while IFS='|' read -r h at t s; do
    [ -z "$h" ] && continue
    state="$(merged_state "$repo" "$h")"
    case "$state" in
      已在主干*)     rank=0 ;;
      已在发版分支*) rank=1 ;;
      已在测试分支*) rank=2 ;;
      *)             rank=3 ;;
    esac
    printf '%s|%s|%s|%s|%s|%s\n' "$at" "$rank" "$h" "$t" "$state" "$s"
  done | awk -F'|' '{
    subj = $6; for (i = 7; i <= NF; i++) subj = subj "|" $i
    key = $1 "|" subj
    if (!(key in best)) { order[++n] = key; best[key] = $0; r[key] = $2 }
    else if ($2 < r[key]) { best[key] = $0; r[key] = $2 }
  } END { for (i = 1; i <= n; i++) print best[order[i]] }'
}

# 明细先落盘、最后按工作量排序输出；统计数据同时写进 DATA_TMP 供规模统计段汇总。
DATA_TMP="$(mktemp)"
DETAIL_DIR="$(mktemp -d)"
trap 'rm -rf "$DATA_TMP" "$DETAIL_DIR"' EXIT

fetch_remotes
[ "$PERIOD" = "weekly" ] && emit_daily_drafts

for repo in "$PROJECTS_DIR"/*/; do
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  is_excluded "$name" && continue

  # 两道并列过滤，各管一件事：
  # 1) committer date 落在增量窗口内（git --since/--until 原生语义），保证接续上一份报告不重不漏；
  # 2) author date 不早于窗口所在那一天的 00:00，剔除 rebase / cherry-pick 把陈旧工作的
  #    committer date 刷成今天造成的重复汇报（这类工作在它的 author date 那天已经报过）。
  # 用 --branches --remotes 而不是 --all：--all 含 refs/stash，会把 git stash 产生的
  # 「WIP on <branch>」「index on <branch>」两条 commit 当成工作产出采进素材
  # （2026-09-15 实测撞到，合并状态判成「仅在特性分支」，归纳后变成一条【开发中】的假工作）。
  # --no-merges：合并提交的标题是「Merge branch 'X' into 'Y'」，对归纳没有信息量，
  # 却占掉本周素材近四成条数，还会把规模统计的提交次数抬高一倍。合进哪条分支这件事
  # 由 merged_state 判定，不靠 merge commit 证明。
  commits="$(git -C "$repo" log --branches --remotes --no-merges \
    --since="$SINCE" --until="$UNTIL" \
    --regexp-ignore-case --author="$AUTHOR_RE" \
    --pretty=format:'%h|%at|%ad|%s' --date=format:'%m-%d %H:%M' 2>/dev/null \
    | awk -F'|' -v cutoff="$STALE_CUTOFF" '$2 >= cutoff')"

  [ -z "$commits" ] && continue

  emitted_any=1
  detect_branches "$repo"
  commits="$(echo "$commits" | dedupe_commits "$repo")"

  {
    echo "### 仓库: $name"
    echo "$commits" | while IFS='|' read -r _at _rank h t state s; do
      [ -z "$h" ] && continue
      word="$(state_word "$state")"
      echo "- [$t] $s"
      # 合并状态连带该写的状态词一起给出，模型不必再做一次映射
      echo "    (合并状态: $state → 报告写 $word)"
      stat="$(git -C "$repo" show --stat --oneline "$h" 2>/dev/null | tail -1 | sed 's/^ *//')"
      [ -n "$stat" ] && echo "    ($stat)"
      # 附 commit body（去空行，行数按周期），保留关键技术判断供归纳
      body="$(git -C "$repo" show -s --pretty=format:'%b' "$h" 2>/dev/null \
        | grep -v '^Co-Authored-By:' | sed '/^[[:space:]]*$/d' | head -"$BODY_LINES")"
      if [ -n "$body" ]; then
        echo "$body" | sed 's/^/    > /'
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$t" "$stat" "$word" "$s" >> "$DATA_TMP"
    done
    echo ""
  } > "$DETAIL_DIR/$name.md"
done

# 规模统计段 + 明细按工作量排序输出。
# 统计交给 summarize.py：提交次数、覆盖天数、新增行数都是纯计数，模型从上百条记录里数会错，
# 而周报主线段要求带这些数字。排序结果同时决定明细里仓库分组的先后。
if [ -s "$DATA_TMP" ]; then
  ORDER_TMP="$(mktemp)"
  python3 "$SCRIPT_DIR/summarize.py" "$DATA_TMP" "$ORDER_TMP" "$PERIOD" \
    || echo "(规模统计生成失败，提交次数与天数请按下面明细自行数)"
  maybe_commit_header
  while IFS= read -r r; do
    [ -n "$r" ] && [ -f "$DETAIL_DIR/$r.md" ] && cat "$DETAIL_DIR/$r.md"
  done < "$ORDER_TMP"
  rm -f "$ORDER_TMP"
fi

# 若无任何素材，返回非零，供上层判断是否跳过
if [ "$emitted_any" -eq 0 ]; then
  exit 10
fi
