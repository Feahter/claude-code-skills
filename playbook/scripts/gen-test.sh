#!/usr/bin/env bash
# gen-test.sh —— 按模板生成 .spec.ts
# 用法：gen-test.sh --template <name> --out <path> [--name "用例名"] [--url <path>] [--api <pattern>]

set -euo pipefail

usage() {
  cat <<'EOF'
gen-test.sh —— 从模板生成 .spec.ts 测试文件

用法:
  gen-test.sh --template <name> --out <path> [选项]
  gen-test.sh --help
  gen-test.sh --list

可用模板:
  happy-path          基础用户流程
  auth-required       需登录页面
  form-submit         表单提交
  api-mock            带 API mock 的用例
  visual-regression   视觉回归
  business-dsl        业务 DSL 风格（spec 调业务动作，跨页/多步流程用）
  permission-check    权限边界（授权角色能进、未授权被挡，多角色场景用）

选项:
  --template <name>   必填，见上方列表
  --out <path>        必填，输出 .spec.ts 路径
  --name "<text>"     用例标题（中文），默认从 out 路径推
  --url <path>        测试目标路径（如 /orders），默认 /
  --api <pattern>     API mock 时的匹配 pattern（仅 api-mock 模板用）

行为:
  - 不会覆盖已存在的输出文件
  - 输出文件后追加提示：哪些占位符还需手动替换
EOF
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TPL_DIR="$(cd "$SCRIPT_DIR/../templates" && pwd)"

TEMPLATE=""; OUT=""; NAME=""; URL_PATH="/"; API_PATTERN="**/api/example"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --list) ls -1 "$TPL_DIR" | sed 's/\.spec\.ts\.tmpl$//'; exit 0 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --url) URL_PATH="$2"; shift 2 ;;
    --api) API_PATTERN="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$TEMPLATE" ]] && { echo "缺 --template" >&2; usage >&2; exit 1; }
[[ -z "$OUT" ]] && { echo "缺 --out" >&2; usage >&2; exit 1; }

TPL_FILE="$TPL_DIR/$TEMPLATE.spec.ts.tmpl"
[[ -f "$TPL_FILE" ]] || { echo "模板不存在: $TPL_FILE" >&2; echo "可用："; ls "$TPL_DIR" >&2; exit 1; }

[[ -e "$OUT" ]] && { echo "目标文件已存在，拒绝覆盖: $OUT" >&2; exit 1; }

[[ -z "$NAME" ]] && NAME="$(basename "$OUT" .spec.ts | tr '-' ' ')"

mkdir -p "$(dirname "$OUT")"

# 占位符替换
sed -e "s|__TEST_NAME__|$NAME|g" \
    -e "s|__URL_PATH__|$URL_PATH|g" \
    -e "s|__API_PATTERN__|$API_PATTERN|g" \
    "$TPL_FILE" > "$OUT"

echo "✅ 已生成: $OUT"
echo
echo "📝 后续手动操作:"
echo "   1) 检查 selector，按 references/selectors.md 优先级（Role > Label > Text > TestId）"
echo "   2) 跑 npx playwright codegen <baseURL>$URL_PATH 抓真实 selector 替换占位符"
echo "   3) 跑 validate-test.sh $OUT 校验"
