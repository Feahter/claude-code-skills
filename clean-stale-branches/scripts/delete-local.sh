#!/usr/bin/env bash
# delete-local.sh [--force] [--dry-run]
# 默认 git branch -d（安全，只删已合并）；--force 用 -D 强删
# --dry-run 只打印计划，不执行
# 读取 $WORK/local-candidates.txt

set -euo pipefail
source "$(dirname "$0")/_workdir.sh"

MODE="safe"
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --force) MODE="force" ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

SRC="$WORK/local-candidates.txt"
[ -f "$SRC" ] || { echo "未找到候选文件: $SRC" >&2; exit 1; }

DELETED="$WORK/deleted-local.txt"
UNMERGED="$WORK/unmerged-local.txt"
ERRLOG="$WORK/delete-local.err.log"
# deleted-local.txt 只追加不清空：先 safe 再 --force 跑两轮时，第一轮的记录要留给 restore-local.sh
touch "$DELETED"
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

n_deleted=0
while IFS= read -r br; do
  [ -z "$br" ] && continue
  # 删之前记下分支指向的提交，恢复时直接用它；分支删掉后它自己的 reflog 也没了
  sha=$(git rev-parse --verify -q "refs/heads/$br^{commit}" || true)
  # stderr 落盘，排查"不是未合并而是别的错（锁/权限/名字怪）"时有据可查
  if err=$(git branch "$flag" "$br" 2>&1 >/dev/null); then
    printf '%s\t%s\n' "$br" "$sha" >> "$DELETED"
    n_deleted=$((n_deleted + 1))
  else
    echo "$br" >> "$UNMERGED"
    printf '[%s] %s\n' "$br" "$err" >> "$ERRLOG"
  fi
done < "$SRC"

echo "模式: $MODE"
echo "已删除: $n_deleted"
echo "未删除（未合并/失败）: $(wc -l < "$UNMERGED")"
[ -s "$ERRLOG" ] && echo "错误详情: $ERRLOG"

if [ "$n_deleted" -gt 0 ]; then
  echo
  echo "提示：删除前的 sha 记在 ${DELETED}，可用 restore-local.sh 恢复"
  echo "  restore-local.sh            # 列出可恢复清单"
  echo "  restore-local.sh <branch>   # 恢复单个分支"
fi
