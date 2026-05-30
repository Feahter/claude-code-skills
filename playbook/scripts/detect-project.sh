#!/usr/bin/env bash
# detect-project.sh —— 探测当前目录的前端项目栈，输出 JSON 到 stdout
# 用法：
#   detect-project.sh [--help] [--cwd <path>]
# 输出：
#   JSON 含 framework / language / packageManager / hasPlaywright / configPath / testDir / baseURL / existingSelectors / uiLib

set -euo pipefail

usage() {
  cat <<'EOF'
detect-project.sh —— 探测前端项目栈
用法:
  detect-project.sh [--cwd <path>]
  detect-project.sh --help

输出 JSON 字段:
  framework        next | vite | nuxt | remix | cra | astro | vue-cli | sveltekit | unknown
  language         ts | js
  packageManager   pnpm | yarn | bun | npm
  hasPlaywright    bool
  configPath       string|null
  testDir          string|null
  baseURL          string|null
  existingSelectors {testid,role,css}  各类选择器在已有 spec 里的出现次数
  uiLib            antd | mui | shadcn | element-plus | naive-ui | vuetify | tailwind | unknown
  unitTesting      单测底座 {hasVitest,hasJest,unitRunner,unitConfigPath,
                   hasTestingLibrary,testingLibFlavor,hasMSW,mswHandlersPath,
                   unitTestDir,coverageThresholdsConfigured}

依赖: jq
退出码: 0 成功；2 缺 jq；3 不是项目目录（找不到 package.json）
EOF
}

CWD="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --cwd) CWD="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "缺少 jq，请先安装：brew install jq" >&2; exit 2; }
[[ -f "$CWD/package.json" ]] || { echo "$CWD 下没有 package.json" >&2; exit 3; }

PKG="$CWD/package.json"

# --- packageManager ---
PM="npm"
[[ -f "$CWD/pnpm-lock.yaml" ]] && PM="pnpm"
[[ -f "$CWD/yarn.lock" ]] && PM="yarn"
[[ -f "$CWD/bun.lockb" ]] && PM="bun"

# --- language ---
LANG_="js"
[[ -f "$CWD/tsconfig.json" ]] && LANG_="ts"

# --- framework ---
DEPS=$(jq -r '(.dependencies // {}) + (.devDependencies // {}) | keys | join(",")' "$PKG")
FW="unknown"
if [[ -f "$CWD/next.config.js" || -f "$CWD/next.config.ts" || -f "$CWD/next.config.mjs" ]] || echo ",$DEPS," | grep -q ",next,"; then
  FW="next"
elif [[ -f "$CWD/nuxt.config.js" || -f "$CWD/nuxt.config.ts" ]] || echo ",$DEPS," | grep -q ",nuxt,"; then
  FW="nuxt"
elif echo ",$DEPS," | grep -q ",@remix-run/"; then
  FW="remix"
elif echo ",$DEPS," | grep -q ",@sveltejs/kit,"; then
  FW="sveltekit"
elif [[ -f "$CWD/astro.config.mjs" || -f "$CWD/astro.config.ts" ]] || echo ",$DEPS," | grep -q ",astro,"; then
  FW="astro"
elif [[ -f "$CWD/vite.config.js" || -f "$CWD/vite.config.ts" || -f "$CWD/vite.config.mjs" ]]; then
  FW="vite"
elif echo ",$DEPS," | grep -q ",react-scripts,"; then
  FW="cra"
elif echo ",$DEPS," | grep -q ",@vue/cli-service,"; then
  FW="vue-cli"
fi

# --- hasPlaywright ---
HAS_PW="false"
echo ",$DEPS," | grep -q ",@playwright/test," && HAS_PW="true"

# --- configPath ---
CONFIG_PATH="null"
for f in playwright.config.ts playwright.config.js playwright.config.mjs playwright.config.cjs; do
  if [[ -f "$CWD/$f" ]]; then CONFIG_PATH="\"$f\""; break; fi
done

