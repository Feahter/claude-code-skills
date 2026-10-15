# 核心机制：泛型、条件类型、映射类型

这三样是类型级编程的“函数、分支、循环”：泛型是参数，条件类型是 if，映射类型是对键的 for。

## 目录

1. 泛型：约束、默认类型、多重泛型、推断控制
2. 条件类型：基础、分布式、infer、嵌套
3. 映射类型：基础映射、键重映射 as、修饰符、同态

## 1. 泛型

### 约束与多重泛型

`extends` 约束既限制调用方能传什么，也让函数体内能使用约束上的成员。多个类型参数之间可以互相约束，最常见的是 `K extends keyof T`。

```ts
function pick<T, K extends keyof T>(obj: T, keys: readonly K[]): Pick<T, K> {
  const out = {} as Pick<T, K>;
  for (const k of keys) out[k] = obj[k];
  return out;
}
const user = { id: 1, name: 'a', email: 'x' };
const picked = pick(user, ['id', 'name']);
// @ts-expect-error 'age' 不是 user 的键
pick(user, ['age']);

type _t = Expect<Equal<typeof picked, { id: number; name: string }>>;
```

### 默认类型

默认类型参数必须排在没有默认值的参数之后。默认值可以引用前面的参数。

```ts
type ApiResponse<TData = unknown, TError = { message: string }> =
  | { ok: true; data: TData }
  | { ok: false; error: TError };

type Paged<T, TMeta extends object = { total: number }> = { items: T[]; meta: TMeta };

type R1 = ApiResponse;                    // data: unknown
type R2 = ApiResponse<string[]>;          // error 用默认值
type _t = Expect<Equal<Paged<string>['meta'], { total: number }>>;
```

### 推断控制

- **一个类型参数至少出现两次才有意义。** 只出现一次（如 `function f<T>(x: T): void`）等价于直接写 `unknown`，多出来的泛型只增加阅读负担。
- **`const` 类型参数**让调用处的字面量不被拓宽，见 `01-foundation.md`。
- **`NoInfer<T>`**（TS 5.4+）把某个参数位置排除在推断之外，让它只接受由其他参数推出来的类型。

```ts
function createLight<C extends string>(colors: C[], defaultColor?: NoInfer<C>) {
  return { colors, defaultColor };
}
createLight(['red', 'green'], 'red');
// @ts-expect-error 没有 NoInfer 时 'purple' 会被并入 C，这里报错
createLight(['red', 'green'], 'purple');
```

- **柯里化分步推断**：TS 不支持部分显式指定类型参数（写了一个就要写全）。需要“调用方指定 A、让 B 自动推断”时，拆成两层函数。

```ts
const createStore = <State>() => <const Actions extends Record<string, (s: State) => State>>(actions: Actions) => actions;

const store = createStore<{ count: number }>()({
  inc: (s) => ({ count: s.count + 1 }),  // s 已推断为 { count: number }
});
type _t = Expect<Equal<keyof typeof store, 'inc'>>;
```

## 2. 条件类型

### 基础

`T extends U ? X : Y` 中的 `extends` 判断的是可赋值性，不是相等。`never extends X` 恒为真，`X extends unknown` 恒为真。

### 分布式条件类型

当被检查的类型是**裸类型参数**时，条件类型会对联合的每个成员分别求值再合并。这是 `Exclude`、`Extract` 的工作原理，也是很多意外结果的来源。

```ts
type ToArray<T> = T extends unknown ? T[] : never;
type ToArrayNonDist<T> = [T] extends [unknown] ? T[] : never;  // 包一层元组阻止分配

type MyExclude<T, U> = T extends U ? never : T;

type _t = [
  Expect<Equal<ToArray<string | number>, string[] | number[]>>,
  Expect<Equal<ToArrayNonDist<string | number>, (string | number)[]>>,
  Expect<Equal<MyExclude<'a' | 'b' | 'c', 'a'>, 'b' | 'c'>>,
  Expect<Equal<ToArray<never>, never>>,        // 空联合，分配零次
  Expect<Equal<ToArrayNonDist<never>, never[]>>,
];
```

