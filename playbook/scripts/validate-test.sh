#!/usr/bin/env bash
# validate-test.sh —— 静态 + 动态双检测试文件
# 用法：validate-test.sh <spec-file> [--skip-runtime]

set -euo pipefail

usage() {
  cat <<'EOF'
validate-test.sh —— 校验 Playwright 测试文件

用法:
  validate-test.sh <spec-file> [--skip-runtime]
  validate-test.sh --help

静态检查（grep 规则，确定性）:
  ❌ 含 page.waitForTimeout / page.wait(\d+)
  ❌ 含 :nth-child / xpath= / css=
  ❌ 含动态 className（.css-[a-z0-9]+）
  ❌ 没有任何 expect(...).toBe*/toHave*
  ⚠️ 用例描述含 validation/format/util/hover/style 等 unit 该测的关键字
  ⚠️ spec 直接 page.click/page.fill 多次（建议抽业务动作 tests/actions/）
  ℹ️ 关键操作未用双模态断言（toBeInViewport + toHaveCSS opacity）

动态检查（除非 --skip-runtime）:
  - 跑 npx playwright test <file> 1 次
  - 通过但 < 1s 警告（可能空跑）
  - 跑 3 次看 flaky

退出码: 0 全过；1 静态失败；2 动态失败；3 flaky
EOF
}

SKIP_RUNTIME=false
FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --skip-runtime) SKIP_RUNTIME=true; shift ;;
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

# ❌ waitForTimeout / page.wait
check_pattern 'waitForTimeout|page\.wait\(' "禁止使用 waitForTimeout / page.wait(ms)，改用 web-first 断言（references/assertions.md）" error

# ❌ nth-child / xpath / css= 显式 engine
check_pattern ':nth-child|xpath=|css=' "禁止使用 nth-child / xpath / css=，改用 Role/Label/TestId（references/selectors.md）" error

# ⚠️ 动态 className
check_pattern "['\"]\.[a-zA-Z]+-[a-z0-9]{4,}" "可能的动态 className（如 .css-abc123 / .MuiButton-root-xxxx），UI 库升级会挂" warn

# ❌ 没断言
if ! grep -qE "expect\(.+\)\.(toBe|toHave|toContain|toMatch)" "$FILE"; then
  echo "❌ 文件中没有 web-first 断言（expect(...).toBe*/toHave*）"
  FAIL=1
fi

# ⚠️ E2E 黑名单：用例描述含 unit/component 该测的关键字
TEST_DESCS=$(grep -nE "test\(\s*['\"\`]" "$FILE" || true)
if [[ -n "$TEST_DESCS" ]]; then
  BAD_DESCS=$(echo "$TEST_DESCS" | grep -iE "validation|校验.*格式|format|parse|util|hover|tooltip|color|样式|边界.*case|edge.case" || true)
  if [[ -n "$BAD_DESCS" ]]; then
    echo "⚠️  用例描述含 unit/component 该测的关键字（references/architecture.md E2E 黑名单）"
    echo "$BAD_DESCS" | sed 's/^/    /'
  fi
fi

# ⚠️ spec 直接 UI 操作过多（建议抽业务动作）
UI_OPS=$(grep -cE "page\.(click|fill|press|type|check|selectOption)\(" "$FILE" || true)
if [[ $UI_OPS -ge 8 ]]; then
  echo "⚠️  spec 中直接 UI 操作 $UI_OPS 处，建议抽到 tests/actions/ 业务动作（references/architecture.md）"
fi

# ℹ️ 关键操作（提交订单/支付/删除）未用双模态断言
CRITICAL=$(grep -iE "提交订单|支付|确认删除|审批|结算" "$FILE" || true)
if [[ -n "$CRITICAL" ]]; then
  if ! grep -qE "toBeInViewport|toHaveAccessibleName|toHaveCSS\(['\"]opacity" "$FILE"; then
    echo "ℹ️  涉及关键操作但未用双模态断言（toBeInViewport / toHaveCSS opacity），高风险按钮被遮挡时会漏报"
    echo "    详见 references/assertions.md 双模态断言"
  fi
fi

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

# 动态检查
RUNNER=""
if command -v pnpm >/dev/null 2>&1 && [[ -f "pnpm-lock.yaml" ]]; then RUNNER="pnpm exec";
elif command -v yarn >/dev/null 2>&1 && [[ -f "yarn.lock" ]]; then RUNNER="yarn";
elif command -v bunx >/dev/null 2>&1 && [[ -f "bun.lockb" ]]; then RUNNER="bunx";
else RUNNER="npx"; fi

# 整体硬上限：dev server / webServer 没起来时 playwright test 会一直等，防止永久卡死。
# macOS 默认无 timeout，探测 gtimeout（brew coreutils）兜底；都没有则只靠 playwright 自身的 --timeout。
TIMEOUT_WRAP=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_WRAP="timeout 180";
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_WRAP="gtimeout 180"; fi

echo
echo "🏃 动态检查（跑 1 次）"
START=$(date +%s)
if ! $TIMEOUT_WRAP $RUNNER playwright test "$FILE" --reporter=line --max-failures=1 --timeout=60000; then
  echo "❌ 用例失败（或 180s 整体超时——多半是 dev server / webServer 没起来），请看 trace（references/trace-debug.md）"
  exit 2
fi
END=$(date +%s)
DUR=$((END - START))
echo "✅ 用例通过（耗时 ${DUR}s）"

if [[ $DUR -lt 1 ]]; then
  echo "⚠️  耗时 < 1s，可能是空跑（没真正等到 UI），请确认断言充分"
fi

echo
echo "🔁 跑 3 次看是否 flaky"
PASS=0; FAIL_CNT=0
for i in 1 2 3; do
  if $TIMEOUT_WRAP $RUNNER playwright test "$FILE" --reporter=line --max-failures=1 --timeout=60000 >/dev/null 2>&1; then
    PASS=$((PASS+1))
    echo "  [$i/3] ✅"
  else
    FAIL_CNT=$((FAIL_CNT+1))
    echo "  [$i/3] ❌"
  fi
done

if [[ $FAIL_CNT -gt 0 ]]; then
  echo
  echo "⛔ Flaky！3 次中失败 $FAIL_CNT 次。进 references/flaky.md 排查决策树"
  exit 3
fi

echo "✅ 3 次全过，稳定"
