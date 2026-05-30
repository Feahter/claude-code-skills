// 业务动作：认证。spec 只调 loginAs(page, role)，不关心 UI 细节
// 配合 examples/auth.fixture.ts 一起用，二选一：
//   - fixture：自动注入 storageState（推荐，速度快）
//   - action：用例显式 loginAs（复杂多步登录或测登录流程本身用）

import { Page, expect } from '@playwright/test';

type Role = 'admin' | 'user' | 'guest';

const credentials: Record<Role, { email: string; password: string }> = {
  admin: {
    email: process.env.TEST_ADMIN_EMAIL ?? 'admin@example.com',
    password: process.env.TEST_ADMIN_PASSWORD ?? 'admin123',
  },
  user: {
    email: process.env.TEST_USER_EMAIL ?? 'user@example.com',
    password: process.env.TEST_USER_PASSWORD ?? 'user123',
  },
  guest: { email: '', password: '' },
};

export async function loginAs(page: Page, role: Role): Promise<void> {
  if (role === 'guest') {
    await page.context().clearCookies();
    return;
  }

  const { email, password } = credentials[role];

  await page.goto('/login');
  await page.getByLabel('邮箱').fill(email);
  await page.getByLabel('密码').fill(password);
  await page.getByRole('button', { name: '登录' }).click();

  // 业务断言：登录成功的用户可见标志
  await expect(page.getByRole('button', { name: /我的账号|个人中心/ })).toBeVisible();
}

export async function logout(page: Page): Promise<void> {
  await page.getByRole('button', { name: /我的账号|个人中心/ }).click();
  await page.getByRole('menuitem', { name: '退出' }).click();
  await expect(page.getByRole('button', { name: '登录' })).toBeVisible();
}
