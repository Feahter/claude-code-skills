// 业务动作：订单。spec 调 createOrder / approvePayment，不关心 UI
// 关键：动作内部用最稳的 selector（Role/Label/TestId），不暴露给 spec

import { Page, expect } from '@playwright/test';

interface CreateOrderInput {
  product: string;
  qty: number;
  address?: string;
}

interface Order {
  id: string;
}

export async function createOrder(page: Page, input: CreateOrderInput): Promise<Order> {
  await page.goto('/products');
  await page.getByRole('link', { name: input.product }).click();

  await page.getByLabel('数量').fill(String(input.qty));
  await page.getByRole('button', { name: '加入购物车' }).click();

  await page.goto('/checkout');
  if (input.address) {
    await page.getByLabel('收货地址').fill(input.address);
  }
  await page.getByRole('button', { name: '提交订单' }).click();

  await expect(page).toHaveURL(/\/orders\/(?<id>\w+)/);
  const url = page.url();
  const match = url.match(/\/orders\/(\w+)/);
  if (!match) throw new Error(`未拿到订单 ID，当前 URL: ${url}`);
  return { id: match[1] };
}

export async function approvePayment(page: Page, orderId: string): Promise<void> {
  await page.goto(`/admin/orders/${orderId}`);
  await page.getByRole('button', { name: '审批支付' }).click();
  await page.getByRole('button', { name: '确认' }).click();
  await expect(page.getByText('已支付')).toBeVisible();
}

export async function requestRefund(page: Page, orderId: string): Promise<void> {
  await page.goto(`/orders/${orderId}`);
  await page.getByRole('button', { name: '申请退款' }).click();
  await page.getByLabel('退款原因').fill('测试退款');
  await page.getByRole('button', { name: '提交申请' }).click();
  await expect(page.getByText('退款审核中')).toBeVisible();
}
