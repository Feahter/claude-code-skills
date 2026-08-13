#!/usr/bin/env bash
# restore-local.sh [branch-name]
# 从 reflog 找最近这个分支最后的 sha，用 checkout -b 恢复
# 不带参数：列出 tmp/branch-cleanup/deleted-local.txt 里每个分支的恢复信息

set -euo pipefail

show_candidate() {
  local br="$1"
  # reflog 里找 "checkout: moving from $br" / "branch: Created from" 这类记录
  local sha
  sha=$(git reflog --all --pretty='%h %gs' 2>/dev/null \
    | grep -E "(checkout: moving from $br |branch: Created from .*$br|$br@\{)" \
    | head -1 | awk '{print $1}' || true)
  if [ -n "$sha" ]; then
    local subject
    subject=$(git log -1 --format='%s' "$sha" 2>/dev/null || echo "?")
    printf "  %s  %s  %s\n" "$sha" "$br" "$subject"
  else
    printf "  ?       %s  (reflog 未找到)\n" "$br"
  fi
}

if [ $# -eq 0 ]; then
  LIST="tmp/branch-cleanup/deleted-local.txt"
  if [ ! -f "$LIST" ]; then
    echo "用法: restore-local.sh <branch-name>" >&2
    echo "或在跑过 delete-local.sh 的目录下无参数运行，列出可恢复清单" >&2
    exit 1
  fi
  echo "可恢复清单（sha | branch | last commit）:"
  while IFS= read -r br; do
    [ -z "$br" ] && continue
    show_candidate "$br"
  done < "$LIST"
  echo
  echo "手动恢复: git checkout -b <branch> <sha>"
  exit 0
fi

BR="$1"
SHA=$(git reflog --all --pretty='%h %gs' \
  | grep -E "(checkout: moving from $BR |branch: Created from .*$BR|$BR@\{)" \
  | head -1 | awk '{print $1}' || true)

if [ -z "$SHA" ]; then
  echo "reflog 未找到分支 $BR 的记录" >&2
  exit 1
fi

echo "找到 $BR 最近的 sha: $SHA"
git log -1 --format='%h %s (%cr)' "$SHA"
read -rp "恢复为本地分支 $BR？[y/N] " ans
case "$ans" in
  y|Y) git checkout -b "$BR" "$SHA" ;;
  *) echo "已取消"; exit 0 ;;
esac
