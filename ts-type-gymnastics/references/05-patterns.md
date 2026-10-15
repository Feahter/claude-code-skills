# 实用模式与高阶技巧

## 目录

1. 工具类型扩展
2. 品牌类型 Branding
3. 可辨识联合（含关联联合问题）
4. 类型级函数与计算
5. 状态机
6. 类型级 Parser
7. 高阶类型模拟 HKT
8. 函数重载模拟

## 1. 工具类型扩展

动手写之前先确认内置类型和 `type-fest` 有没有现成的。内置的 `Partial`、`Required`、`Readonly`、`Pick`、`Omit`、`Record`、`Exclude`、`Extract`、`NonNullable`、`Parameters`、`ReturnType`、`ConstructorParameters`、`InstanceType`、`Awaited`、`NoInfer` 覆盖了大部分基础需求；`type-fest` 提供了 `SetOptional`、`Merge`、`Simplify`、`Paths`、`Get`、`CamelCasedPropertiesDeep` 等大量经过测试的工具类型。项目已经依赖 `type-fest` 时优先用它，没有依赖时，下面这些常用的可以直接写：

```ts
/** 展开交叉类型，让悬停提示显示最终形状。 */
type Prettify<T> = { [K in keyof T]: T[K] } & {};
/** 右侧覆盖左侧的同名属性（& 做不到，冲突属性会变成交叉）。 */
type Merge<A, B> = Prettify<Omit<A, keyof B> & B>;
/** 把指定键变成可选 / 必填。 */
type PartialBy<T, K extends keyof T> = Prettify<Omit<T, K> & Partial<Pick<T, K>>>;
type RequiredBy<T, K extends keyof T> = Prettify<Omit<T, K> & Required<Pick<T, K>>>;
/** 内置 Omit 的 K 不受约束，写错键名不会报错。这个版本会。 */
type StrictOmit<T, K extends keyof T> = Omit<T, K>;
type ValueOf<T> = T[keyof T];
/** 至少提供其中一个键。 */
type AtLeastOne<T> = { [K in keyof T]-?: Required<Pick<T, K>> & Partial<Omit<T, K>> }[keyof T];

type User = { id: number; name: string; email?: string };
type _t = [
  Expect<Equal<Merge<User, { id: string }>, { name: string; email?: string; id: string }>>,
  Expect<Equal<PartialBy<User, 'name'>, { id: number; email?: string; name?: string }>>,
  Expect<Equal<ValueOf<{ a: 1; b: 2 }>, 1 | 2>>,
];
// @ts-expect-error 'nmae' 不是 User 的键
type _bad = StrictOmit<User, 'nmae'>;

type Contact = AtLeastOne<{ email: string; phone: string }>;
const c: Contact = { phone: '1' };
// @ts-expect-error 一个都没给
const c2: Contact = {};
```

几个不建议写的工具类型：`UnionToTuple` / `LastOfUnion` 依赖联合成员的内部排序，排序在不同版本、不同文件顺序下可能变化，结果不可依赖；`DeepMerge` 一类深度合并在边界情况（数组、可选、联合）上很难写对，实际需要时用运行时库并显式声明结果类型。

## 2. 品牌类型 Branding

结构类型系统里，两个 `string` 别名可以互相赋值。品牌类型在类型层面给值打上标记，只能通过指定的构造函数获得，运行时零开销。

```ts
declare const brand: unique symbol;
type Brand<T, B extends string> = T & { readonly [brand]: B };

type UserId = Brand<string, 'UserId'>;
type OrderId = Brand<string, 'OrderId'>;
type Cents = Brand<number, 'Cents'>;

// 智能构造函数：校验在这里集中做一次，之后类型本身就代表“已校验”
function toUserId(raw: string): UserId {
  if (!/^u_[a-z0-9]+$/.test(raw)) throw new Error(`Invalid UserId: ${raw}`);
  return raw as UserId;
}
function toCents(n: number): Cents {
  if (!Number.isInteger(n)) throw new Error('Cents must be an integer');
  return n as Cents;
}

function getOrder(id: OrderId) { return id; }
const uid = toUserId('u_42');
// @ts-expect-error UserId 不能当 OrderId 用
getOrder(uid);
// @ts-expect-error 普通字符串也不行
getOrder('o_1');

const len: number = uid.length;     // 品牌类型仍可当作底层类型使用
const total: number = toCents(100) + toCents(50); // 运算结果退回 number，需要时再包装
```

