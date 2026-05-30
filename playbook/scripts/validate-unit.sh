#!/usr/bin/env bash
# validate-unit.sh —— 静态 + 动态双检单元 / 集成测试文件
# 用法：validate-unit.sh <test-file> [--skip-runtime] [--no-coverage]

set -euo pipefail

usage() {
  cat <<'EOF'
validate-unit.sh —— 校验单元 / 集成测试文件（Vitest / Jest）

用法:
  validate-unit.sh <test-file> [--skip-runtime] [--coverage]
  validate-unit.sh --help

静态检查（grep 规则，确定性）:
  ❌ 含 Math.random / Date.now（破坏确定性三角，输出不可复现）
  ❌ 含裸 setTimeout / sleep 等真实等待（改 vi.useFakeTimers）
  ❌ 没有任何 expect(...) 断言
  ⚠️ mock 子组件（vi.mock('./xxx/components')）—— 隐藏真实集成问题
  ⚠️ 用 fireEvent（建议 userEvent，更接近真实交互）
  ⚠️ toMatchSnapshot 但无显式断言 / 快照引用文件过大
  ⚠️ getBy* 配 await（多半该用 findBy*）

动态检查（除非 --skip-runtime）:
  - 跑 vitest run <file>（务必 run，不进 watch）；jest 项目用 jest <file>
  - 默认不带覆盖率：单文件全局 coverage 既无意义又慢，覆盖率看全量回归
  - 加 --coverage 才附 --coverage（仅在需要看该文件覆盖时用）
  - 不连跑（单测确定性强，flaky 看静态 fake-timer 规则）

退出码: 0 全过；1 静态失败；2 动态失败
EOF
}

SKIP_RUNTIME=false
WITH_COVERAGE=false
FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --skip-runtime) SKIP_RUNTIME=true; shift ;;
    --coverage) WITH_COVERAGE=true; shift ;;
    *) FILE="$1"; shift ;;
  esac
done

[[ -z "$FILE" ]] && { echo "缺测试文件路径" >&2; usage >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "文件不存在: $FILE" >&2; exit 1; }

echo "🔍 静态检查: $FILE"
FAIL=0

check_pattern() {
  local pattern="$1"; local message="$2"; local level="$3"  # error|warn
  local hits
  hits=$(grep -nE "$pattern" "$FILE" || true)
  if [[ -n "$hits" ]]; then
    if [[ "$level" == "error" ]]; then
      echo "❌ $message"
      echo "$hits" | sed 's/^/    /'
      FAIL=1
    else
      echo "⚠️  $message"
      echo "$hits" | sed 's/^/    /'
    fi
  fi
}

# ❌ Math.random / Date.now —— 确定性三角
check_pattern 'Math\.random|Date\.now\(' "禁止 Math.random / Date.now（确定性三角，见 references/unit-integration.md）。用固定种子 / vi.setSystemTime" error

# ❌ 裸 setTimeout / sleep 等真实等待
check_pattern '\bsleep\(|setTimeout\(|waitForTimeout' "禁止真实等待（sleep / setTimeout），改 vi.useFakeTimers + advanceTimersByTime（references/flaky.md）" error

# ❌ 没断言
if ! grep -qE "expect\(" "$FILE"; then
  echo "❌ 文件中没有任何 expect(...) 断言"
  FAIL=1
fi

# ⚠️ mock 子组件
check_pattern "(vi|jest)\.mock\(['\"][^'\"]*[Cc]omponents?/" "疑似 mock 子组件，会隐藏真实集成问题（references/unit-integration.md Mock 三刀流）" warn

# ⚠️ fireEvent
check_pattern '\bfireEvent\b' "用了 fireEvent，建议改 userEvent（触发 hover/focus 等真实交互）" warn

# ⚠️ 快照无显式断言
if grep -qE "toMatchSnapshot\(" "$FILE"; then
  if ! grep -qE "expect\(.+\)\.(toBe|toEqual|toHaveText|toContain|toMatchObject|toBeInTheDocument)" "$FILE"; then
    echo "⚠️  只有快照断言、无显式断言（快照只防回退、不测正确，references/unit-integration.md 快照纪律）"
  fi
fi

# ⚠️ getBy* 配 await（多半该用 findBy*）
check_pattern 'await\s+screen\.getBy' "await getBy* 多半该用 findBy*（getBy 不重试，异步元素会抢跑）" warn

if [[ $FAIL -eq 1 ]]; then
  echo
  echo "⛔ 静态检查未通过"
  exit 1
fi

echo "✅ 静态检查通过"

if [[ "$SKIP_RUNTIME" == "true" ]]; then
  echo "（跳过动态检查）"
  exit 0
fi

# 动态检查：探测 runner（vitest 优先，回退 jest）
RUNNER=""
if command -v pnpm >/dev/null 2>&1 && [[ -f "pnpm-lock.yaml" ]]; then RUNNER="pnpm exec";
elif command -v yarn >/dev/null 2>&1 && [[ -f "yarn.lock" ]]; then RUNNER="yarn";
elif command -v bunx >/dev/null 2>&1 && [[ -f "bun.lockb" ]]; then RUNNER="bunx";
else RUNNER="npx"; fi

# 选 vitest 还是 jest：看 devDeps（缺 jq 时默认 vitest）
TEST_TOOL="vitest"
if command -v jq >/dev/null 2>&1 && [[ -f package.json ]]; then
  DEPS=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys | join(",")' package.json 2>/dev/null || echo "")
  if ! echo ",$DEPS," | grep -q ",vitest," && echo ",$DEPS," | grep -q ",jest,"; then
    TEST_TOOL="jest"
  fi
fi

# 默认不带覆盖率：单文件全局 coverage 无意义又慢。需要时显式 --coverage
COV_FLAG=""
[[ "$WITH_COVERAGE" == "true" ]] && COV_FLAG="--coverage"

# 整体硬上限：防止误进 watch 永久卡死
TIMEOUT_WRAP=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_WRAP="timeout 180";
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_WRAP="gtimeout 180"; fi

echo
echo "🏃 动态检查（$TEST_TOOL run，单次）"
if [[ "$TEST_TOOL" == "vitest" ]]; then
  # 务必 run，不进 watch
  CMD="$RUNNER vitest run \"$FILE\" $COV_FLAG --reporter=dot"
else
  CMD="$RUNNER jest \"$FILE\" $COV_FLAG --ci"
fi

if ! eval "$TIMEOUT_WRAP $CMD"; then
  echo "❌ 用例失败（或 180s 超时——若卡住多半误进了 watch，确认用的是 vitest run）"
  exit 2
fi

echo "✅ 用例通过"
if [[ "$WITH_COVERAGE" == "true" ]]; then
  echo
  echo "📊 覆盖率：未配 thresholds 则对照分层门限人工把关（references/test-pyramid.md）；"
  echo "   单文件覆盖率只反映该文件，整体覆盖率看全量回归。"
fi
