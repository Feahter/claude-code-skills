---
name: ts-type-gymnastics
description: TypeScript 类型层的设计、排错与审计：写工具类型和泛型函数签名，用条件、映射、模板字面量和递归类型从字符串或对象推导类型（含 Paths / Get 路径类型），让 API 获得精确补全；修 TS2589、TS2590、not assignable、excessively deep 等类型报错；用 unknown、satisfies、品牌类型、可辨识联合替换 any 和 as；审计项目里的类型反模式；配置 strict 和 TS 7 tsconfig；给类型写测试；用 Zod 推导类型；做 type-challenges。用户没说“类型体操”，或用英文说 advanced types、type-level programming、branded types 时同样适用。纯运行时逻辑 bug，或与类型无关的 React、RxJS 用法问题不用本 skill。
---

# TypeScript 类型体操

内容整合自 wshobson/agents、ofershap、mattpocock/skills 的相关 skill，已按 TypeScript 7.0 校正。`references/` 中的每个代码块都在 TS 7.0.2 的严格配置下编译通过，`Expect<Equal<...>>` 断言即示例的预期结果。

## 先判断是哪类任务

| 任务 | 做法 |
|---|---|
| 日常写 TS：业务代码、组件、接口定义 | 遵守下面的“日常底线规则”，通常不需要读 references |
| 设计类型：工具类型、泛型 API、从字符串或对象推导类型 | 走“类型设计工作流”，按“导航”读对应的 reference |
| 修类型报错 | 先对照“高频陷阱”，再看报错码：TS2589 读 `03-recursion.md`，TS2590 读 `04-string-path.md` 第 1 节 |
| 审计项目里的类型反模式 | 走“审计模式” |
| 配置 tsconfig、升级到 TS 7、给类型写测试、接 Zod | 读 `06-engineering.md` 对应小节 |

先确认项目的 TypeScript 版本（`package.json` 或 `npx tsc -v`），不同版本的能力差别很大：`const` 类型参数需要 5.0+，`NoInfer` 需要 5.4+，TS 7 移除了 `baseUrl` 等一批选项。

## 日常底线规则

这些规则针对 agent 最常写出的过时或不安全写法。每条都说明理由，因为遇到例外时需要靠理由判断。

1. **用 `unknown` 代替 `any`。** `any` 会关掉检查并沿着赋值传染，`unknown` 要求先收窄再使用。外部输入（`JSON.parse`、接口响应、`catch` 的错误）一律当作 `unknown`，在边界处用 schema 或类型谓词收窄。
2. **用 `satisfies` 校验，不用 `as` 断言。** `x satisfies T` 检查 `x` 符合 `T` 但保留 `x` 更精确的推断类型；`x as T` 只是让编译器闭嘴，字段写错、缺失都不会报错。`as` 只在你确实比编译器知道得多时使用（例如智能构造函数内部、类型体操实现内部），并且要有测试守住。`as unknown as T` 几乎总是设计问题。
3. **互斥状态用可辨识联合，不用一堆可选字段。** `{ data?: T; error?: E; loading?: boolean }` 允许不可能的组合；`{ status: 'success'; data: T } | { status: 'error'; error: E }` 让每个状态的字段都确定，`switch` 能穷尽检查。
4. **常量对象和数组用 `as const`，字面量泛型用 `const` 类型参数。** 避免字面量被拓宽成 `string`。
5. **穷尽检查**：处理联合的 `switch` 在 `default` 里把值赋给 `never`，联合新增成员时编译器会指出漏处理的地方。
6. **用类型谓词 `x is T` 或断言函数 `asserts x is T` 收窄**，而不是 `as T`。
7. **领域 ID 和单位用品牌类型**（`UserId`、`OrderId`、`Cents`），防止同为 `string`、`number` 的值被混用。
8. **只用于类型的导入写 `import type`**，开启 `verbatimModuleSyntax` 后这是强制的。
9. **字符串模式用模板字面量类型**（`` `${Locale}_${Key}` ``、`` `${number}px` ``），不要退回 `string`。
10. **需要阻止某个参数参与推断时用 `NoInfer<T>`**，例如默认值必须来自前面参数推出的联合。
11. **不用 `enum`**，用 `as const` 对象加 `(typeof X)[keyof typeof X]`，或直接用字面量联合。`enum` 需要生成运行时代码，与 `erasableSyntaxOnly` 和 Node 的类型剥离不兼容。
12. **不用 `Function`、`Object`、`{}` 表示“任意函数 / 任意对象 / 任意值”**。分别用具体的函数签名、`object` 或 `Record<string, unknown>`、`unknown`。`string & {}`、`Prettify` 末尾的 `& {}` 是另一回事，属于有意的类型技巧。
13. **`@ts-expect-error` 优于 `@ts-ignore`，并且必须写原因。** 前者在错误消失时会报“未使用”，提醒你删掉它。
14. **不为了让代码通过而关闭严格选项**。TS 7 默认开启 `strict`；推荐的额外选项见 `06-engineering.md` 第 5 节。开启 `noUncheckedIndexedAccess` 后，索引访问的结果要先判空。

