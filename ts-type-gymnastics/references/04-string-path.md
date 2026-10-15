# 字符串与路径

## 目录

1. 模板字面量类型：构造与拼接
2. 模式匹配与 infer
3. 内置字符串操作与大小写转换
4. 路径类型：Paths、Leaves、Get / PathValue、数组路径
5. 把路径类型用到函数签名上

## 1. 构造与拼接

模板字面量类型在插槽里放联合时会做笛卡尔积。插槽里也可以放 `string`、`number`、`bigint` 这些宽类型，作为“任意字符串 / 数字串”的模式。

```ts
type Size = 'sm' | 'md' | 'lg';
type Side = 'top' | 'bottom';
type Margin = `m${Capitalize<Side>}-${Size}`;   // 2 × 3 = 6 个成员
type Px = `${number}px`;
type EventName<T extends string> = `on${Capitalize<T>}`;

const ok: Px = '12.5px';
// @ts-expect-error 不匹配 `${number}px`
const bad: Px = '12em';

type _t = [
  Expect<Equal<Margin, 'mTop-sm' | 'mTop-md' | 'mTop-lg' | 'mBottom-sm' | 'mBottom-md' | 'mBottom-lg'>>,
  Expect<Equal<EventName<'click' | 'focus'>, 'onClick' | 'onFocus'>>,
];
```

成员数是各插槽联合大小的乘积，十万成员就会报 TS2590（见 `03-recursion.md`）。需要表达“任意组合”时，与其枚举全部组合，不如用宽类型模式 `` `${string}-${string}` `` 加运行时校验。

## 2. 模式匹配与 infer

在 `extends` 右侧的模板字面量里放 `infer`，就能把字符串拆开。匹配规则：

- 两个 `infer` 紧挨着（`` `${infer A}${infer B}` ``）时，`A` 只匹配**一个字符**，`B` 拿走剩余部分。这是逐字符扫描的基础。
- `infer` 后面跟着字面量分隔符（`` `${infer A}.${infer B}` ``）时，`A` 匹配到**第一个**分隔符为止。
- `infer X extends number` 可以把数字串直接转成数字字面量（TS 4.8+）。

```ts
type Trim<S extends string> =
  S extends ` ${infer R}` | `\n${infer R}` | `\t${infer R}` ? Trim<R>
  : S extends `${infer L} ` | `${infer L}\n` | `${infer L}\t` ? Trim<L>
  : S;

type Split<S extends string, D extends string, Acc extends string[] = []> =
  S extends `${infer H}${D}${infer R}` ? Split<R, D, [...Acc, H]>
  : S extends '' ? Acc
  : [...Acc, S];

type ReplaceAll<S extends string, From extends string, To extends string, Acc extends string = ''> =
  From extends '' ? S
  : S extends `${infer L}${From}${infer R}` ? ReplaceAll<R, From, To, `${Acc}${L}${To}`>
  : `${Acc}${S}`;

type _t = [
  Expect<Equal<Trim<'  hi \n'>, 'hi'>>,
  Expect<Equal<Split<'a,b,c', ','>, ['a', 'b', 'c']>>,
  Expect<Equal<Split<'', ','>, []>>,
  Expect<Equal<ReplaceAll<'a-b-c', '-', '_'>, 'a_b_c'>>,
  Expect<Equal<ReplaceAll<'aaa', 'a', 'aa'>, 'aaaaaa'>>, // 累加器写法不会对替换结果重复匹配
];
```

`ReplaceAll` 把已处理部分放进累加器 `Acc`，不再对替换后的字符串重新匹配，所以 `From` 是 `To` 的子串时也不会死循环；同时它是尾递归。`From extends ''` 的判断是必要的，否则空模式会无限匹配。

### 路由参数提取

```ts
type RouteParams<P extends string> =
  P extends `${string}:${infer Param}/${infer Rest}`
    ? { [K in Param | keyof RouteParams<`/${Rest}`>]: string }
    : P extends `${string}:${infer Param}`
      ? { [K in Param]: string }
      : {};

function buildUrl<const P extends string>(pattern: P, params: RouteParams<P>): string {
  return pattern.replace(/:(\w+)/g, (_, k: string) => (params as Record<string, string>)[k] ?? '');
}

buildUrl('/users/:id/posts/:postId', { id: '1', postId: '2' });
// @ts-expect-error 缺少 postId
buildUrl('/users/:id/posts/:postId', { id: '1' });

type _t = Expect<Equal<RouteParams<'/a/:x/b/:y'>, { x: string; y: string }>>;
```

