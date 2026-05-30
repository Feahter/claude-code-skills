#!/usr/bin/env bash
# gen-unit-test.sh —— 按模板生成单元 / 集成测试（.test.ts / .test.tsx）
# 用法：gen-unit-test.sh --template <name> --out <path> [--name "用例名"] [--module <import路径>] [--import <符号>] [--component <组件名>] [--api <pattern>]

set -euo pipefail

usage() {
  cat <<'EOF'
gen-unit-test.sh —— 从模板生成单元 / 集成测试文件

用法:
  gen-unit-test.sh --template <name> --out <path> [选项]
  gen-unit-test.sh --help
  gen-unit-test.sh --list

可用模板:
  unit-pure               纯逻辑参数化（it.each + 边界 + 异常）   → .test.ts
  hook                    React Hook（renderHook + act）          → .test.ts
  component-integration   组件集成（RTL + userEvent + MSW）        → .test.tsx

选项:
  --template <name>    必填，见上方列表
  --out <path>         必填，输出路径（如 src/utils/price.test.ts）
  --name "<text>"      用例标题（中文），默认从 out 路径推
  --module <path>      被测模块 import 路径（如 ./price 或 ../hooks/useCounter），默认 ./TODO_MODULE
  --import <symbol>    被测函数/Hook 名（unit-pure / hook 用），默认从 out 推
  --component <name>   被测组件名（component-integration 用），默认从 out 推
  --api <pattern>      MSW handler 路径（component-integration 用），默认 /api/example

行为:
  - 不会覆盖已存在的输出文件
  - 默认落点不进 tests/e2e（单测与源码同目录或就近放）
  - 输出后提示：项目有测试标杆 / 专属生成 skill 时优先照标杆调整
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TPL_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"

# 模板名 → 文件后缀映射
tpl_suffix() {
  case "$1" in
    component-integration) echo "test.tsx.tmpl" ;;
    unit-pure|hook) echo "test.ts.tmpl" ;;
    *) echo "" ;;
  esac
}

TEMPLATE=""; OUT=""; NAME=""; MODULE_PATH="./TODO_MODULE"; IMPORT_NAME=""; COMPONENT_NAME=""; API_PATTERN="/api/example"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --list) ls -1 "$TPL_DIR" | grep -E '\.test\.tsx?\.tmpl$' | sed -E 's/\.test\.tsx?\.tmpl$//'; exit 0 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --module) MODULE_PATH="$2"; shift 2 ;;
    --import) IMPORT_NAME="$2"; shift 2 ;;
    --component) COMPONENT_NAME="$2"; shift 2 ;;
    --api) API_PATTERN="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$TEMPLATE" ]] && { echo "缺 --template" >&2; usage >&2; exit 1; }
[[ -z "$OUT" ]] && { echo "缺 --out" >&2; usage >&2; exit 1; }

SUFFIX="$(tpl_suffix "$TEMPLATE")"
[[ -z "$SUFFIX" ]] && { echo "未知模板: $TEMPLATE" >&2; echo "可用："; ls -1 "$TPL_DIR" | grep -E '\.test\.tsx?\.tmpl$' >&2; exit 1; }

TPL_FILE="$TPL_DIR/$TEMPLATE.$SUFFIX"
[[ -f "$TPL_FILE" ]] || { echo "模板不存在: $TPL_FILE" >&2; exit 1; }

[[ -e "$OUT" ]] && { echo "目标文件已存在，拒绝覆盖: $OUT" >&2; exit 1; }

# 落点保护：单测不该进 E2E 目录
case "$OUT" in
  */e2e/*|tests/e2e/*) echo "⚠️ 拒绝把单测落进 E2E 目录: ${OUT} —— 单测与源码同目录或就近放，见 references/test-pyramid.md" >&2; exit 1 ;;
esac

# 默认值从 out 路径推（去掉 .test.ts / .test.tsx 后缀）
BASE="$(basename "$OUT")"; BASE="${BASE%.test.tsx}"; BASE="${BASE%.test.ts}"
[[ -z "$NAME" ]] && NAME="$(echo "$BASE" | tr '-' ' ')"
[[ -z "$IMPORT_NAME" ]] && IMPORT_NAME="$BASE"
[[ -z "$COMPONENT_NAME" ]] && COMPONENT_NAME="$BASE"

mkdir -p "$(dirname "$OUT")"

# 占位符替换
sed -e "s|__TEST_NAME__|$NAME|g" \
    -e "s|__MODULE_PATH__|$MODULE_PATH|g" \
    -e "s|__IMPORT_NAME__|$IMPORT_NAME|g" \
    -e "s|__COMPONENT_NAME__|$COMPONENT_NAME|g" \
    -e "s|__API_PATTERN__|$API_PATTERN|g" \
    "$TPL_FILE" > "$OUT"

echo "✅ 已生成: $OUT"
echo
echo "📝 后续手动操作:"
echo "   1) 填 TODO：补全输入代表点 / 用户操作 / 断言（模板只给骨架）"
echo "   2) 项目若有测试标杆或专属生成 skill，优先照标杆调整命名/打桩风格；本模板为通用兜底"
echo "   3) 跑 validate-unit.sh $OUT 校验"