# --- testDir ---
TEST_DIR="null"
for d in tests/e2e tests e2e test; do
  if [[ -d "$CWD/$d" ]]; then
    if find "$CWD/$d" -maxdepth 3 -name '*.spec.ts' -o -name '*.spec.js' 2>/dev/null | head -1 | grep -q .; then
      TEST_DIR="\"$d\""; break
    fi
  fi
done

# --- baseURL（先 config，后 dev script 推测）---
BASE_URL="null"
if [[ "$CONFIG_PATH" != "null" ]]; then
  CP_RAW=$(echo "$CONFIG_PATH" | tr -d '"')
  URL=$(grep -Eo "baseURL[^,}]*['\"]http[^'\"]+" "$CWD/$CP_RAW" 2>/dev/null | grep -Eo "http[^'\"]+" | head -1 || true)
  [[ -n "$URL" ]] && BASE_URL="\"$URL\""
fi
if [[ "$BASE_URL" == "null" ]]; then
  case "$FW" in
    next|nuxt|remix|cra) BASE_URL='"http://localhost:3000"' ;;
    vite|sveltekit) BASE_URL='"http://localhost:5173"' ;;
    astro) BASE_URL='"http://localhost:4321"' ;;
  esac
fi

# --- existingSelectors（统计 spec 里的用法）---
TESTID_CNT=0; ROLE_CNT=0; CSS_CNT=0
if [[ "$TEST_DIR" != "null" ]]; then
  TD_RAW=$(echo "$TEST_DIR" | tr -d '"')
  if [[ -d "$CWD/$TD_RAW" ]]; then
    TESTID_CNT=$({ grep -rE 'getByTestId|data-testid' "$CWD/$TD_RAW" 2>/dev/null || true; } | wc -l | tr -d ' ')
    ROLE_CNT=$({ grep -rE 'getByRole|getByLabel|getByText' "$CWD/$TD_RAW" 2>/dev/null || true; } | wc -l | tr -d ' ')
    CSS_CNT=$({ grep -rE "page\.locator\(['\"]\\.|nth-child|xpath=" "$CWD/$TD_RAW" 2>/dev/null || true; } | wc -l | tr -d ' ')
  fi
fi

# --- uiLib ---
UI="unknown"
for lib in antd '@mui/material' element-plus naive-ui vuetify; do
  if echo ",$DEPS," | grep -q ",$lib,"; then
    case "$lib" in
      antd) UI="antd" ;;
      '@mui/material') UI="mui" ;;
      element-plus) UI="element-plus" ;;
      naive-ui) UI="naive-ui" ;;
      vuetify) UI="vuetify" ;;
    esac
    break
  fi
done
if [[ "$UI" == "unknown" ]] && echo ",$DEPS," | grep -q ",tailwindcss,"; then
  UI="tailwind"
fi
if [[ "$UI" == "unknown" ]] && [[ -d "$CWD/components/ui" || -f "$CWD/components.json" ]]; then
  UI="shadcn"
fi

# --- 单测底座（unitTesting）：探测 vitest/jest + RTL + msw，给规划阶段判断分层承接 ---
HAS_VITEST="false"; HAS_JEST="false"
echo ",$DEPS," | grep -q ",vitest," && HAS_VITEST="true"
echo ",$DEPS," | grep -q ",jest," && HAS_JEST="true"
UNIT_RUNNER="none"
[[ "$HAS_JEST" == "true" ]] && UNIT_RUNNER="jest"
[[ "$HAS_VITEST" == "true" ]] && UNIT_RUNNER="vitest"

UNIT_CONFIG="null"
for f in vitest.config.ts vitest.config.js vitest.config.mts vitest.config.mjs \
         jest.config.ts jest.config.js jest.config.cjs jest.config.mjs; do
  if [[ -f "$CWD/$f" ]]; then UNIT_CONFIG="\"$f\""; break; fi
done
# package.json 内联 jest 配置兜底
if [[ "$UNIT_CONFIG" == "null" ]] && jq -e '.jest' "$PKG" >/dev/null 2>&1; then
  UNIT_CONFIG='"package.json#jest"'
fi

