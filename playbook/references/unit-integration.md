# 单元 & 集成测试：通用写法

分层判断见 `test-pyramid.md`。本文讲落到单元/集成层后**具体怎么写**。工具默认 Vitest + Testing Library + MSW（Jest 同理，API 名换一下）。

## 一、单元测试：测纯逻辑

### 测什么、不测什么

**必测**（覆盖率冲 95%+）：`utils/` `services/` `validators/` 各类计算/格式化/校验函数——无副作用、输入确定、输出确定。

**少测**：UI 组件。别断言 `className`，只验行为：

```ts
expect(button).toBeEnabled();   // ✅ 行为
expect(button).toBeDisabled();
expect(button.className).toBe('btn-primary');  // ❌ 价值极低，重构即挂
```

**核心原则：测行为不测实现。** 不测内部 state、不测私有方法、不测 hook 内部细节。这样 Vue→React、Redux→Zustand、Class→Hooks 重构后，测试仍然通过。

### 参数化：表格即需求文档

不要用 `forEach` 拼测试，用框架原生参数化：

```ts
// ❌ 烂写法
[1, 2, 3].forEach(n => { it(`handle ${n}`, () => { /* ... */ }); });

// ✅ test.each：一旦失败，表格本身就是需求文档
it.each([
  { input: 100, rate: 0.8, expected: 80,  desc: '正常折扣' },
  { input: 0,   rate: 0.8, expected: 0,   desc: '零值' },
  { input: -5,  rate: 0.8, expected: -4,  desc: '负数' },
  { input: NaN, rate: 0.8, expected: 0,   desc: '非法输入兜底' },  // 异常优先
])('calcPrice($desc): $input × $rate → $expected', ({ input, rate, expected }) => {
  expect(calcPrice(input, rate)).toBe(expected);
});
```

浮点运算用 `toBeCloseTo` 而非 `toBe`：

```ts
expect(calcTax(99.99, 0.1)).toBeCloseTo(10.0, 2);
```

含 try-catch / 降级兜底的函数，要构造能触发异常的输入（非法格式、越界、null），验证**返回兜底值而非抛出**。

### 测 Hooks：renderHook + act

```ts
import { renderHook, act } from '@testing-library/react';

it('increment 增加计数', () => {
  const { result } = renderHook(() => useCounter(0));
  act(() => { result.current.increment(); });   // 状态更新必须包在 act 里
  expect(result.current.count).toBe(1);          // 断状态变化，不断 DOM
});
```

漏 `act` 会导致状态更新未反映 + React 警告。

## 二、Mock 三刀流：mock 边界，不 mock 一切

新人最容易写成 `jest.mock()` 满天飞，结果"测试通过、线上挂了"——因为测的是 mock。三条铁律：

| 场景 | 策略 | 反例 |
|---|---|---|
| 外部 HTTP 请求 | 用 MSW 在 HTTP 边界拦截，或 mock 你的 `apiClient` | 直接 `jest.mock('axios')`——脆，且模拟不了真实状态码/延迟 |
| 浏览器 API | `vi.stubGlobal('xxx', ...)` 显式声明 | 全局 `window.location = {}` 改坏全局 |
| 子组件 / 内部模块 | **绝不 mock** | `jest.mock('./Child')` 会隐藏真实集成问题 |

**心法：Mock 的目的是隔离不稳定边界，不是隔离复杂度。** 当你 mock 一个内部模块，你测的是自己的假设，不是代码。

## 三、确定性三角

集成测试腐烂的根因常是不确定性。一个测试必须同时满足：

- **确定输入**：用工厂模式生成（见下），不用线上随机数据
- **确定环境**：jsdom / happy-dom，不碰真实浏览器、真实后端
- **确定输出**：断言**具体的状态变化 / 用户可感知结果**，而非 DOM 结构

一旦出现 `await sleep(100)` 或 `if (Math.random() > 0.5)`，这个测试就死了。异步等待用 `findBy*` / `waitFor`，时间用 `vi.useFakeTimers()`（见 `flaky.md`）。

## 四、集成测试：测模块接缝

集成测试的核心是验证**模块之间的契约**（状态层 ↔ 视图层 ↔ 服务层的交界"接缝"），不是验证用户故事（那是 E2E）。

