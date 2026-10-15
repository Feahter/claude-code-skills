# 基础构建块

类型体操的每一步最终都落在这几样东西上。这里的行为细节（拓宽、分配、`never` 被吸收）是后面各章出错的主要来源，写复杂类型前值得先对照一遍。

代码块中的 `Equal` / `Expect` 来自 `assets/type-assert.ts`。

## 目录

1. 字面量类型与拓宽
2. 联合与交叉
3. keyof、typeof 与索引访问
4. 元组与可变元组
5. never、unknown、any 的精确控制

## 1. 字面量类型与拓宽

`let` 声明和可变对象属性会把字面量拓宽成基础类型，`const` 声明不会。要让对象或数组里的值保持字面量，用 `as const`；要让泛型参数按字面量推断，用 `const` 类型参数（TS 5.0+），调用方就不用写 `as const`。

```ts
let a = 'GET';                 // string
const b = 'GET';               // "GET"
const obj = { method: 'GET' }; // { method: string }
const frozen = { method: 'GET', tags: ['a', 'b'] } as const;
// { readonly method: "GET"; readonly tags: readonly ["a", "b"] }

function routes<const T extends readonly string[]>(paths: T): T {
  return paths;
}
const r = routes(['/home', '/about']); // readonly ["/home", "/about"]

type _t = [
  Expect<Equal<typeof a, string>>,
  Expect<Equal<typeof b, 'GET'>>,
  Expect<Equal<typeof obj, { method: string }>>,
  Expect<Equal<(typeof frozen)['tags'], readonly ['a', 'b']>>,
  Expect<Equal<typeof r, readonly ['/home', '/about']>>,
];
```

`const` 类型参数的约束要写成 `readonly` 数组，否则传入数组字面量时推断会退回到可变的 `string[]`。

## 2. 联合与交叉

联合 `A | B` 是“值属于其一”，交叉 `A & B` 是“值同时满足两者”。几条容易出错的规则：

- 原始类型的交叉如果不可能同时成立就化简为 `never`，例如 `string & number`。
- 对象交叉时同名属性各自交叉，冲突属性变成 `never`，但整个对象不一定变成 `never`。只有当冲突的属性是字面量类型的判别字段时，整个交叉才化简为 `never`。
- 在联合上取属性，只能访问所有成员共有的属性，需要先收窄。

```ts
type P = string & number;                          // never
type O = { a: string } & { a: number };            // { a: never }，对象本身仍存在
type D = { kind: 'a' } & { kind: 'b' };            // never，判别字段冲突

type _t = [
  Expect<Equal<P, never>>,
  Expect<Equal<O['a'], never>>,
  Expect<Equal<D, never>>,
];

type Shape = { kind: 'circle'; r: number } | { kind: 'square'; size: number };
function area(s: Shape) {
  if ('r' in s) return Math.PI * s.r ** 2; // in 收窄
  return s.size ** 2;
}
```

字面量联合想保留自动补全又允许任意字符串时，用 `string & {}` 占位。直接写 `'a' | string` 会被化简成 `string`，补全就没了。

```ts
type Color = 'red' | 'blue' | (string & {});
const c1: Color = 'red';     // 编辑器会提示 red / blue
const c2: Color = '#ff0000'; // 也允许
```

## 3. keyof、typeof 与索引访问

- `typeof x` 把值空间的变量提升到类型空间。`keyof typeof obj` 是从常量对象取键联合的惯用法。
- `T[K]` 是索引访问，`K` 可以是联合，结果是对应值类型的联合。`T[number]` 取数组或元组的元素类型。
- `keyof` 作用在联合上得到的是**共有键**，作用在交叉上得到的是所有键的并集。
- `keyof any` 等于 `string | number | symbol`，内置别名 `PropertyKey` 就是它。
- 带字符串索引签名的类型，`keyof` 是 `string | number`，因为数字键在 JS 中会被转成字符串。

```ts
const STATUS = { active: 1, banned: 2 } as const;
type StatusKey = keyof typeof STATUS;              // "active" | "banned"
type StatusCode = (typeof STATUS)[StatusKey];      // 1 | 2

const ROLES = ['admin', 'editor', 'viewer'] as const;
type Role = (typeof ROLES)[number];                // "admin" | "editor" | "viewer"

type A = { id: string; a: number };
type B = { id: string; b: boolean };
type _t = [
  Expect<Equal<StatusCode, 1 | 2>>,
  Expect<Equal<Role, 'admin' | 'editor' | 'viewer'>>,
  Expect<Equal<keyof (A | B), 'id'>>,
  Expect<Equal<keyof (A & B), 'id' | 'a' | 'b'>>,
  Expect<Equal<keyof { [k: string]: unknown }, string | number>>,
];
```

想只拿字符串键时写 `keyof T & string`，或者在模板字面量里用 `Extract<keyof T, string>`，否则 `symbol` 键会让 `` `${K}` `` 报错。

## 4. 元组与可变元组

元组是定长、按位置定型的数组。它是类型级计数和参数列表变换的基础：`T['length']` 是数字字面量，展开 `[...A, ...B]` 可以拼接。

- 元组元素可以有标签 `[name: string, age?: number]`，可选元素让 `length` 变成联合，例如 `1 | 2`。
- 剩余元素可以出现在任意位置：`[string, ...number[], boolean]`。
- 可变元组泛型（TS 4.0+）让函数能保留参数列表的精确形状，`concat`、`curry`、`bind` 这类函数靠它写出精确签名。
- `as const` 产生的是 `readonly` 元组。接收它的泛型约束要写 `readonly unknown[]`，否则不兼容。

