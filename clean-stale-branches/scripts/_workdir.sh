# 被其他脚本 source：产物放仓库外的临时目录，按仓库路径区分，不往用户仓库里写文件
_top="$(git rev-parse --show-toplevel)"
_base="${TMPDIR:-/tmp}"
WORK="${BRANCH_CLEANUP_DIR:-${_base%/}/branch-cleanup/$(basename "$_top")-$(printf '%s' "$_top" | shasum | cut -c1-8)}"
mkdir -p "$WORK"