要点：

- 用 `unique symbol` 做品牌键，而不是字符串属性 `__brand`。字符串键会出现在自动补全里，也可能和真实属性冲突。
- `as UserId` 只应出现在构造函数内部，这是唯一允许断言的地方。
- 断言函数形式 `asserts x is UserId` 适合“校验后原地收窄”的场景。
- 与 Zod 的 `.brand()` 结合时，schema 解析成功即得到品牌类型，见 `06-engineering.md`。

## 3. 可辨识联合

用一个字面量类型的判别字段（`type`、`kind`、`status`）区分联合成员，代替一堆互相依赖的可选字段。可选字段允许“data 和 error 同时存在”这类不可能状态，可辨识联合让每个状态的字段都确定。

```ts
type RemoteData<T, E = Error> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'failure'; error: E };

function render(r: RemoteData<string[]>): string {
  switch (r.status) {
    case 'idle': return '';
    case 'loading': return '...';
    case 'success': return r.data.join(',');   // r 已收窄
    case 'failure': return r.error.message;
    default: {
      const _exhaustive: never = r;
      return _exhaustive;
    }
  }
}

type Success = Extract<RemoteData<number>, { status: 'success' }>;
type _t = Expect<Equal<Success, { status: 'success'; data: number }>>;
```

### 关联联合问题

把事件分发给处理器表时，直接写 `handlers[e.type](e)` 会报错：编译器分别把 `handlers[e.type]` 和 `e` 看成两个独立的联合，无法知道它们是对应的。解决方法是让联合由一个映射表生成，并用泛型 `K` 把两边关联起来（TS 4.6+ 支持这种写法）：

```ts
type EventMap = {
  click: { x: number; y: number };
  key: { code: string };
};

// 由映射表生成可辨识联合
type AppEvent<K extends keyof EventMap = keyof EventMap> =
  { [P in K]: { type: P; payload: EventMap[P] } }[K];

type HandlerMap = { [K in keyof EventMap]: (payload: EventMap[K]) => void };

const handlers: HandlerMap = {
  click: (p) => { void (p.x + p.y); },
  key: (p) => { void p.code.length; },
};

function dispatch<K extends keyof EventMap>(e: AppEvent<K>) {
  handlers[e.type](e.payload);   // 通过泛型 K 关联，不需要断言
}

dispatch({ type: 'key', payload: { code: 'Enter' } });
// @ts-expect-error payload 与 type 不匹配
dispatch({ type: 'key', payload: { x: 1, y: 2 } });
```

这个模式的关键是映射表 `EventMap` 成为唯一事实来源：联合类型、处理器表、分发函数都从它派生。新增事件只需要改映射表，漏写处理器时 `handlers` 的赋值会报错。

## 4. 类型级函数与计算

类型级计算通常借助元组长度实现：构造长度为 N 的元组，用展开拼接做加法，用 `infer` 剥离做减法。它适合计算小的常量（数组长度约束、索引偏移、固定长度元组），不适合做真正的数值运算，受递归和元组规模上限约束（见 `03-recursion.md`）。

```ts
type BuildTuple<N extends number, Acc extends unknown[] = []> =
  Acc['length'] extends N ? Acc : BuildTuple<N, [...Acc, unknown]>;

type Add<A extends number, B extends number> = [...BuildTuple<A>, ...BuildTuple<B>]['length'] & number;
type Subtract<A extends number, B extends number> =
  BuildTuple<A> extends [...BuildTuple<B>, ...infer R] ? R['length'] : never;
type GreaterThan<A extends number, B extends number> =
  A extends B ? false : BuildTuple<A> extends [...BuildTuple<B>, ...unknown[]] ? true : false;

/** 固定长度元组，常用于向量、坐标、矩阵行。 */
type FixedArray<T, N extends number, Acc extends T[] = []> =
  Acc['length'] extends N ? Acc : FixedArray<T, N, [...Acc, T]>;

type _t = [
  Expect<Equal<Add<3, 4>, 7>>,
  Expect<Equal<Subtract<10, 3>, 7>>,
  Expect<Equal<Subtract<3, 10>, never>>,
  Expect<Equal<GreaterThan<5, 3>, true>>,
  Expect<Equal<GreaterThan<3, 3>, false>>,
  Expect<Equal<FixedArray<number, 3>, [number, number, number]>>,
];
```