判断要不要分配：

- 想“逐个成员过滤或变换”，保留分配。
- 想“把整个联合当作一个整体判断”（比如判断是否为 `never`、两个联合是否相等），用 `[T] extends [U]` 关掉分配。
- 分配只发生在裸类型参数上。`T[] extends ...`、`{ a: T } extends ...`、`keyof T extends ...` 都不会分配。

### infer

`infer` 在 `extends` 子句中声明一个待推断的类型变量，只能在 true 分支中使用。它可以出现在任何能放类型的位置：函数参数、返回值、数组元素、Promise 的值、元组的某一段、模板字面量的某一段。

```ts
type Awaited2<T> = T extends PromiseLike<infer V> ? Awaited2<V> : T;   // 递归解包
type ElementOf<T> = T extends readonly (infer E)[] ? E : never;
type FirstArg<F> = F extends (first: infer A, ...rest: any[]) => any ? A : never;

// infer 加约束（TS 4.7+）：匹配到的部分必须满足约束，否则走 false 分支
type FirstIfString<T> = T extends [infer S extends string, ...unknown[]] ? S : never;
// 字符串转数字字面量（TS 4.8+）
type ToNumber<S extends string> = S extends `${infer N extends number}` ? N : never;

type _t = [
  Expect<Equal<Awaited2<Promise<Promise<number>>>, number>>,
  Expect<Equal<ElementOf<readonly string[]>, string>>,
  Expect<Equal<FirstArg<(a: boolean, b: string) => void>, boolean>>,
  Expect<Equal<FirstIfString<['x', 1]>, 'x'>>,
  Expect<Equal<FirstIfString<[1, 'x']>, never>>,
  Expect<Equal<ToNumber<'42'>, 42>>,
];
```

同一个 `infer` 变量出现在多个位置时，协变位置（返回值、属性）的候选合并为联合，逆变位置（函数参数）的候选合并为交叉。`UnionToIntersection` 就是利用逆变位置：

```ts
type UnionToIntersection<U> =
  (U extends unknown ? (x: U) => void : never) extends (x: infer I) => void ? I : never;

type CoVariant<T> = T extends { a: infer X; b: infer X } ? X : never;

type _t = [
  Expect<Equal<UnionToIntersection<{ a: 1 } | { b: 2 }>, { a: 1 } & { b: 2 }>>,
  Expect<Equal<CoVariant<{ a: string; b: number }>, string | number>>,
];
```

对重载函数做 `infer`（包括内置的 `Parameters`、`ReturnType`）只会匹配**最后一个**重载签名，详见 `05-patterns.md` 的重载一节。

### 嵌套条件

嵌套条件按顺序匹配，第一个命中的分支生效。把最具体的情况放前面，`any`、`never` 这类特殊值需要的话放在最前面单独处理。

```ts
type TypeName<T> =
  [T] extends [never] ? 'never'
  : T extends string ? 'string'
  : T extends number ? 'number'
  : T extends boolean ? 'boolean'
  : T extends undefined ? 'undefined'
  : T extends (...args: any[]) => unknown ? 'function'
  : T extends readonly unknown[] ? 'array'
  : 'object';

type _t = [
  Expect<Equal<TypeName<'a'>, 'string'>>,
  Expect<Equal<TypeName<() => void>, 'function'>>,
  Expect<Equal<TypeName<string[]>, 'array'>>,
  Expect<Equal<TypeName<never>, 'never'>>,
  Expect<Equal<TypeName<string | number[]>, 'string' | 'array'>>, // 后面几层仍然分配
];
```

层数超过四五层时，改成“查找表 + 索引访问”通常更清楚，也更快：

```ts
type Lookup = { string: string; number: number; boolean: boolean };
type FromName<N extends keyof Lookup> = Lookup[N];
type _t = Expect<Equal<FromName<'number' | 'string'>, number | string>>;
```

## 3. 映射类型

### 基础映射

`{ [K in Keys]: ... }` 对键联合逐个生成属性。`Keys` 必须是 `string | number | symbol` 的子类型。