## 类型设计工作流

写任何非平凡的类型（工具类型、泛型签名、推导类型）都按这个顺序，因为类型体操的 bug 几乎都在边界输入上，而边界输入只有事先列出来才会被测到。

1. **先写期望**。用 `Expect<Equal<Actual, Expected>>` 写出 3～5 个典型输入和对应结果，再按 `06-engineering.md` 的测试矩阵补边界：`never`、`any`、联合、空值（`[]`、`''`、`{}`）、可选和 `readonly`、数组与元组、非法输入（`@ts-expect-error`）。断言工具在 `assets/type-assert.ts`，项目里没有就复制过去。
2. **找现成的**。内置工具类型、项目已有的类型工具、`type-fest`（项目已依赖时）。能组合现成类型就不手写。
3. **实现**。拆成多个具名小类型，每个只做一件事。递归一律优先写成尾递归（累加器写法），输入深度不可控时加深度参数。
4. **跑 `tsc --noEmit`**（或项目的 typecheck 命令），断言全部通过才算完成。没有项目环境时，在临时目录建一个最小的 `tsconfig`（`strict: true`）单独编译。
5. **反向确认**。把实现临时改坏一处（对调分支、删掉终止条件），确认至少一条断言变红后再改回。
6. **检查可读性和开销**。悬停结果是否可读（需要时包 `Prettify`），注释是否解释了非显然的技巧，大型输入下 `--extendedDiagnostics` 的 `Instantiations` 是否可接受。

交付时把类型测试一起交付，说明测试覆盖了哪些边界、没覆盖哪些。

## 高频陷阱

这些行为与直觉相反，是类型体操里最常见的错误来源。详细解释和示例在括号中的文件里。

- **`never` 进入分布式条件类型直接得到 `never`**，`T extends never ? A : B` 判断不了 `never`，要写 `[T] extends [never]`。（01 第 5 节）
- **`any` 进入条件类型会走两个分支**，结果是两者的联合；递归类型要在入口拦截 `any`。（01 第 5 节、03 第 2 节）
- **分布式只发生在裸类型参数上**；需要整体判断时用 `[T] extends [U]` 包起来。（02 第 2 节）
- **`keyof (A | B)` 是共有键**，不是所有键。（01 第 3 节）
- **`T extends object` 对数组和函数也成立**，处理对象时先排除函数和数组。（03 第 1 节）
- **`Date`、`Map` 等内置对象会被映射类型展开成方法集合**，深度变换要把它们列为叶子；但叶子判断按结构匹配，`Error` 这类宽类型会误伤普通对象，`Map` / `Set` 要先于 `WeakMap` / `WeakSet` 判断。（03 第 1 节）
- **同态映射 `{ [K in keyof T]: ... }` 保留修饰符、保持数组和元组形状**；改成 `[K in keyof T & string]` 或加 `as` 后这些行为会部分丢失。（02 第 3 节）
- **`Parameters`、`ReturnType` 对重载函数只取最后一个签名。**（05 第 8 节）
- **朴素的 `Equal` 把 `any` 判成与任何类型相等**，类型测试必须用 `assets/type-assert.ts` 里的版本。（06 第 1 节）
- **类的类型参数不出现在任何成员里时不参与结构比较**，类型状态模式要加一个 `declare` 字段。（05 第 5 节）
- **非尾递归约几十层就报 TS2589，尾递归上限约一千次**；联合超过约 10 万成员报 TS2590，元组超过 1 万元素报 TS2799。（03 第 3 节）
- **模板字面量插槽里的联合做笛卡尔积**，规模是各插槽大小的乘积。（04 第 1 节）
- **`'a' | string` 会被化简成 `string`**，要保留补全写 `'a' | (string & {})`。（01 第 2 节）

## 导航

`references/` 按“TypeScript 类型体操”思维导图的六个分支组织。只读当前任务需要的文件，每个文件开头有目录。

