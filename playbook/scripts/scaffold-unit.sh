#!/usr/bin/env bash
# scaffold-unit.sh —— 搭建 Vitest 单元/集成测试底座（装包 + 写 config + setup + test-utils + 目录）
# 用法：scaffold-unit.sh [--help] [--cwd <path>] [--pm <pnpm|yarn|npm|bun>] [--flavor <react|vue>]

set -euo pipefail

usage() {
  cat <<'EOF'
scaffold-unit.sh —— 在当前目录搭建 Vitest 单元 / 集成测试底座

用法:
  scaffold-unit.sh [--cwd <path>] [--pm <manager>] [--flavor <react|vue>]
  scaffold-unit.sh --help

行为:
  1) 装 vitest + @vitest/coverage-v8 + jsdom + Testing Library + msw
  2) 写 vitest.config.ts（globals / jsdom / setupFiles / coverage v8 + thresholds）
  3) 写 src/test-utils/{setup,server}.ts（MSW server 生命周期 + jest-dom）
  4) package.json 加 test / test:run / test:coverage / test:ui scripts
  5) 建 src/mocks/handlers.ts（MSW 单一数据源占位）

如果未指定 --pm / --flavor，会自动调 detect-project.sh 探测。
不会覆盖已存在的 vitest.config.* / 不触碰任何 Playwright 文件。
EOF
}

CWD="$(pwd)"
PM=""
FLAVOR=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --pm) PM="$2"; shift 2 ;;
    --flavor) FLAVOR="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

cd "$CWD"

if [[ -z "$PM" || -z "$FLAVOR" ]]; then
  if command -v jq >/dev/null 2>&1 && [[ -f package.json ]]; then
    PROJ_JSON=$(bash "$SCRIPT_DIR/detect-project.sh" 2>/dev/null || echo "{}")
    [[ -z "$PM" ]] && PM=$(echo "$PROJ_JSON" | jq -r '.packageManager // "npm"')
    if [[ -z "$FLAVOR" ]]; then
      TLF=$(echo "$PROJ_JSON" | jq -r '.unitTesting.testingLibFlavor // "none"')
      case "$TLF" in
        vue) FLAVOR="vue" ;;
        *) FLAVOR="react" ;;  # react / dom / none 默认按 react 搭
      esac
    fi
  fi
  [[ -z "$PM" ]] && PM="npm"
  [[ -z "$FLAVOR" ]] && FLAVOR="react"
fi

case "$PM" in
  pnpm) INSTALL="pnpm add -D" ;;
  yarn) INSTALL="yarn add -D" ;;
  bun) INSTALL="bun add -d" ;;
  npm|*) INSTALL="npm i -D" ;;
esac

# Testing Library 按 flavor
TL_PKG="@testing-library/react"
[[ "$FLAVOR" == "vue" ]] && TL_PKG="@testing-library/vue"

echo "==> 装包（vitest + coverage + jsdom + Testing Library($FLAVOR) + msw）"
$INSTALL vitest @vitest/coverage-v8 jsdom "$TL_PKG" @testing-library/user-event @testing-library/jest-dom msw

echo "==> 建目录"
mkdir -p src/test-utils src/mocks

# vitest.config.ts
if [[ ! -f vitest.config.ts && ! -f vitest.config.js && ! -f vitest.config.mts ]]; then
  cat > vitest.config.ts <<'TS'
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test-utils/setup.ts',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      exclude: ['**/*.d.ts', '**/*.config.*', '**/test-utils/**', '**/mocks/**', '**/*.test.*'],
      // 门限按 references/test-pyramid.md 分层目标调；不设全局 100%
      thresholds: { lines: 80, branches: 70, functions: 80, statements: 80 },
    },
  },
});
TS
  echo "==> 写入 vitest.config.ts"
else
  echo "==> vitest.config 已存在，跳过"
fi

# test-utils/server.ts
if [[ ! -f src/test-utils/server.ts ]]; then
  cat > src/test-utils/server.ts <<'TS'
import { setupServer } from 'msw/node';
import { handlers } from '../mocks/handlers';

// 单一数据源：单测 + 集成 + 开发共用同一套 handlers
export const server = setupServer(...handlers);
TS
  echo "==> 写入 src/test-utils/server.ts"
fi

# test-utils/setup.ts
if [[ ! -f src/test-utils/setup.ts ]]; then
  cat > src/test-utils/setup.ts <<'TS'
import '@testing-library/jest-dom/vitest';
import { afterAll, afterEach, beforeAll } from 'vitest';
import { server } from './server';

// 全局接管 MSW 生命周期：漏 mock 的请求直接报错，每个用例后重置
beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
TS
  echo "==> 写入 src/test-utils/setup.ts"
fi

# mocks/handlers.ts 占位
if [[ ! -f src/mocks/handlers.ts ]]; then
  cat > src/mocks/handlers.ts <<'TS'
import { http, HttpResponse } from 'msw';

// MSW 单一数据源。fixture 对齐后端真实响应形态（如 { code: 0, data: {...} }）
export const handlers = [
  // http.get('/api/example', () => HttpResponse.json({ items: [] })),
];
TS
  echo "==> 写入 src/mocks/handlers.ts（占位）"
fi

# package.json scripts（用 node 改，避免覆盖已有）
if command -v node >/dev/null 2>&1 && [[ -f package.json ]]; then
  node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
    p.scripts = p.scripts || {};
    const add = { test: "vitest", "test:run": "vitest run", "test:coverage": "vitest run --coverage", "test:ui": "vitest --ui" };
    let changed = false;
    for (const [k, v] of Object.entries(add)) {
      if (!p.scripts[k]) { p.scripts[k] = v; changed = true; }
    }
    if (changed) fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
    console.log(changed ? "==> 已补 test scripts" : "==> test scripts 已存在，跳过");
  '
fi

echo
echo "✅ Vitest 底座搭建完成。下一步:"
echo "   1) 在 src/mocks/handlers.ts 补真实接口 mock"
echo "   2) 用 gen-unit-test.sh 按模板生成第一条用例"
echo "   3) 跑 $PM run test:run 验证"
