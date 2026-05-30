#!/usr/bin/env bash
# coverage-audit.sh —— 审计 .playbook/test-plan.md 在 6 维度上的覆盖度
# 用法：coverage-audit.sh [--plan <path>]

set -euo pipefail

usage() {
  cat <<'EOF'
coverage-audit.sh —— 审计测试计划在对抗覆盖 6 维度上的差距

用法:
  coverage-audit.sh [--plan <path>]
  coverage-audit.sh --help

维度:
  exception   异常路径（4xx/5xx/超时）
  role        多角色权限
  network     网络异常（慢网/丢包）
  boundary    边界数据（空/超长/特殊字符）
  concurrency 并发（多 tab/多用户）
  a11y        无障碍（键盘/screen reader）

金字塔检查（references/architecture.md）:
  ❌ 用例命中 E2E 黑名单（validation/format/hover/边界 case 等单测该测的）

输出: 表格 + 金字塔违规清单 + 是否建议派 agent
EOF
}

PLAN=".playbook/test-plan.md"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --plan) PLAN="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$PLAN" ]] || { echo "找不到 test-plan: $PLAN" >&2; exit 1; }

count_keyword() {
  local kws="$1"
  grep -ciE "$kws" "$PLAN" || true
}

EXC=$(count_keyword "异常|失败|错误|4[0-9]{2}|5[0-9]{2}|超时|timeout|exception")
ROLE=$(count_keyword "角色|admin|guest|权限|role|permission")
NET=$(count_keyword "网络|慢网|断网|丢包|offline|network")
BND=$(count_keyword "边界|空|超长|特殊字符|emoji|boundary|empty|max")
CON=$(count_keyword "并发|多tab|同时|concurrency|race")
A11Y=$(count_keyword "a11y|无障碍|键盘|aria|tab顺序|screen reader")

echo "📊 对抗覆盖审计：$PLAN"
echo
printf "%-15s %-6s %s\n" "维度" "用例数" "状态"
printf "%-15s %-6s %s\n" "---" "---" "---"
report() {
  local name="$1" cnt="$2"
  if [[ $cnt -ge 3 ]]; then echo -e "$(printf "%-15s %-6s" "$name" "$cnt") ✅";
  elif [[ $cnt -ge 1 ]]; then echo -e "$(printf "%-15s %-6s" "$name" "$cnt") ⚠️ 偏少";
  else echo -e "$(printf "%-15s %-6s" "$name" "$cnt") ❌ 缺失"; fi
}
report "exception"   "$EXC"
report "role"        "$ROLE"
report "network"     "$NET"
report "boundary"    "$BND"
report "concurrency" "$CON"
report "a11y"        "$A11Y"

TOTAL=$((EXC + ROLE + NET + BND + CON + A11Y))
MISSING=0
for v in $EXC $ROLE $NET $BND $CON $A11Y; do
  [[ $v -eq 0 ]] && MISSING=$((MISSING+1))
done

echo
echo "🔍 金字塔检查：E2E 黑名单"
PYRAMID_HITS=$(grep -inE "validation|校验.*格式|format|parse|util|hover|tooltip|color|样式|边界.*case|edge.case" "$PLAN" || true)
if [[ -n "$PYRAMID_HITS" ]]; then
  echo "❌ 命中 E2E 黑名单（建议改 unit/component test，详见 references/architecture.md）"
  echo "$PYRAMID_HITS" | sed 's/^/    /'
  PYRAMID_FAIL=1
else
  echo "✅ 未命中 E2E 黑名单"
  PYRAMID_FAIL=0
fi

echo
if [[ $MISSING -ge 3 ]]; then
  echo "🚨 建议：缺失维度 $MISSING 个，按 references/adversarial-coverage.md 派 agent 补"
  [[ $PYRAMID_FAIL -eq 1 ]] && echo "   同时清理金字塔违规用例"
  exit 2
elif [[ $MISSING -ge 1 ]] || [[ $PYRAMID_FAIL -eq 1 ]]; then
  echo "⚠️  缺失 $MISSING 个维度 / 金字塔违规 $PYRAMID_FAIL 处，可考虑派 agent 或人工补"
  exit 1
else
  echo "✅ 6 维度均有覆盖，金字塔合规"
  exit 0
fi
