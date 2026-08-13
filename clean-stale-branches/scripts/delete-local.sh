#!/usr/bin/env bash
# delete-local.sh [--force] [--dry-run]
# 默认 git branch -d（安全，只删已合并）；--force 用 -D 强删
# --dry-run 只打印计划，不执行
# 读取 tmp/branch-cleanup/local-candidates.txt

set -euo pipefail

MODE="safe"
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --force) MODE="force" ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

SRC="tmp/branch-cleanup/local-candidates.txt"
[ -f "$SRC" ] || { echo "未找到候选文件: $SRC" >&2; exit 1; }

DELETED="tmp/branch-cleanup/deleted-local.txt"
UNMERGED="tmp/branch-cleanup/unmerged-local.txt"
ERRLOG="tmp/branch-cleanup/delete-local.err.log"
: > "$DELETED"
: > "$UNMERGED"
: > "$ERRLOG"

flag="-d"
[ "$MODE" = "force" ] && flag="-D"

if [ "$DRY_RUN" = "1" ]; then
  echo "[dry-run] 模式: $MODE   命令: git branch $flag <branch>"
  echo "[dry-run] 待处理: $(wc -l < "$SRC" | tr -d ' ') 个"
  awk 'NF' "$SRC" | sed 's/^/  /'
  exit 0
fi

while IFS= read -r br; do
  [ -z "$br" ] && continue
  # stderr 落盘，排查"不是未合并而是别的错（锁/权限/名字怪）"时有据可查
  if err=$(git branch "$flag" "$br" 2>&1 >/dev/null); then
    echo "$br" >> "$DELETED"
  else
    echo "$br" >> "$UNMERGED"
    printf '[%s] %s\n' "$br" "$err" >> "$ERRLOG"
  fi
done < "$SRC"

echo "模式: $MODE"
echo "已删除: $(wc -l < "$DELETED")"
echo "未删除（未合并/失败）: $(wc -l < "$UNMERGED")"
[ -s "$ERRLOG" ] && echo "错误详情: $ERRLOG"

# 善意提示：reflog 是本地删除的后悔药
if [ -s "$DELETED" ]; then
  echo
  echo "提示：本地删除可通过 reflog 恢复"
  echo "  git reflog | grep 'branch: Created'    # 找分支创建/切换记录"
  echo "  git checkout -b <name> <sha>           # 从 sha 恢复"
fi
