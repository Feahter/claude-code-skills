# 搭建配方：按框架对号入座

每个配方包括：装包命令、`playwright.config.ts` 关键字段、`webServer` 配置、目录约定。

## 通用骨架

```bash
# 安装（先看 packageManager）
pnpm add -D @playwright/test
pnpm exec playwright install --with-deps chromium  # 默认只装 chromium 提速
```

`playwright.config.ts` 通用字段（见 `examples/playwright.config.ts` 完整版）：

```ts
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.BASE_URL ?? 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: { /* 见各框架 */ },
});
```

## Next.js

```ts
webServer: {
  command: 'pnpm dev',
  url: 'http://localhost:3000',
  reuseExistingServer: !process.env.CI,
  timeout: 120_000,
},
```
- `app/` 目录用 RSC，注意首次访问可能慢，`timeout` 留够
- 测试 API Route：用 `request` fixture 直接打 endpoint

## Vite (React/Vue)

```ts
webServer: {
  command: 'pnpm dev',
  url: 'http://localhost:5173',
  reuseExistingServer: !process.env.CI,
},
```
- HMR 不影响 e2e，但 `reuseExistingServer` 本地推荐 true，提速 30s+

## Nuxt

```ts
webServer: {
  command: 'pnpm dev',
  url: 'http://localhost:3000',
  reuseExistingServer: !process.env.CI,
  timeout: 120_000,
},
```
- 默认端口 3000，首次冷启动慢，timeout 给足

## Remix

```ts
webServer: {
  command: 'pnpm dev',
  url: 'http://localhost:3000',
  reuseExistingServer: !process.env.CI,
},
```

## CRA

```ts
webServer: {
  command: 'BROWSER=none pnpm start',  // 关掉自动开浏览器
  url: 'http://localhost:3000',
  reuseExistingServer: !process.env.CI,
  timeout: 120_000,
},
```

## Astro

```ts
webServer: {
  command: 'pnpm dev',
  url: 'http://localhost:4321',
},
```

## 目录约定（各框架通用）

```
tests/
├── e2e/                # 测试文件 *.spec.ts
│   ├── auth/
│   ├── checkout/
│   └── settings/
├── fixtures/           # auto fixture（auth、testData 等）
├── mocks/              # API mock 数据
└── utils/              # 通用 helper
```

`tests/` 与 `src/` 同级，**不要**放进 `src/`——会被打包工具误扫。

## storageState 复用（强烈推荐）

```ts
// playwright.config.ts
export default defineConfig({
  globalSetup: require.resolve('./tests/global-setup.ts'),
  use: { storageState: 'tests/.auth/user.json' },
});
```

`global-setup.ts` 只跑一次登录，存 cookie + localStorage 到 `.auth/user.json`，后续 100 条用例直接复用，省 30-60s/次。

加 `.gitignore`：
```
tests/.auth/
test-results/
playwright-report/
```