HAS_TL="false"; TL_FLAVOR="none"
if echo ",$DEPS," | grep -q ",@testing-library/react,"; then HAS_TL="true"; TL_FLAVOR="react"
elif echo ",$DEPS," | grep -q ",@testing-library/vue,"; then HAS_TL="true"; TL_FLAVOR="vue"
elif echo ",$DEPS," | grep -q ",@testing-library/dom,"; then HAS_TL="true"; TL_FLAVOR="dom"
fi

HAS_MSW="false"
echo ",$DEPS," | grep -q ",msw," && HAS_MSW="true"

MSW_HANDLERS="null"
for f in src/mocks/handlers.ts src/mocks/handlers.js mocks/handlers.ts mocks/handlers.js \
         src/test-utils/msw/handlers.ts src/test-utils/msw/handlers.js \
         src/test-utils/handlers.ts src/test-utils/handlers.js; do
  if [[ -f "$CWD/$f" ]]; then MSW_HANDLERS="\"$f\""; break; fi
done

# 单测目录：找含 *.test.ts(x) 的目录，排除 E2E 目录，优先 src
UNIT_TEST_DIR="null"
for d in src tests/unit test tests; do
  if [[ -d "$CWD/$d" ]]; then
    if find "$CWD/$d" -maxdepth 4 -path '*/e2e/*' -prune -o \
         \( -name '*.test.ts' -o -name '*.test.tsx' \) -print 2>/dev/null | head -1 | grep -q .; then
      UNIT_TEST_DIR="\"$d\""; break
    fi
  fi
done

# 覆盖率门限是否已配（供规划阶段判断要不要对照门限表）
COV_THRESH="false"
if [[ "$UNIT_CONFIG" != "null" && "$UNIT_CONFIG" != '"package.json#jest"' ]]; then
  UC_RAW=$(echo "$UNIT_CONFIG" | tr -d '"')
  grep -qE "thresholds|coverageThreshold" "$CWD/$UC_RAW" 2>/dev/null && COV_THRESH="true"
elif jq -e '.jest.coverageThreshold' "$PKG" >/dev/null 2>&1; then
  COV_THRESH="true"
fi

# --- 输出 JSON ---
jq -n \
  --arg fw "$FW" \
  --arg lang "$LANG_" \
  --arg pm "$PM" \
  --argjson hasPw "$HAS_PW" \
  --argjson configPath "$CONFIG_PATH" \
  --argjson testDir "$TEST_DIR" \
  --argjson baseURL "$BASE_URL" \
  --argjson testidCnt "$TESTID_CNT" \
  --argjson roleCnt "$ROLE_CNT" \
  --argjson cssCnt "$CSS_CNT" \
  --arg ui "$UI" \
  --argjson hasVitest "$HAS_VITEST" \
  --argjson hasJest "$HAS_JEST" \
  --arg unitRunner "$UNIT_RUNNER" \
  --argjson unitConfigPath "$UNIT_CONFIG" \
  --argjson hasTL "$HAS_TL" \
  --arg tlFlavor "$TL_FLAVOR" \
  --argjson hasMSW "$HAS_MSW" \
  --argjson mswHandlers "$MSW_HANDLERS" \
  --argjson unitTestDir "$UNIT_TEST_DIR" \
  --argjson covThresh "$COV_THRESH" \
'{
  framework: $fw,
  language: $lang,
  packageManager: $pm,
  hasPlaywright: $hasPw,
  configPath: $configPath,
  testDir: $testDir,
  baseURL: $baseURL,
  existingSelectors: { testid: $testidCnt, role: $roleCnt, css: $cssCnt },
  uiLib: $ui,
  unitTesting: {
    hasVitest: $hasVitest,
    hasJest: $hasJest,
    unitRunner: $unitRunner,
    unitConfigPath: $unitConfigPath,
    hasTestingLibrary: $hasTL,
    testingLibFlavor: $tlFlavor,
    hasMSW: $hasMSW,
    mswHandlersPath: $mswHandlers,
    unitTestDir: $unitTestDir,
    coverageThresholdsConfigured: $covThresh
  }
}'
