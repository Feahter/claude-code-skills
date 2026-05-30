// tests/fixtures/auth.ts
// 多角色 auth fixture 示范
// 配合 playwright.config.ts 的 use.storageState 使用
//
// 单角色项目可以省略 fixture，直接在 globalSetup 里登一次，
// config 设 use.storageState = 'tests/.auth/user.json'

import { test as base, Page, request } from '@playwright/test';
import * as fs from 'node:fs';
import * as path from 'node:path';

type Role = 'admin' | 'user' | 'guest';

interface AuthFixtures {
  authedPage: Page;
  adminPage: Page;
}

const STORAGE_DIR = 'tests/.auth';

async function ensureStorageState(role: Role, baseURL: string): Promise<string> {
  const file = path.join(STORAGE_DIR, `${role}.json`);
  if (fs.existsSync(file)) return file;

  fs.mkdirSync(STORAGE_DIR, { recursive: true });

  // 推荐：用 API 拿 token，跳过 UI 登录（快且稳）
  const ctx = await request.newContext({ baseURL });
  const resp = await ctx.post('/api/auth/login', {
    data: {
      email: process.env[`TEST_${role.toUpperCase()}_EMAIL`],
      password: process.env[`TEST_${role.toUpperCase()}_PASSWORD`],
    },
  });
  if (!resp.ok()) {
    throw new Error(`登录失败 (${role}): ${resp.status()}`);
  }

  // 接口登录后 ctx 已带 cookie，直接存 storageState
  // 如果业务需要把 token 写到 localStorage，改用浏览器 ctx 注入：
  //   const browser = await chromium.launch();
  //   const browserCtx = await browser.newContext();
  //   await browserCtx.addInitScript(t => localStorage.setItem('token', t), token);
  //   await browserCtx.storageState({ path: file });
  await ctx.storageState({ path: file });
  await ctx.dispose();
  return file;
}

export const test = base.extend<AuthFixtures>({
  authedPage: async ({ browser, baseURL }, use) => {
    const file = await ensureStorageState('user', baseURL!);
    const ctx = await browser.newContext({ storageState: file });
    const page = await ctx.newPage();
    await use(page);
    await ctx.close();
  },

  adminPage: async ({ browser, baseURL }, use) => {
    const file = await ensureStorageState('admin', baseURL!);
    const ctx = await browser.newContext({ storageState: file });
    const page = await ctx.newPage();
    await use(page);
    await ctx.close();
  },
});

export { expect } from '@playwright/test';

// 用例里用法：
//
// import { test, expect } from '../fixtures/auth';
//
// test('user 看不到 admin 入口', async ({ authedPage }) => {
//   await authedPage.goto('/dashboard');
//   await expect(authedPage.getByRole('link', { name: '管理后台' })).toBeHidden();
// });
//
// test('admin 能进管理后台', async ({ adminPage }) => {
//   await adminPage.goto('/admin');
//   await expect(adminPage.getByRole('heading', { name: '管理后台' })).toBeVisible();
// });
