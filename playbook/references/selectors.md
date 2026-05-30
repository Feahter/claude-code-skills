# 选择器策略

## 优先级（强制）

| 等级 | API | 何时用 | 例 |
|---|---|---|---|
| 1 | `getByRole` | 有语义角色的元素（button/link/heading/textbox/tab/...） | `page.getByRole('button', { name: '提交' })` |
| 2 | `getByLabel` | 表单控件 | `page.getByLabel('邮箱')` |
| 3 | `getByPlaceholder` | 输入框无 label 时 | `page.getByPlaceholder('请输入邮箱')` |
| 4 | `getByText` | 静态文本（非交互元素） | `page.getByText('订单已提交')` |
| 5 | `getByTestId` | 上述都不适用、或文本会变 | `page.getByTestId('user-avatar')` |
| ❌ | CSS 类 / nth-child / xpath | **绝不用** | `.btn-primary` / `:nth-child(3)` |

**为什么这样排**：Role/Label/Text 跟着用户认知和 a11y 走，UI 重构（换组件库、改 className）不会挂；testId 是最后兜底。CSS 类是 UI 库的内部实现，UI 库一升级就挂。

## testId 命名规范

格式：`<page>-<module>-<element>`，全小写+连字符。

例：
- `login-form-submit`
- `cart-item-remove-btn`
- `settings-profile-avatar`

**不要写**：`btn1` / `test-1` / `MyButton`（驼峰）

源码里加 `data-testid` 用 ts-eslint 规则强制（`testing-library/consistent-data-testid`）；构建时按需剥离（`babel-plugin-jsx-remove-data-test-id` for prod）。

## UI 库特定坑

| 库 | 坑 | 解 |
|---|---|---|
| antd | Button 内文本被 `<span>` 包裹 | `getByRole('button', { name: /文本/ })` 用正则 |
| antd | Modal 渲染到 `body` 末尾 | 用 `page.getByRole('dialog')` 进入作用域 |
| MUI | className 含 hash（`MuiButton-root-xxxx`） | 永远别用 className，全走 Role |
| MUI | Select 实际渲染成 `<div>` 不是 `<select>` | 用 `getByRole('combobox')` + 键盘交互 |
| Element Plus | el-input 内嵌 `<input>` | `getByLabel` 通常能命中 |
| shadcn | 完全无样式 hash | Role/Label 体验最佳 |

## codegen 用法

dev server 跑起来后：
```bash
npx playwright codegen http://localhost:3000
```

Playwright 会启动浏览器并实时记录操作 → 生成代码。**生成出来的代码不要直接用**——它默认按 Role 抓，但有时候会退化到 CSS。复制片段后手动改成本文档的优先级。

## locator 链式用法（避免脆弱选择器）

```ts
// ❌ 脆
await page.locator('div > div:nth-child(2) .btn').click();

// ✅ 链式过滤
const card = page.getByRole('article').filter({ hasText: '订单 #123' });
await card.getByRole('button', { name: '取消' }).click();
```

`filter` 用法是写稳健测试的关键——按"用户怎么找到这个元素"的思路链式定位。

## 现有项目用 CSS selector 怎么办

按风险迁移：

1. 先跑 `validate-test.sh` 列出所有违规 selector
2. 高频用例先迁（按 git 历史看哪些 spec 改得多）
3. 给源码加 `data-testid`（testId 列表见 `gen-test.sh` 输出）
4. 一次迁一条用例，每迁完跑 `validate-test.sh` 确认没退化

不要"全量重写"——历史包袱太重时分批迁。

## 配合阅读

- `architecture.md`：为什么选择器要藏进业务动作（spec 描述业务、不描述 UI）
- `assertions.md`：选好元素后怎么断言（`getByRole` 配 web-first 断言才完整）
