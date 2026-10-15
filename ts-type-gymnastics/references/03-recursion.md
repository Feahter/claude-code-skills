# 递归与控制

类型系统里没有循环，迭代全部靠递归。写递归类型要同时想清楚三件事：每一步怎么缩小问题、什么时候停、会不会撞到编译器的上限。

## 目录

1. 递归类型别名
2. 递归终止条件
3. 深度限制与规模上限（含 TS 7.0 实测数据）
4. 尾递归优化
5. 深度计数器

## 1. 递归类型别名

类型别名可以在对象属性、数组元素、元组元素位置引用自身，这类递归是**惰性**的，只有被访问时才展开，所以不受深度限制：

```ts
type Json = string | number | boolean | null | Json[] | { [key: string]: Json };
type Tree<T> = { value: T; children: Tree<T>[] };

const j: Json = { a: [1, 'x', { b: null }] };
```

在条件类型的分支里引用自身则是**立即**展开的，这是类型体操里大多数递归的形态，受深度限制约束。

`DeepReadonly` 是典型例子。借助同态映射对数组、元组和原始类型的特殊处理（见 `02-core-mechanisms.md`），一行映射就能覆盖对象、数组、元组；只需要单独排除函数和不该展开的内置对象：

```ts
type Builtin = Date | RegExp | ((...args: any[]) => unknown);

type DeepReadonly<T> = T extends Builtin
  ? T
  : T extends Map<infer K, infer V>
    ? ReadonlyMap<DeepReadonly<K>, DeepReadonly<V>>
    : T extends Set<infer M>
      ? ReadonlySet<DeepReadonly<M>>
      : { readonly [K in keyof T]: DeepReadonly<T[K]> };

type Cfg = { db: { hosts: string[]; port: number }; createdAt: Date; onError: (e: Error) => void };
type R = DeepReadonly<Cfg>;

type _t = [
  Expect<Equal<R['db']['hosts'], readonly string[]>>,
  Expect<Equal<R['createdAt'], Date>>,                // 没有被展开成一堆只读方法
  Expect<Equal<R['onError'], (e: Error) => void>>,
  Expect<Equal<DeepReadonly<string>, string>>,         // 原始类型原样返回
  Expect<Equal<DeepReadonly<[1, { a: 2 }]>, readonly [1, { readonly a: 2 }]>>,
  Expect<Equal<DeepReadonly<{ m: Map<string, { a: 1 }> }>['m'], ReadonlyMap<string, { readonly a: 1 }>>>,
];

// 结构类型陷阱：如果把 Error 列进 Builtin，任何带 name 和 message 字段的普通对象都会被当成叶子跳过
type Profile = DeepReadonly<{ name: string; message: string; tags: string[] }>;
type _t2 = Expect<Equal<Profile['tags'], readonly string[]>>;
```

叶子判断用的是可赋值性，不是名义类型，所以列进 `Builtin` 的类型越“宽”，误伤越多：

- **不要把 `Error` 列为叶子。** `Error` 只要求 `name` 和 `message` 两个字符串属性，`{ name: string; message: string; ... }` 这样的业务对象会被整个跳过。`Date`、`RegExp` 的成员多且特殊，误伤风险低。
- **`Map`、`Set` 的判断要放在叶子判断之前。** 方法参数是双变的，`Set<T>` 在结构上可以赋给 `WeakSet<object>`；叶子列表里如果有 `WeakSet` / `WeakMap`，排在前面就会把 `Set` / `Map` 吞掉。
- 加一个叶子类型后，用一个结构相近的普通对象类型做反例测试，确认它没有被误判。

不排除 `Date` 时，`Date` 会被映射成包含 `getTime`、`toISOString` 等只读属性的普通对象，不再能赋值给 `Date`。`DeepPartial`、`DeepRequired`、`DeepMutable` 都按这个骨架改修饰符即可。

## 2. 递归终止条件

每个递归类型都要回答“空输入返回什么”。常见的终止信号：

| 输入种类 | 终止条件 | 失配时的回退 |
|---|---|---|
| 元组 | `T extends []`，或 `T extends [infer H, ...infer R]` 失配 | 返回累加器或 `[]` |
| 字符串 | `S extends ''`，或模板匹配 `` `${infer C}${infer R}` `` 失配 | 返回累加器或 `''` |
| 数组（长度不定） | 无法逐个迭代，只能处理元素类型 `T[number]` | 先用 `number extends T['length']` 分流 |
| 对象 | 到达原始类型或排除列表中的叶子 | 原样返回 |
| 计数 | 计数元组的 `length` 达到目标 | 返回结果 |

另外两种输入会让递归跑飞或产生错误结果，需要在入口处单独拦截：

- **`any`**：`any` 会同时进入条件类型的两个分支，递归时每一层都分裂，结果是无意义的大联合，甚至触发深度错误。入口处用 `IsAny` 拦截。
- **`never`**：作为裸类型参数时直接得到 `never`，通常无害，但如果期望得到 `[]` 或 `''` 就需要用 `[T] extends [never]` 显式处理。