函数体里的 `as Record<string, string>` 是类型体操常见的“实现内部断言”：调用方签名精确，实现内部无法让编译器理解计算类型时，在实现里收敛一次断言是可以接受的，前提是有类型测试或单元测试守住行为。

## 3. 内置字符串操作与大小写转换

内置的 `Uppercase`、`Lowercase`、`Capitalize`、`Uncapitalize` 是编译器内建的，没有对应的类型定义可看。其他转换要自己写：

```ts
type CamelCase<S extends string> =
  S extends `${infer H}_${infer R}` ? `${Lowercase<H>}${Capitalize<CamelCase<R>>}` : Lowercase<S>;

type KebabCase<S extends string, Acc extends string = ''> =
  S extends `${infer C}${infer R}`
    ? KebabCase<R, `${Acc}${C extends Lowercase<C> ? C : `${Acc extends '' ? '' : '-'}${Lowercase<C>}`}`>
    : Acc;

type CamelKeys<T> = { [K in keyof T as K extends string ? CamelCase<K> : K]: T[K] };

type _t = [
  Expect<Equal<CamelCase<'user_first_name'>, 'userFirstName'>>,
  Expect<Equal<KebabCase<'backgroundColor'>, 'background-color'>>,
  Expect<Equal<KebabCase<'Foo'>, 'foo'>>,
  Expect<Equal<CamelKeys<{ created_at: Date; id: number }>, { createdAt: Date; id: number }>>,
];
```

`C extends Lowercase<C>` 用来判断字符是否已经是小写。数字和符号的大小写形式等于自身，会被当作“小写”保留原样。

## 4. 路径类型

路径类型把嵌套对象的访问路径表示为点分字符串，用于类型安全的 `get` / `set`、表单字段名、i18n 键、排序字段。四个组件分工如下：

| 类型 | 作用 | 示例结果 |
|---|---|---|
| `Paths<T>` | 所有路径，包括中间节点 | `'user' \| 'user.name' \| 'tags' \| 'tags.${number}'` |
| `Leaves<T>` | 只有叶子路径 | `'user.name' \| 'tags.${number}'` |
| `Get<T, P>` / `PathValue` | 沿路径取值类型 | `Get<T, 'user.name'>` 是 `string` |
| 深度参数 `D` | 防止自引用类型无限展开 | 默认 8 层 |

```ts
type Primitive = string | number | bigint | boolean | symbol | null | undefined;
type Leaf = Primitive | Date | RegExp | ((...args: any[]) => unknown);
type Dot<K extends string | number, P> = [P] extends [never] ? never : `${K}.${P & string}`;

/** 所有路径。数组段写成 `${number}`，元组段写成具体下标。 */
type Paths<T, D extends unknown[] = []> =
  D['length'] extends 8 ? never
  : T extends Leaf ? never
  : T extends readonly unknown[]
    ? number extends T['length']
      ? `${number}` | Dot<number, Paths<T[number], [...D, 0]>>
      : { [K in keyof T & `${number}`]: K | Dot<K, Paths<T[K], [...D, 0]>> }[keyof T & `${number}`]
    : { [K in keyof T & (string | number)]-?: `${K}` | Dot<K, Paths<NonNullable<T[K]>, [...D, 0]>> }[keyof T & (string | number)];

/** 只取叶子路径：子节点没有更深的路径时，自身就是叶子。 */
type Leaves<T, D extends unknown[] = []> =
  D['length'] extends 8 ? never
  : T extends Leaf ? never
  : T extends readonly unknown[]
    ? number extends T['length']
      ? LeafOrDeeper<number, T[number], D>
      : { [K in keyof T & `${number}`]: LeafOrDeeper<K, T[K], D> }[keyof T & `${number}`]
    : { [K in keyof T & (string | number)]-?: LeafOrDeeper<K, NonNullable<T[K]>, D> }[keyof T & (string | number)];
type LeafOrDeeper<K extends string | number, V, D extends unknown[]> =
  [Leaves<V, [...D, 0]>] extends [never] ? `${K}` : Dot<K, Leaves<V, [...D, 0]>>;

/** 沿点分路径取值类型。经过可选属性时结果带上 undefined，与可选链的语义一致。 */
type Get<T, P extends string> =
  P extends `${infer K}.${infer Rest}` ? Get<Prop<T, K>, Rest> : Prop<T, P>;
type Prop<T, K extends string> =
  T extends null | undefined ? undefined          // 对联合分配，传递 undefined
  : K extends keyof T ? T[K]
  : T extends readonly unknown[] ? (K extends `${number}` ? T[number] : never)
  : never;

type Model = {
  user: { name: string; address?: { city: string } };
  tags: string[];
  pair: [number, { ok: boolean }];
  createdAt: Date;
};

type _t = [
  Expect<Equal<Paths<Model>,
    | 'user' | 'user.name' | 'user.address' | 'user.address.city'
    | 'tags' | `tags.${number}`
    | 'pair' | 'pair.0' | 'pair.1' | 'pair.1.ok'
    | 'createdAt'>>,
  Expect<Equal<Leaves<Model>,
    'user.name' | 'user.address.city' | `tags.${number}` | 'pair.0' | 'pair.1.ok' | 'createdAt'>>,
  Expect<Equal<Get<Model, 'user.name'>, string>>,
  Expect<Equal<Get<Model, 'user.address.city'>, string | undefined>>,
  Expect<Equal<Get<Model, 'tags.3'>, string>>,
  Expect<Equal<Get<Model, 'pair.1.ok'>, boolean>>,
  Expect<Equal<Get<Model, 'nope'>, never>>,
];
```

