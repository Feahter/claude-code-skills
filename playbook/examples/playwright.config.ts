import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  // 测试文件位置
  testDir: './tests/e2e',

  // 并发跑用例（同进程内）
  fullyParallel: true,

  // CI 上禁止 .only —— 防止开发遗留
  forbidOnly: !!process.env.CI,

  // CI 失败重试 2 次（容忍第三方依赖抖动），本地必须 0（暴露 flaky）
  retries: process.env.CI ? 2 : 0,

  // CI 限制并发避免资源争抢；本地默认按 CPU 数
  workers: process.env.CI ? 2 : undefined,

  reporter: [
    ['list'],
    ['html', { open: 'never' }],
    // CI 多 shard 合并用：reporter: [['blob']]
  ],

  // 全局 setup：登录一次存 storageState 给所有用例复用
  globalSetup: require.resolve('./tests/global-setup.ts'),

  use: {
    // 测试环境基址，CI 可用 BASE_URL 环境变量覆盖
    baseURL: process.env.BASE_URL ?? 'http://localhost:3000',

    // 复用登录态
    storageState: 'tests/.auth/user.json',

    // trace：失败首次重试时记录（够排查、不爆磁盘）
    trace: 'on-first-retry',

    // 失败截图 + 录像
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',

    // 默认断言超时（5s 一般够；慢操作单独调）
    actionTimeout: 10_000,
    navigationTimeout: 30_000,
  },

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    // 视实际需要打开下面的 project：
    // { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    // { name: 'webkit',  use: { ...devices['Desktop Safari'] } },
    // { name: 'mobile-chrome', use: { ...devices['Pixel 5'] } },
  ],

  // dev server 自动启动
  webServer: {
    command: 'pnpm dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,  // 本地开发已起的 server 直接用，提速
    timeout: 120_000,
    stdout: 'ignore',
    stderr: 'pipe',
  },
});