`Add` 结尾的 `& number` 是为了让 `['length']` 的结果被识别为 `number` 的子类型，否则把结果再传给要求 `extends number` 的参数时会报错。`BuildTuple` 对负数、小数、`number` 本身都会无限递归直到报错，公开的工具类型应在入口处用 `` `${N}` extends `-${string}` | `${string}.${string}` `` 和 `number extends N` 把这些输入挡掉。

## 5. 状态机

用类型描述状态转移表，让“在某个状态下只能触发合法事件”成为编译期约束。

```ts
// 一份运行时转移表，同时作为类型的唯一来源
function defineMachine<const M extends { [S in keyof M]: Record<string, keyof M> }>(m: M): M {
  return m;
}

const machine = defineMachine({
  idle: { FETCH: 'loading' },
  loading: { RESOLVE: 'success', REJECT: 'failure' },
  success: { RESET: 'idle' },
  failure: { RETRY: 'loading', RESET: 'idle' },
});

type Machine = typeof machine;
type State = keyof Machine;
type EventOf<S extends State> = keyof Machine[S] & string;
type Next<S extends State, E extends EventOf<S>> = Machine[S][E];

function transition<S extends State, E extends EventOf<S>>(state: S, event: E): Next<S, E> {
  return machine[state][event];
}

const s1 = transition('idle', 'FETCH');        // "loading"
const s2 = transition(s1, 'REJECT');           // "failure"
// @ts-expect-error idle 状态没有 RESOLVE 事件
transition('idle', 'RESOLVE');

// @ts-expect-error 转移目标必须是已定义的状态
defineMachine({ idle: { GO: 'nowhere' } });

type _t = [
  Expect<Equal<typeof s1, 'loading'>>,
  Expect<Equal<typeof s2, 'failure'>>,
];
```

`defineMachine` 的约束 `{ [S in keyof M]: Record<string, keyof M> }` 引用了 `M` 自身，要求每个转移目标都是已有状态的键。`const` 类型参数保留了字面量，所以 `Next` 能算出具体的下一个状态。

另一种状态机是**类型状态**（typestate）：用类型参数记录对象处于哪个阶段，只在合适的阶段暴露方法。适合构建器和协议客户端：

```ts
type QueryState = { table: boolean; where: boolean };

class Query<S extends QueryState = { table: false; where: false }> {
  declare private readonly _state: S;   // 让 S 参与结构比较，见下文
  private parts: string[] = [];
  from(table: string): Query<{ table: true; where: S['where'] }> {
    this.parts.push(`FROM ${table}`);
    return this as unknown as Query<{ table: true; where: S['where'] }>;
  }
  where(cond: string): Query<{ table: S['table']; where: true }> {
    this.parts.push(`WHERE ${cond}`);
    return this as unknown as Query<{ table: S['table']; where: true }>;
  }
  build(this: Query<{ table: true; where: boolean }>): string {
    return `SELECT * ${this.parts.join(' ')}`;
  }
}

new Query().from('users').where('id = 1').build();
// @ts-expect-error 没调用 from 就 build
new Query().where('id = 1').build();
```

`build` 的 `this` 参数声明了调用前提。`_state` 这个只声明不赋值的字段是必需的：TypeScript 按结构比较类型，如果类型参数 `S` 不出现在任何成员的类型里，`Query<{ table: false; ... }>` 和 `Query<{ table: true; ... }>` 结构相同、可以互相赋值，阶段约束就失效了（去掉这一行，上面的 `@ts-expect-error` 会变成“未使用”）。`declare` 字段不生成运行时代码，在 `erasableSyntaxOnly` 下也允许。

类型状态变化时返回 `this` 需要经过 `unknown` 的双重断言，这是该模式少数可以接受双重断言的地方，因为运行时对象确实是同一个，只是阶段不同。

## 6. 类型级 Parser