```ts
type Flags<K extends string> = { [P in K]: boolean };
type Nullable<T> = { [K in keyof T]: T[K] | null };

type _t = Expect<Equal<Flags<'dark' | 'beta'>, { dark: boolean; beta: boolean }>>;
```

### 修饰符

`readonly` 和 `?` 可以加 `+`（默认）或 `-` 前缀。`-?` 去掉可选并且从值类型中去掉 `undefined`（在未开启 `exactOptionalPropertyTypes` 时尤其明显）。

```ts
type Mutable<T> = { -readonly [K in keyof T]: T[K] };
type Concrete<T> = { [K in keyof T]-?: T[K] };

type Cfg = { readonly host: string; port?: number };
type _t = [
  Expect<Equal<Mutable<Cfg>, { host: string; port?: number }>>,
  Expect<Equal<Concrete<Cfg>, { readonly host: string; port: number }>>,
];
```

### 键重映射 as

`as` 子句（TS 4.1+）在生成属性前改写键名。返回 `never` 的键被丢弃，这就是按值类型或按键名过滤属性的方法。

```ts
type Getters<T> = {
  [K in keyof T as `get${Capitalize<K & string>}`]: () => T[K];
};
type PickByValue<T, V> = { [K in keyof T as T[K] extends V ? K : never]: T[K] };
type OmitByPrefix<T, P extends string> = { [K in keyof T as K extends `${P}${string}` ? never : K]: T[K] };

type Person = { name: string; age: number; _secret: string };
type _t = [
  Expect<Equal<Getters<{ name: string }>, { getName: () => string }>>,
  Expect<Equal<PickByValue<Person, number>, { age: number }>>,
  Expect<Equal<OmitByPrefix<Person, '_'>, { name: string; age: number }>>,
];
```

`as` 也能把一个联合的每个成员映射成一个属性，用于从可辨识联合生成处理器表：

```ts
type Event = { type: 'click'; x: number } | { type: 'key'; code: string };
type Handlers = { [E in Event as E['type']]: (e: E) => void };

type _t = Expect<Equal<Handlers, { click: (e: { type: 'click'; x: number }) => void; key: (e: { type: 'key'; code: string }) => void }>>;
```

### 同态映射

形如 `{ [K in keyof T]: ... }` 且 `T` 是类型参数的映射类型称为**同态映射**，它有三个非同态映射没有的行为：

1. **保留修饰符**：原属性的 `readonly` 和 `?` 会被带过来。
2. **对数组和元组保持形状**：`T` 是元组时结果仍是元组，是数组时结果仍是数组，只映射元素，不会把 `length`、`push` 映射出来。
3. **对联合分配**：`T` 是联合时对每个成员分别映射。

用了 `as` 子句后，修饰符仍保留，但对数组和元组不再保持形状。`Pick<T, K>` 写成 `[P in K]` 且 `K extends keyof T`，同样会保留修饰符。

```ts
type Boxed<T> = { [K in keyof T]: { value: T[K] } };
type FromKeys<T> = { [K in keyof T & string]: T[K] };     // 不是同态写法

type _t = [
  Expect<Equal<Boxed<{ readonly a?: 1 }>, { readonly a?: { value: 1 | undefined } }>>,
  Expect<Equal<Boxed<[1, 2]>, [{ value: 1 }, { value: 2 }]>>,         // 元组保持形状
  Expect<Equal<Boxed<{ a: 1 } | { b: 2 }>, { a: { value: 1 } } | { b: { value: 2 } }>>,
  Expect<Equal<FromKeys<{ readonly a: 1 }>, { a: 1 }>>,               // 修饰符丢失
];
```

`Boxed<{ readonly a?: 1 }>` 的 `value` 带上了 `| undefined`：同态映射里读取 `T[K]` 时，可选属性的值类型包含 `undefined`，开启 `exactOptionalPropertyTypes` 也一样（已用 TS 7.0 实测）。需要原始值类型时用 `Exclude<T[K], undefined>`。
