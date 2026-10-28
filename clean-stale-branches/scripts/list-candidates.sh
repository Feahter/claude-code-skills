#!/usr/bin/env bash
# list-candidates.sh <days> <author_email> [protected_regex]
# 产物：
#   $WORK/local-candidates.txt     纯分支名，一行一个
#   $WORK/remote-candidates.txt    纯分支名（去掉 origin/）
#   $WORK/candidates-preview.txt   带日期的预览，供展示

set -euo pipefail
source "$(dirname "$0")/_workdir.sh"

DAYS="${1:-30}"
AUTHOR="${2:-}"
PROTECTED="${3:-^(master|main|pre|dev|HEAD)$}"

if [ -z "$AUTHOR" ]; then
  AUTHOR="$(git config user.email)"
fi

CUTOFF=$(date -v-"${DAYS}"d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d)

# detached HEAD 时 cur 为空会导致 $1!=cur 永真，所有分支都进候选——
# 这里塞个绝对不会跟真实分支名相等的哨兵值
CUR=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
[ -z "$CUR" ] && CUR="__DETACHED_HEAD_SENTINEL__"

LOCAL_RAW="$WORK/local-raw.txt"
REMOTE_RAW="$WORK/remote-raw.txt"

# 一次 for-each-ref 同时拿名字、日期、作者，下游预览复用——
# 原来预览对每个分支调 git log 一次，几百分支量级会卡
git for-each-ref --format='%(refname:short)|%(committerdate:short)|%(authoremail)' refs/heads/ > "$LOCAL_RAW"
git for-each-ref --format='%(refname:short)|%(committerdate:short)|%(authoremail)' refs/remotes/origin/ > "$REMOTE_RAW"

awk -F'|' -v c="$CUTOFF" -v a="<$AUTHOR>" -v cur="$CUR" -v p="$PROTECTED" '
  $3==a && $2<c && $1!=cur && $1 !~ p {print $1}
' "$LOCAL_RAW" > "$WORK/local-candidates.txt"

awk -F'|' -v c="$CUTOFF" -v a="<$AUTHOR>" -v p="$PROTECTED" '
  {
    sub(/^origin\//,"",$1)
    if ($3==a && $2<c && $1 !~ p) print $1
  }
' "$REMOTE_RAW" > "$WORK/remote-candidates.txt"

# 预览直接从 RAW 里切，不再 per-branch 调 git log
{
  echo "# cutoff: $CUTOFF  author: $AUTHOR  protected: $PROTECTED"
  echo
  echo "## 本地候选（$(wc -l < "$WORK/local-candidates.txt") 个）"
  awk -F'|' -v c="$CUTOFF" -v a="<$AUTHOR>" -v cur="$CUR" -v p="$PROTECTED" '
    $3==a && $2<c && $1!=cur && $1 !~ p {printf "  %s | %s\n", $2, $1}
  ' "$LOCAL_RAW" | sort
  echo
  echo "## 远端候选（$(wc -l < "$WORK/remote-candidates.txt") 个）"
  awk -F'|' -v c="$CUTOFF" -v a="<$AUTHOR>" -v p="$PROTECTED" '
    {
      name=$1; sub(/^origin\//,"",name)
      if ($3==a && $2<c && name !~ p) printf "  %s | %s\n", $2, $1
    }
  ' "$REMOTE_RAW" | sort
} > "$WORK/candidates-preview.txt"

echo "本地候选: $(wc -l < "$WORK/local-candidates.txt")"
echo "远端候选: $(wc -l < "$WORK/remote-candidates.txt")"
echo "预览: "$WORK/candidates-preview.txt""
