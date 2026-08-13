#!/usr/bin/env bash
# delete-remote.sh [--dry-run]
# 读取 tmp/branch-cleanup/remote-candidates.txt，分批 push 删除
# 整批失败时回退到单条重试，避免一个坏分支连累整批

set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

SRC="tmp/branch-cleanup/remote-candidates.txt"
[ -f "$SRC" ] || { echo "未找到候选文件: $SRC" >&2; exit 1; }

DELETED="tmp/branch-cleanup/deleted-remote.txt"
FAILED="tmp/branch-cleanup/failed-remote.txt"
LOG="tmp/branch-cleanup/push.log"
: > "$DELETED"
: > "$FAILED"
: > "$LOG"

TOTAL=$(awk 'NF' "$SRC" | wc -l | tr -d ' ')

if [ "$DRY_RUN" = "1" ]; then
  echo "[dry-run] 将删除远端分支 $TOTAL 个（分批 10 个/次）"
  echo "[dry-run] 示例命令: git push origin :br1 :br2 ..."
  awk 'NF' "$SRC" | sed 's/^/  :/'
  exit 0
fi

# 远端删除不可逆，打个显眼提示
echo "⚠️  即将对 origin 执行 $TOTAL 个分支的删除推送（不可逆）"
echo "   日志: $LOG"

BATCH_SIZE=10
i=0
batch=()

# 批量失败时回退到单条重试——上游已被别人删 / 分支名冲突 / 保护分支拦截
# 这些情况只会连累一个分支，不该让整批失败
retry_single() {
  local ref
  for ref in "$@"; do
    if git push origin "$ref" >>"$LOG" 2>&1; then
      echo "${ref#:}" >> "$DELETED"
    else
      echo "${ref#:}" >> "$FAILED"
    fi
  done
}

flush() {
  [ ${#batch[@]} -eq 0 ] && return 0
  if git push origin "${batch[@]}" >>"$LOG" 2>&1; then
    for ref in "${batch[@]}"; do echo "${ref#:}" >> "$DELETED"; done
  else
    echo "  批量失败，逐条重试..." >&2
    retry_single "${batch[@]}"
  fi
  batch=()
}

while IFS= read -r br; do
  [ -z "$br" ] && continue
  batch+=(":$br")
  i=$((i+1))
  if [ ${#batch[@]} -ge "$BATCH_SIZE" ]; then
    flush
    echo "  ...已处理 $i / $TOTAL"
  fi
done < "$SRC"

flush
[ "$i" -gt 0 ] && [ $((i % BATCH_SIZE)) -ne 0 ] && echo "  ...已处理 $i / $TOTAL"

echo "已删除: $(wc -l < "$DELETED")"
echo "失败: $(wc -l < "$FAILED")"
echo "日志: $LOG"
[ -s "$FAILED" ] && echo "失败清单: $FAILED"
