#!/usr/bin/env bash
# restore-local.sh [branch-name]
# 从 $WORK/deleted-local.txt 取 delete-local.sh 删除前记下的 sha，用 checkout -b 恢复
# 不带参数：列出清单里每个分支的恢复信息
# 不从 reflog 反推：HEAD 的 reflog 只记录 HEAD 去了哪，"moving from <br>" 那条的 sha 是切走后的目标提交，不是分支末端

set -euo pipefail
source "$(dirname "$0")/_workdir.sh"

LIST="$WORK/deleted-local.txt"

# 同一分支删过多次时取最后一条；旧格式（只有分支名）的行取到空串
lookup_sha() {
  awk -F'\t' -v b="$1" '$1 == b { s = $2 } END { print s }' "$LIST"
}

show_candidate() {
  local br="$1" sha="$2"
  if [ -z "$sha" ]; then
    printf "  ?        %s  (清单里没记 sha，旧版脚本删除的)\n" "$br"
  elif ! git cat-file -e "${sha}^{commit}" 2>/dev/null; then
    printf "  %.8s  %s  (提交已不在库里，可能被 gc 清理)\n" "$sha" "$br"
  elif git show-ref --verify -q "refs/heads/$br"; then
    printf "  %.8s  %s  (同名分支已存在)\n" "$sha" "$br"
  else
    printf "  %.8s  %s  %s\n" "$sha" "$br" "$(git log -1 --format='%s' "$sha")"
  fi
}

if [ ! -f "$LIST" ]; then
  echo "未找到删除清单: $LIST" >&2
  echo "restore-local.sh 只恢复 delete-local.sh 删掉的分支，需在同一仓库下运行" >&2
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "可恢复清单（sha | branch | last commit）:"
  # 每个分支只列一次，sha 取最后一次删除时记下的
  awk -F'\t' 'NF && !seen[$1]++ { print $1 }' "$LIST" | while IFS= read -r br; do
    show_candidate "$br" "$(lookup_sha "$br")"
  done
  echo
  echo "恢复单个分支: restore-local.sh <branch>"
  exit 0
fi

BR="$1"
SHA=$(lookup_sha "$BR")

if [ -z "$SHA" ]; then
  echo "删除清单里没有分支 ${BR} 的 sha" >&2
  echo "若是旧版脚本删的，可在 git reflog 里找 \"checkout: moving from ${BR} to\" 那一行，" >&2
  echo "它下面一行（更早的那条）的 sha 才是当时 ${BR} 所在提交，恢复前先 git log 核对" >&2
  exit 1
fi

if ! git cat-file -e "${SHA}^{commit}" 2>/dev/null; then
  echo "提交 ${SHA} 已不在库里，无法恢复 ${BR}" >&2
  exit 1
fi

echo "找到 ${BR} 删除前的 sha: ${SHA}"
git log -1 --format='%h %s (%cr)' "$SHA"
read -rp "恢复为本地分支 ${BR}？[y/N] " ans
case "$ans" in
  y|Y) git checkout -b "$BR" "$SHA" ;;
  *) echo "已取消"; exit 0 ;;
esac