```ts
type Reverse<T extends readonly unknown[], Acc extends unknown[] = []> =
  T extends readonly [infer H, ...infer R] ? Reverse<R, [H, ...Acc]> : Acc;

type Join<T extends readonly string[], Sep extends string, Acc extends string = ''> =
  T extends readonly [infer H extends string, ...infer R extends readonly string[]]
    ? Join<R, Sep, Acc extends '' ? H : `${Acc}${Sep}${H}`>
    : Acc;

type SafeLength<T> = 0 extends 1 & T ? never : T extends readonly unknown[] ? T['length'] : never;

type _t = [
  Expect<Equal<Reverse<[1, 2, 3]>, [3, 2, 1]>>,
  Expect<Equal<Reverse<[]>, []>>,
  Expect<Equal<Join<['a', 'b', 'c'], '-'>, 'a-b-c'>>,
  Expect<Equal<Join<[], '-'>, ''>>,
  Expect<Equal<SafeLength<any>, never>>,
];
```

对长度不定的数组（`string[]`），`[infer H, ...infer R]` 的匹配会失败，`Reverse<string[]>` 返回 `[]`。这通常不是想要的结果，如果输入可能是数组，先判断 `number extends T['length']` 再决定返回什么。

## 3. 深度限制与规模上限

以下数据在 TypeScript 7.0.2 上实测（`tsc --noEmit`）：

| 限制 | 错误码 | 实测 |
|---|---|---|
| 非尾递归的实例化深度 | TS2589 "Type instantiation is excessively deep and possibly infinite" | 每层把递归结果包进模板字面量的 `Repeat`：47 层通过，48 层报错 |
| 尾递归的条件类型迭代次数 | TS2589 | 累加器写法的 `Repeat`：999 次通过，1000 次报错 |
| 联合成员数量 | TS2590 "Expression produces a union type that is too complex to represent" | 1 万成员通过，10 万成员报错 |
| 元组长度 | TS2799 "Type produces a tuple type that is too large to represent" | 7992 通过，15984 报错（上限 1 万） |

非尾递归能走多少层取决于每层消耗多少实例化深度，所以 47 只是这个例子的数字，不同写法会有差别。编译器内部的深度预算是 100 层实例化，再复杂一点的每层结构可能只剩二三十层。设计时按“非尾递归几十层、尾递归一千次以内”估计，并为可能超限的输入准备深度参数。

模板字面量的笛卡尔积是联合规模失控的常见原因：`` `${A}${B}${C}` `` 的成员数是三个联合大小的乘积。路径类型、CSS 值类型、颜色字符串类型最容易撞到这里。

TS 7 的原生编译器检查速度大幅提升，但上面这些上限是语义层面的保护，不会因为编译器变快而放宽。

## 4. 尾递归优化

TS 4.5 起，如果条件类型的某个分支**直接**就是对自身的递归调用，编译器会把它当作循环处理，不在调用栈上叠加，上限从几十层提高到约一千次。

“直接”意味着递归调用的结果不能再被包一层。以下写法都会破坏尾位置：

- 包进模板字面量：`` `${H}${F<R>}` ``
- 展开到元组里：`[H, ...F<R>]`
- 与其他类型做交叉或联合：`F<R> & X`、`F<R> | X`
- 作为参数传给另一个泛型：`Other<F<R>>`

改写的方法是引入累加器参数，把“对递归结果做的加工”提前到传参时做：

```ts
// 非尾递归：递归结果被包进模板字面量
type RepeatSlow<S extends string, N extends number, C extends unknown[] = []> =
  C['length'] extends N ? '' : `${S}${RepeatSlow<S, N, [...C, 0]>}`;

// 尾递归：加工提前到累加器 Acc
type Repeat<S extends string, N extends number, C extends unknown[] = [], Acc extends string = ''> =
  C['length'] extends N ? Acc : Repeat<S, N, [...C, 0], `${Acc}${S}`>;

type _t = [
  Expect<Equal<RepeatSlow<'ab', 3>, 'ababab'>>,
  Expect<Equal<Repeat<'ab', 3>, 'ababab'>>,
];
type Long = Repeat<'a', 500>;      // 尾递归，正常
// @ts-expect-error 非尾递归在 TS 7.0 实测 48 层即报 TS2589
type TooDeep = RepeatSlow<'a', 60>;
```

字符串逐字符处理（`TrimLeft`、`Replace` 的扫描）和元组逐项处理（`Reverse`、`Join`）都应该优先写成尾递归。只有当结果天然是“在递归结果外面加一层”（比如构造嵌套对象 `{ [K in Head]: F<Rest> }`）时才保留非尾形式，这种情况的递归在对象属性里，本身是惰性的。

## 5. 深度计数器

对于输入深度不可控的递归（路径类型、深层对象变换），用一个元组参数计数，到达上限就停：

```ts
type DeepKeys<T, D extends unknown[] = []> =
  D['length'] extends 5
    ? never
    : T extends object
      ? { [K in keyof T & string]: K | `${K}.${DeepKeys<T[K], [...D, 0]>}` }[keyof T & string]
      : never;

type Self = { name: string; parent: Self };  // 自引用类型，没有计数器会无限展开
type K = DeepKeys<Self>;

type _t = [
  Expect<Equal<DeepKeys<{ a: { b: 1 } }>, 'a' | 'a.b'>>,
  Expect<Equal<Extract<K, 'parent.parent.name'>, 'parent.parent.name'>>,
];
```

另一种写法是预先写好递减表 `type Prev = [never, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9]`，用 `Prev[D]` 让 `D` 从上限往下数，到 `never` 停止。两种写法效果相同，元组计数更容易调整上限。

上限取多少：业务对象嵌套一般不超过 5 层，默认值取 5 到 10 足够，并让调用方可以通过类型参数调整。上限越高，自引用类型生成的联合越大，编辑器提示越慢。