设计取舍：

- **叶子的定义**：`Date`、`RegExp`、函数被当作叶子，不再展开。项目里还有其他不该展开的类（`Decimal`、`Temporal.Instant`、`Map`）就加进 `Leaf`。
- **空对象**：`Leaves` 会把值为 `{}` 的属性当作叶子，因为它下面没有路径。
- **数组下标**：数组段是 `` `${number}` ``，所以 `'tags.3'` 和 `'tags.0'` 都合法；元组段是具体下标，越界下标不合法。
- **`noUncheckedIndexedAccess`**：开启时，运行时访问数组越界会得到 `undefined`。如果希望 `Get` 也反映这一点，把数组分支改成 `T[number] | undefined`。
- **性能**：`Paths` 在大型类型（几百个字段、带自引用）上生成的联合可能上万，编辑器会变慢。超过这个规模时改用分段 API（见下一节末尾）。

## 5. 用到函数签名上

```ts
type Paths<T> = T extends object
  ? { [K in keyof T & string]: `${K}` | `${K}.${Paths<T[K]>}` }[keyof T & string]
  : never;
type Get<T, P extends string> = P extends `${infer K}.${infer R}`
  ? K extends keyof T ? Get<T[K], R> : never
  : P extends keyof T ? T[P] : never;

function get<T, const P extends Paths<T>>(obj: T, path: P): Get<T, P> {
  let cur: unknown = obj;
  for (const seg of path.split('.')) cur = (cur as Record<string, unknown> | undefined)?.[seg];
  return cur as Get<T, P>;
}

const data = { a: { b: { c: 42 } }, d: 'x' };
const v = get(data, 'a.b.c');     // number
// @ts-expect-error 路径不存在
get(data, 'a.x');

type _t = Expect<Equal<typeof v, number>>;
```

`P extends Paths<T>` 同时提供了路径的自动补全和非法路径的报错。实现内部的两个 `as` 是不可避免的，因为运行时逐段访问无法被编译器跟踪。

对于大型类型，可以把路径拆成多个参数，每个参数只依赖上一个，避免一次性生成全部路径：

```ts
function at<T, K1 extends keyof T>(o: T, k1: K1): T[K1];
function at<T, K1 extends keyof T, K2 extends keyof T[K1]>(o: T, k1: K1, k2: K2): T[K1][K2];
function at(o: unknown, ...keys: PropertyKey[]): unknown {
  return keys.reduce<unknown>((cur, k) => (cur as Record<PropertyKey, unknown>)[k], o);
}

const city = at({ user: { city: 'SH' } }, 'user', 'city');
type _t = Expect<Equal<typeof city, string>>;
```

分段写法每一步只计算一层的 `keyof`，开销与对象规模无关，代价是层数受重载数量限制。