类型级解析器把字符串字面量解析成结构化类型，用于让字符串 DSL（格式化模板、路由、SQL 片段、查询字符串）获得类型检查。写法统一是“逐段匹配 + 累加器 + 尾递归”。

### printf 风格的格式化参数

```ts
type FormatSpec = { s: string; d: number; b: boolean };

type ParseFormat<S extends string, Acc extends unknown[] = []> =
  S extends `${string}%${infer C}${infer Rest}`
    ? C extends keyof FormatSpec
      ? ParseFormat<Rest, [...Acc, FormatSpec[C]]>
      : C extends '%'
        ? ParseFormat<Rest, Acc>          // %% 是转义
        : ParseFormat<Rest, Acc>          // 未知占位符：忽略，也可以返回错误类型
    : Acc;

function format<const S extends string>(template: S, ...args: ParseFormat<S>): string {
  let i = 0;
  return template.replace(/%([sdb%])/g, (_, c: string) => (c === '%' ? '%' : String(args[i++])));
}

format('%s is %d years old', 'Ann', 30);
// @ts-expect-error 第二个参数应为 number
format('%s is %d years old', 'Ann', '30');

type _t = [
  Expect<Equal<ParseFormat<'%s:%d (%b) 100%%'>, [string, number, boolean]>>,
  Expect<Equal<ParseFormat<'no args'>, []>>,
];
```

### 查询字符串解析为对象

```ts
type ParseQuery<S extends string, Acc extends Record<string, string> = {}> =
  S extends `${infer Pair}&${infer Rest}`
    ? ParseQuery<Rest, Acc & ParsePair<Pair>>
    : Prettify<Acc & ParsePair<S>>;
type ParsePair<P extends string> =
  P extends `${infer K}=${infer V}` ? { [_ in K]: V } : P extends '' ? {} : { [_ in P]: '' };

type _t = Expect<Equal<ParseQuery<'page=2&sort=name&debug'>, { page: '2'; sort: 'name'; debug: '' }>>;
```

### 让错误可读

解析失败时返回 `never` 会让调用方看到“不能赋值给 never”，信息很差。可以返回一个带说明的字符串字面量或对象类型，让报错直接显示原因：

```ts
type ParseError<Msg extends string> = { __error: Msg };
type ParseBool<S extends string> =
  S extends 'true' ? true : S extends 'false' ? false : ParseError<`Expected boolean, got "${S}"`>;

type _t = Expect<Equal<ParseBool<'yes'>, ParseError<'Expected boolean, got "yes"'>>>;
```

类型级解析器的开销随输入长度线性增长，又受尾递归一千次的上限约束。输入是用户写在代码里的短字符串时很好用；输入可能很长（整段 SQL、模板文件）时，改用代码生成或运行时解析加 schema。

## 7. 高阶类型模拟 HKT

TypeScript 不支持把泛型类型本身当作参数传递（不能写 `F<_>` 再在别处应用 `F<number>`）。常见的模拟方法是用接口的 `this` 类型做延迟应用：

```ts
interface HKT {
  readonly arg: unknown;
  readonly out: unknown;
}
/** 把类型构造器 F 应用到 A 上。 */
type Apply<F extends HKT, A> = (F & { readonly arg: A })['out'];

interface ArrayF extends HKT { readonly out: Array<this['arg']> }
interface PromiseF extends HKT { readonly out: Promise<this['arg']> }
type Box<T> = { value: T };
// 不能写成 { value: this['arg'] }：对象字面量类型里的 this 指向字面量自身，会报 TS2526
interface BoxF extends HKT { readonly out: Box<this['arg']> }

interface Functor<F extends HKT> {
  map<A, B>(fa: Apply<F, A>, f: (a: A) => B): Apply<F, B>;
}

const arrayFunctor: Functor<ArrayF> = { map: (fa, f) => fa.map(f) };
const boxFunctor: Functor<BoxF> = { map: (fa, f) => ({ value: f(fa.value) }) };

const lens = arrayFunctor.map(['a', 'bb'], (s) => s.length);
type _t = [
  Expect<Equal<Apply<PromiseF, number>, Promise<number>>>,
  Expect<Equal<typeof lens, number[]>>,
];
```

同样的编码可以表达“类型级函数作为参数”，用于对元组或联合做通用的 map / filter：