```ts
type Point = [x: number, y: number, z?: number];
type Len = Point['length'];                         // 2 | 3

function concat<A extends readonly unknown[], B extends readonly unknown[]>(
  a: A,
  b: B,
): [...A, ...B] {
  return [...a, ...b];
}
const joined = concat([1, 'a'] as const, [true] as const); // [1, "a", true]

type Head<T extends readonly unknown[]> = T extends readonly [infer H, ...unknown[]] ? H : never;
type Tail<T extends readonly unknown[]> = T extends readonly [unknown, ...infer R] ? R : [];
type Last<T extends readonly unknown[]> = T extends readonly [...unknown[], infer L] ? L : never;

// 去掉函数的第一个参数，常用于给已有函数绑定上下文
type DropFirst<F> = F extends (first: any, ...rest: infer R) => infer Ret
  ? (...args: R) => Ret
  : never;

type _t = [
  Expect<Equal<Len, 2 | 3>>,
  Expect<Equal<typeof joined, [1, 'a', true]>>,
  Expect<Equal<Head<[1, 2, 3]>, 1>>,
  Expect<Equal<Tail<[1, 2, 3]>, [2, 3]>>,
  Expect<Equal<Last<[1, 2, 3]>, 3>>,
  Expect<Equal<Head<[]>, never>>,
  Expect<Equal<DropFirst<(ctx: object, id: string, n: number) => void>, (id: string, n: number) => void>>,
];
```

区分数组和元组：`number extends T['length']` 为真说明是数组（长度不确定），为假说明是元组。递归处理时这两种情况的终止条件不同，见 `03-recursion.md`。

## 5. never、unknown、any 的精确控制

三者在类型格中的位置：`unknown` 是顶类型（任何值都能赋给它），`never` 是底类型（它能赋给任何类型，但没有值能赋给它），`any` 同时关掉了两个方向的检查。

| 行为 | `never` | `unknown` | `any` |
|---|---|---|---|
| 在联合中 | 被吸收：`A \| never` = `A` | 吸收其他成员：`A \| unknown` = `unknown` | 吸收其他成员 |
| 在交叉中 | 吸收其他成员 | 被吸收：`A & unknown` = `A` | 吸收其他成员 |
| 作为裸类型参数进入条件类型 | 直接得到 `never`（空联合分配零次） | 正常判断 | 两个分支的联合 |
| `keyof` | `string \| number \| symbol` | `never` | `string \| number \| symbol` |

判定工具要绕开这些特殊行为：

```ts
type IsNever<T> = [T] extends [never] ? true : false;     // 用元组包住，阻止分配
type IsAny<T> = 0 extends 1 & T ? true : false;           // 只有 any 能让 1 & T 接纳 0
type IsUnknown<T> = IsAny<T> extends true ? false : unknown extends T ? true : false;

type NaiveIsNever<T> = T extends never ? true : false;
type AnyBranch<T> = T extends string ? 'yes' : 'no';

type _t = [
  Expect<Equal<IsNever<never>, true>>,
  Expect<Equal<NaiveIsNever<never>, never>>,   // 朴素写法的陷阱
  Expect<Equal<IsAny<any>, true>>,
  Expect<Equal<IsAny<unknown>, false>>,
  Expect<Equal<IsUnknown<unknown>, true>>,
  Expect<Equal<AnyBranch<any>, 'yes' | 'no'>>, // any 走两个分支
  Expect<Equal<keyof unknown, never>>,
];
```

`never` 的三种实际用途：

1. **穷尽检查**：在 `switch` 的 `default` 里把被收窄的值赋给 `never`，联合新增成员时编译器会在这里报错。
2. **过滤**：映射类型的 `as` 子句或条件类型返回 `never`，该成员就从结果中消失。
3. **禁止某个参数或属性**：`{ a: string; b?: never }` 表示不允许传 `b`，常用于互斥参数。

```ts
function assertNever(x: never): never {
  throw new Error(`Unhandled case: ${JSON.stringify(x)}`);
}

type Status = 'active' | 'pending';
function label(s: Status) {
  switch (s) {
    case 'active': return 'Active';
    case 'pending': return 'Pending';
    default: return assertNever(s);
  }
}

// 互斥参数：要么传 id，要么传 slug，不能都传
type ById = { id: string; slug?: never };
type BySlug = { slug: string; id?: never };
function find(q: ById | BySlug) { return q; }
find({ id: '1' });
// @ts-expect-error 两个都传会报错
find({ id: '1', slug: 'x' });
```

`unknown` 是外部输入（`JSON.parse`、`fetch` 结果、`catch` 的错误）的正确类型。它要求先收窄再使用，收窄方式按可靠性排序：运行时 schema 校验（见 `06-engineering.md` 的 Zod 一节）、自定义类型谓词 `x is T`、`typeof` / `in` / `instanceof` 内联判断。`any` 只在两种场合可以接受：泛型约束中表示“任意函数”（如 `(...args: any[]) => unknown`，因为参数位置是逆变的，`unknown[]` 会拒绝具体参数类型的函数），以及与无类型的第三方边界对接时临时使用并尽快收窄。
