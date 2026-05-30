# 测试架构：业务 DSL 分层 + 测试金字塔

普通团队写 `page.click('.submit')`，神级团队写 `await checkout.placeOrder(product)`。差别不在 Playwright 本身，在于**测试是描述 UI 还是描述业务**。

## 业务 DSL 四层架构

```
spec (用例)
 ↓        "admin 能审批退款单"
business actions
 ↓        loginAs / createOrder / approveRefund
page objects（仅复杂页面）
 ↓        CheckoutPage.fillAddress / submit
playwright api
          page.getByRole / fill / click
```

为什么要分层：UI 会变（className、DOM 结构、组件库），业务语义不变。把测试钉在业务语义上，UI 重构时测试基本不动。

### 推荐写法

```ts
test('admin 审批退款单', async ({ page }) => {
  await loginAs(page, 'admin');
  const order = await createOrder(page, { amount: 100 });
  await requestRefund(page, order.id);
  await approveRefund(page, order.id);
  await expect(page.getByText('已退款')).toBeVisible();
});
```

### 反模式

```ts
test('admin 审批退款单', async ({ page }) => {
  await page.goto('/login');
  await page.fill('#username', 'admin');
  await page.fill('#password', '123456');
  await page.click('.btn-login');
  // ...还有 30 行 UI 操作
});
```

业务动作放 `tests/actions/`（见 examples/actions/），page object 放 `tests/pages/`，spec 只调动作，不直接操作 DOM。

## 何时引入 page object

| 情况 | 选择 |
|---|---|
| 单页面 < 5 个交互 | 不要 POM，直接写或抽 action |
| 单页面 ≥ 10 个交互 / 多状态切换 | 抽 POM |
| 跨页面流程 | 用 actions 串起来，不要为流程造 POM |

POM 是"为了组织复杂页面"的工具，不是"为了显得专业"。简单页面套 POM 反而难读。

## 测试金字塔：E2E 该测什么

```
        E2E (10%)      只测核心赚钱路径 + 高风险链路
      Integration (20%)
    Component (大头)
  Unit (大头)
```

### E2E 应该测

- **用户赚钱路径**：注册 / 登录 / 下单 / 支付 / 退款
- **高风险链路**：权限边界 / 风控 / 结算 / 数据一致性
- **跨系统链路**：web → api → mq → db
- **核心写操作**：增删改的最终落库

### E2E 不应该测（让 unit / component 测）

- form 校验规则（手机号格式、密码强度）
- 工具函数（formatMoney / parseDate）
- React/Vue hooks 自身行为
- 边界 case（10000 字输入、空字符串）
- 单组件的视觉细节（按钮 hover 颜色）—— 用 visual-regression

判断标准：**这个 bug 用户能感知到吗？只有用户感知得到的才进 E2E。**

## E2E 黑名单（validate-test.sh 会警告）

测试名/描述含下面关键字，建议改 unit/component：
- `validation` / `校验` / `格式` —— 表单校验类
- `format` / `parse` / `util` —— 工具函数类
- `hover` / `style` / `color` —— 单组件视觉类
- `boundary case` / `edge case` —— 边界穷举类

## 阶段 2 规划时的金字塔判断

写 `test-plan.md` 前先过一遍：

1. 用户的目标是流程级（登录→下单→支付）→ E2E
2. 用户的目标是逻辑级（金额计算、表单校验）→ 推回让用户写 unit
3. 用户的目标是单组件级（弹窗动画、tooltip）→ 推回让用户写 component test
4. 拿不准：问"这个 bug 上线后用户报障会怎么描述？"——能描述出业务影响才是 E2E 该测的

## 业务 DSL 命名规范

动作以**业务动词**开头，参数用**业务对象**：

```ts
// ✅ 业务语义
loginAs(page, 'admin')
createOrder(page, { product, qty })
approvePayment(page, orderId)

// ❌ UI 语义
clickLoginBtn(page)
fillFormAndSubmit(page, formData)
clickButton(page, '审批')
```

action 内部用最稳的 selector（Role > Label > TestId），不暴露给上层 spec。

## 配合阅读

- `selectors.md`：action 内部该用哪种选择器（本文只说"用最稳的"，优先级规则在那里）
- `assertions.md`：spec 末尾的业务断言怎么写（web-first，抓用户能感知的结果）
