#!/usr/bin/env bash
# scaffold.sh —— 按 framework 一键搭建 Playwright（装包 + 写 config + 建目录 + globalSetup）
# 用法：scaffold.sh [--help] [--cwd <path>] [--framework <name>] [--pm <pnpm|yarn|npm|bun>]

set -euo pipefail

usage() {
  cat <<'EOF'
scaffold.sh —— 在当前目录搭建 Playwright E2E 测试基础设施

用法:
  scaffold.sh [--cwd <path>] [--framework <name>] [--pm <manager>]
  scaffold.sh --help

行为:
  1) 用对应 packageManager 装 @playwright/test
  2) 装 chromium 浏览器（--with-deps）
  3) 写入 playwright.config.ts（基于 framework 选模板）
  4) 创建 tests/e2e/ tests/fixtures/ tests/mocks/ 目录
  5) 创建 tests/global-setup.ts 和 tests/.gitignore

如果未指定 --framework / --pm，会自动调 detect-project.sh 探测。
不会覆盖已存在的 playwright.config.* 文件。
EOF
}

CWD="$(pwd)"
FRAMEWORK=""
PM=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --cwd) CWD="$2"; shift 2 ;;
    --framework) FRAMEWORK="$2"; shift 2 ;;
    --pm) PM="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

cd "$CWD"

if [[ -z "$FRAMEWORK" || -z "$PM" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "需要 jq 来探测项目，请安装或显式指定 --framework --pm" >&2; exit 2
  fi
  PROJ_JSON=$(bash "$SCRIPT_DIR/detect-project.sh")
  [[ -z "$FRAMEWORK" ]] && FRAMEWORK=$(echo "$PROJ_JSON" | jq -r .framework)
  [[ -z "$PM" ]] && PM=$(echo "$PROJ_JSON" | jq -r .packageManager)
fi

case "$PM" in
  pnpm) INSTALL="pnpm add -D"; EXEC="pnpm exec" ;;
  yarn) INSTALL="yarn add -D"; EXEC="yarn" ;;
  bun) INSTALL="bun add -d"; EXEC="bunx" ;;
  npm|*) INSTALL="npm i -D"; EXEC="npx" ;;
esac

# 端口推测
case "$FRAMEWORK" in
  vite|sveltekit) PORT=5173 ;;
  astro) PORT=4321 ;;
  *) PORT=3000 ;;
esac

# CRA 需要禁用自动开浏览器
DEV_CMD="$PM run dev"
[[ "$FRAMEWORK" == "cra" ]] && DEV_CMD="BROWSER=none $PM start"

echo "==> 装包"
$INSTALL @playwright/test

echo "==> 装 chromium"
$EXEC playwright install --with-deps chromium

echo "==> 建目录"
mkdir -p tests/e2e tests/fixtures tests/mocks tests/.auth

# .gitignore
if [[ ! -f tests/.gitignore ]]; then
  cat > tests/.gitignore <<'GIT'
.auth/
GIT
fi

# 项目根 .gitignore 追加 playwright 产物
if [[ -f .gitignore ]] && ! grep -q "playwright-report" .gitignore; then
  cat >> .gitignore <<'GIT'

# Playwright
playwright-report/
test-results/
GIT
fi

# config
if [[ ! -f playwright.config.ts && ! -f playwright.config.js ]]; then
  cat > playwright.config.ts <<TS
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: [['list'], ['html', { open: 'never' }]],
  globalSetup: require.resolve('./tests/global-setup.ts'),
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:${PORT}',
    storageState: 'tests/.auth/user.json',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: {
    command: '${DEV_CMD}',
    url: 'http://localhost:${PORT}',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
TS
  echo "==> 写入 playwright.config.ts"
else
  echo "==> playwright.config 已存在，跳过"
fi

# global-setup
if [[ ! -f tests/global-setup.ts ]]; then
  cat > tests/global-setup.ts <<'TS'
import { chromium, FullConfig } from '@playwright/test';

// 全局只跑一次：登录后存 storageState
// 把 doLogin 替换成你的项目实际登录流程，或调 API 拿 token 注入 cookie。
async function globalSetup(config: FullConfig) {
  const baseURL = config.projects[0]?.use.baseURL ?? 'http://localhost:3000';
  const browser = await chromium.launch();
  const ctx = await browser.newContext();
  const page = await ctx.newPage();

  // TODO: 替换为真实登录流程
  // await page.goto(`${baseURL}/login`);
  // await page.getByLabel('邮箱').fill(process.env.TEST_USER_EMAIL!);
  // await page.getByLabel('密码').fill(process.env.TEST_USER_PASSWORD!);
  // await page.getByRole('button', { name: '登录' }).click();
  // await page.waitForURL(`${baseURL}/`);

  await ctx.storageState({ path: 'tests/.auth/user.json' });
  await browser.close();
}

export default globalSetup;
TS
  echo "==> 写入 tests/global-setup.ts（含 TODO，替换登录流程）"
fi

# 占位 spec
if [[ ! -f tests/e2e/smoke.spec.ts ]]; then
  cat > tests/e2e/smoke.spec.ts <<'TS'
import { test, expect } from '@playwright/test';

test('首页能加载', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/.+/);
});
TS
  echo "==> 写入 tests/e2e/smoke.spec.ts"
fi

echo
echo "✅ 搭建完成。下一步:"
echo "   1) 编辑 tests/global-setup.ts 替换登录流程"
echo "   2) 跑 $EXEC playwright test"
echo "   3) 用 $EXEC playwright codegen http://localhost:$PORT 抓选择器"