```ts
interface Fn { readonly input: unknown; readonly output: unknown }
type Call<F extends Fn, X> = (F & { readonly input: X })['output'];

type MapTuple<T extends readonly unknown[], F extends Fn> = { [K in keyof T]: Call<F, T[K]> };

interface ToPromise extends Fn { readonly output: Promise<this['input']> }
interface Stringify extends Fn { readonly output: `${this['input'] & (string | number | boolean)}` }

type _t = [
  Expect<Equal<MapTuple<[1, 'a'], ToPromise>, [Promise<1>, Promise<'a'>]>>,
  Expect<Equal<MapTuple<[1, true], Stringify>, ['1', 'true']>>,
];
```

这是 Effect、fp-ts 等库内部使用的技术。在业务代码里，HKT 带来的抽象收益很少能抵消阅读成本；只有在写需要对多种容器通用的库时才值得用。

## 8. 函数重载模拟

### 三种写法的选择

| 写法 | 适合场景 | 代价 |
|---|---|---|
| 重载声明 | 参数个数或形状不同，分支少（2～4 个） | 实现签名需要兼容所有重载，内部要自己收窄 |
| 泛型 + 映射表查找 | 返回类型由某个参数的字面量决定，分支多 | 需要维护映射表 |
| 条件返回类型 | 返回类型是输入类型的函数 | 实现内部几乎必然需要断言 |

```ts
// 1. 重载声明
function parse(input: string): object;
function parse(input: string, reviver: (k: string, v: unknown) => unknown): unknown;
function parse(input: string, reviver?: (k: string, v: unknown) => unknown): unknown {
  return JSON.parse(input, reviver);
}

// 2. 泛型 + 映射表查找：分支多时最清楚，也是 DOM 的 createElement 采用的方式
type ShapeMap = { circle: { r: number }; rect: { w: number; h: number } };
function create<K extends keyof ShapeMap>(kind: K, props: ShapeMap[K]): { kind: K } & ShapeMap[K] {
  return { kind, ...props };
}
const circle = create('circle', { r: 1 });
// @ts-expect-error circle 需要 r
create('circle', { w: 1, h: 1 });

// 3. 条件返回类型
function wrap<T extends string | number>(x: T): T extends string ? string[] : number[] {
  return [x] as T extends string ? string[] : number[];
}
const w = wrap('a');

type _t = [
  Expect<Equal<typeof circle, { kind: 'circle' } & { r: number }>>,
  Expect<Equal<typeof w, string[]>>,
];
```

### 从映射表生成重载

需要真正的重载签名（例如为了让编辑器逐个列出签名）又不想手写时，可以把每个分支的函数类型交叉起来。函数类型的交叉在调用时表现为重载：

```ts
type UnionToIntersection<U> =
  (U extends unknown ? (x: U) => void : never) extends (x: infer I) => void ? I : never;

type ShapeMap = { circle: { r: number }; rect: { w: number; h: number } };
type CreateOverloads = UnionToIntersection<
  { [K in keyof ShapeMap]: (kind: K, props: ShapeMap[K]) => ShapeMap[K] & { kind: K } }[keyof ShapeMap]
>;

declare const createShape: CreateOverloads;
const rect = createShape('rect', { w: 1, h: 2 });
type _t = Expect<Equal<typeof rect, { w: number; h: number } & { kind: 'rect' }>>;
```

### 重载的陷阱

对重载函数使用 `Parameters`、`ReturnType` 或任何 `infer`，只会取到**最后一个**重载签名。需要所有签名时，按签名数量逐层匹配：

```ts
declare function fn(x: string): string;
declare function fn(x: number): number;

type Last = ReturnType<typeof fn>;               // 只得到 number

type Overloads2<F> = F extends { (...a: infer A1): infer R1; (...a: infer A2): infer R2 }
  ? [(...a: A1) => R1, (...a: A2) => R2]
  : never;
type All = Overloads2<typeof fn>;

type _t = [
  Expect<Equal<Last, number>>,
  Expect<Equal<All, [(x: string) => string, (x: number) => number]>>,
];
```

因为这个陷阱，给第三方重载函数写包装器时，最好直接声明包装器的签名，而不是从原函数推导。