### RTL：像用户一样操作

```ts
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

it('提交表单后显示成功提示', async () => {
  const user = userEvent.setup();
  render(<OrderForm />);

  await user.type(screen.getByLabelText('数量'), '2');
  await user.click(screen.getByRole('button', { name: /提交/ }));

  // findBy* 智能等待，超时自动报错；绝不用 querySelector / 固定 setTimeout
  expect(await screen.findByText('提交成功')).toBeInTheDocument();
});
```

- 用 `userEvent` 不用 `fireEvent`——后者不触发 hover/focus 等真实交互。
- 用 `getByRole` / `findByText` 不用 `container.querySelector('.xxx')`。
- 多个相似元素用 `within(scope)` 作用域查询。
- **一个用例覆盖一个完整用户故事**（添加→展示→完成→过滤），别拆成孤立的"添加测试""完成测试"——孤立用例会漏掉状态污染。

### renderWithProviders：统一渲染入口

集成测试的组件通常需要 状态 store / 数据查询 client / i18n provider 包裹。封装一个项目专属的 `renderWithProviders`，**具体 Provider 组合按项目技术栈替换**（状态管理库、数据请求库、国际化库各取项目所用）：

```tsx
// test-utils/renderWithProviders.tsx —— 形态通用，内部 Provider 可换
function renderWithProviders(ui, { queryClient, initialState, locale = 'zh', ...opts } = {}) {
  const client = queryClient ?? new QueryClient({
    defaultOptions: { queries: { retry: false } },  // 测试里关掉 retry
  });
  return render(
    <QueryProvider client={client}>
      <StoreProvider initialState={initialState}>
        <I18nProvider locale={locale}>{ui}</I18nProvider>
      </StoreProvider>
    </QueryProvider>,
    opts,
  );
}
```

断言用户可感知结果，**不断言 Query 内部状态 / store 内部值**——那是单元层该做的。

### MSW：服务契约的活文档

网络层走 MSW 在 HTTP 边界拦截，不 mock service/hook 内部。完整 setupServer 配方见 `mocking.md`。要点：

- `handlers` 单一数据源，单测 + 集成 + 开发 + E2E 共用，避免三处维护三份假数据。
- fixture **对齐后端真实响应形态**（常见 `{ code: 0, data: {...} }` 这种包裹层；平铺就取不到值，是最常见的坑）。
- 异常用 `server.use()` 动态覆盖：`server.use(http.get('/api/x', () => HttpResponse.error()))`。

## 五、工厂造数据 vs 固定夹具

固定测试数据是集成测试腐烂的主因。用工厂 + faker 动态生成，按维度精确控制：

```ts
const userFactory = Factory.define<User>(({ sequence, params }) => ({
  id: params.id ?? `user-${sequence}`,
  name: faker.person.fullName(),
  role: params.role ?? 'user',
  orders: params.orders ?? orderFactory.buildList(2),  // 关联数据自动级联
}));

const admin = userFactory.build({ role: 'admin', orders: [] });  // 只控你关心的维度
```

集成测试的数据准备代码量常超过测试本身，工厂模式是唯一可持续方案。

## 六、快照测试的纪律

快照只有一个合法用途：**防 UI 意外漂移**。规则：

- 必须配合**显式断言**，不能只有 `toMatchSnapshot()`。
- 快照文件进 Git，PR 里人工 review。
- 超过 50 行的快照直接拒绝，拆成更小的断言单元。

不要用快照"测正确性"——它只能告诉你"变了"，不能告诉你"对不对"。

## 七、TDD 与调试（轻量）

- **红-绿-重构**：先写失败的测试（确认它真的会失败，防假阳性）→ 写最少代码转绿 → 重构保持绿。
- 调试集成测试失败：先 `screen.debug()` 打印当前 DOM 树，再看是不是该用 `findBy*` 而非 `getBy*`。

## 配合阅读

- `test-pyramid.md`：先判断该不该落到这一层
- `mocking.md`：MSW 完整配置 + 各种 mock 场景
- `flaky.md`：单测/集成层 fake timers 与异步稳定
- `anti-rot.md` / `source-pushback.md`：防腐与反推源码
