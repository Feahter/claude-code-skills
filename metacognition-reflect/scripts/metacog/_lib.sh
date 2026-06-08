#!/usr/bin/env bash
# 公共工具函数与路径常量。被其它脚本 source。

set -eu

METACOG_HOME="${METACOG_HOME:-$HOME/.claude/scripts/metacog}"
METACOG_LOG="${METACOG_LOG:-/tmp/metacog.log}"

# 单个 project 的 memory 目录推导：根据 cwd 自动推导 ~/.claude/projects/<slug>/memory
metacog_memdir_for_cwd() {
  local cwd="${1:-$PWD}"
  # 把路径里的 / 换成 -，前面加 -；这是 ~/.claude/projects/ 下的 slug 规则
  local slug
  slug="$(printf '%s' "$cwd" | sed 's|/|-|g')"
  # slug 前应以 - 开头
  case "$slug" in
    -*) ;;
    *) slug="-$slug" ;;
  esac
  echo "$HOME/.claude/projects/$slug/memory"
}

# 备用：cwd 推导失败时，回退到当前工作目录的 slug（可用 METACOG_DEFAULT_MEMDIR 覆盖）
metacog_default_memdir() {
  echo "${METACOG_DEFAULT_MEMDIR:-$(metacog_memdir_for_cwd)}"
}

metacog_log() {
  local line
  line="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
  echo "$line" >> "$METACOG_LOG" 2>/dev/null || true
}

# 读 stdin，最多 N 字节（防 hook 阻塞）
metacog_read_stdin_capped() {
  local max="${1:-65536}"
  head -c "$max" || true
}

# jq 是否可用
metacog_has_jq() {
  command -v jq >/dev/null 2>&1
}
