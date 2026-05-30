// 同一用例两种写法对比 —— Fixture vs POM
// 结论：默认用 Fixture，复杂页面才上 POM。详见 references/fixtures.md

// =============================================================
// 写法 A：Fixture（推荐，简洁）
// =============================================================

import { test as baseTest, expect } from '@playwright/test';

const test = baseTest.extend<{ checkoutAddress: string }>({
  checkoutAddress: async ({}, use) => {
    await use('上海市浦东新区世纪大道 100 号');
  },
});

test('Fixture 写法：提交订单', async ({ page, checkoutAddress }) => {
  await page.goto('/checkout');
  await page.getByLabel('收货地址').fill(checkoutAddress);
  await page.getByRole('button', { name: '提交订单' }).click();
  await expect(page).toHaveURL(/\/orders\/\d+/);
  await expect(page.getByText('订单创建成功')).toBeVisible();
});

// =============================================================
// 写法 B：POM（复杂页面才推荐）
// =============================================================

import { Page } from '@playwright/test';

class CheckoutPage {
  constructor(public readonly page: Page) {}

  readonly addressInput = this.page.getByLabel('收货地址');
  readonly couponInput = this.page.getByLabel('优惠券');
  readonly applyCouponBtn = this.page.getByRole('button', { name: '使用' });
  readonly submitBtn = this.page.getByRole('button', { name: '提交订单' });
  readonly totalAmount = this.page.getByTestId('checkout-total-amount');

  async goto() {
    await this.page.goto('/checkout');
  }

  async fillAddress(address: string) {
    await this.addressInput.fill(address);
  }

  async applyCoupon(code: string) {
    await this.couponInput.fill(code);
    await this.applyCouponBtn.click();
    // POM 方法可以包含等待，但不要 sleep
    await expect(this.page.getByText(/优惠券已使用|不可用/)).toBeVisible();
  }

  async submit() {
    await this.submitBtn.click();
    await expect(this.page).toHaveURL(/\/orders\/\d+/);
  }
}

test('POM 写法：复杂下单流程', async ({ page }) => {
  const checkout = new CheckoutPage(page);
  await checkout.goto();
  await checkout.fillAddress('上海市浦东新区世纪大道 100 号');
  await checkout.applyCoupon('SAVE20');
  await expect(checkout.totalAmount).toContainText('80'); // 假设原价 100
  await checkout.submit();
});

// =============================================================
// 何时用哪个？
// =============================================================
// - 页面交互少（< 5 个元素）→ Fixture/直接写
// - 页面交互复杂（> 10 个元素，或多状态切换）→ POM
// - 全项目混用，不要纠结一致性。简单页用简单写法，复杂页用 POM。