| 分支 | 文件 | 内容 |
|---|---|---|
| 基础构建块 | `references/01-foundation.md` | 字面量与拓宽、`const` 类型参数；联合与交叉的化简规则；`keyof` / `typeof` / 索引访问；元组、可变元组、`Head` / `Tail` / `Last`；`never` / `unknown` / `any` 的精确控制、`IsNever` / `IsAny`、穷尽检查、互斥参数 |
| 核心机制 | `references/02-core-mechanisms.md` | 泛型约束、默认类型、多重泛型、`NoInfer`、柯里化分步推断；条件类型基础、分布式与关闭分配、`infer`（含 `infer X extends`、协变与逆变位置）、嵌套条件与查找表；映射类型基础、修饰符 `+` / `-`、键重映射 `as` 与过滤、同态映射 |
| 递归与控制 | `references/03-recursion.md` | 递归类型别名（惰性与立即展开）、`DeepReadonly` 骨架；递归终止条件表；深度限制与规模上限的 TS 7 实测数据；尾递归优化与改写方法；深度计数器 |
| 字符串与路径 | `references/04-string-path.md` | 模板字面量的构造与拼接；模式匹配加 `infer`（`Trim`、`Split`、`ReplaceAll`、路由参数）；内置字符串操作与 `CamelCase` / `KebabCase`；路径类型 `Paths`、`Leaves`、`Get` / PathValue、数组与元组路径；类型安全的 `get` 与分段 API |
| 实用模式与高阶技巧 | `references/05-patterns.md` | 工具类型扩展（`Prettify`、`Merge`、`PartialBy`、`StrictOmit`、`AtLeastOne`）；品牌类型与智能构造函数；可辨识联合与关联联合问题；类型级计算（加减、比较、定长元组）；状态机（转移表、类型状态）；类型级 Parser（printf、查询字符串、可读错误）；HKT 模拟；函数重载模拟 |
| 工程化与测试 | `references/06-engineering.md` | 类型测试（`Equal` 的正确实现、测试矩阵、反向确认、vitest `expectTypeOf`）；性能优化（测量命令与优化顺序）；可读性与可维护性；Zod 4 结合（`z.infer` / `z.input`、`.brand()`、与已有类型同步）；TS 7 的 tsconfig 严格配置与已移除选项；shoehorn 测试数据；deep modules 模块边界 |

`assets/type-assert.ts` 是可直接复制进项目的断言工具；`assets/dependency-cruiser.config.cjs` 是模块边界的配置模板，只在用户要求建立包边界时使用（步骤见 `06-engineering.md` 第 7 节）。

## 审计模式

用户要求检查项目的类型质量（“审计一下类型”“找找 any”“audit”）时，先用搜索定位候选，再逐个读上下文判断，因为很多命中是合理的（例如泛型约束里的 `any[]`、测试里的 `fromAny`、智能构造函数里的 `as`）。

```bash
rg -n --type ts ':\s*any\b|<any>|as any\b|any\[\]' .                 # any
rg -n --type ts 'as unknown as|\bas [A-Z]\w*(<[^>]*>)?[;,)\s]' .      # 断言
rg -n --type ts '@ts-ignore|@ts-expect-error\s*$|@ts-nocheck' .      # 无说明的压制
rg -n --type ts '^\s*(export\s+)?(const\s+)?enum\s|:\s*Function\b' .  # enum、Function 类型
rg -n --type ts '[\w)\]]!\.' .                                       # 非空断言
rg -n '"strict"\s*:\s*false|"noImplicitAny"\s*:\s*false|"baseUrl"' -g 'tsconfig*.json' .
```

输出按严重程度分组，每条给出 `文件:行号`、问题、建议写法：

- **critical**：会让错误在运行时才暴露。外部输入直接标成 `any` 或断言成具体类型、`strict: false`、关闭 `noImplicitAny`、`@ts-ignore` 压掉真实错误、`as unknown as` 绕过不兼容的类型。
- **warning**：削弱类型检查但影响局部。业务代码里的 `as T`、可选字段堆砌的状态对象、`enum`、`Function` 类型、缺少穷尽检查的 `switch`、没写原因的 `@ts-expect-error`、TS 7 已移除的配置项。
- **info**：风格和可维护性。缺少 `import type`、可以用 `satisfies` 的地方、可以用品牌类型的裸 ID、过长的内联类型。

报告末尾给出数量统计和建议的修复顺序（先 critical，再按模块分批）。默认只报告不修改，用户确认后再动手。
