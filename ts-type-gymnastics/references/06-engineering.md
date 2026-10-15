# 工程化与测试

## 目录

1. 类型测试 Expect / Assert
2. 性能优化
3. 可读性与可维护性
4. 与运行时 Zod 结合
5. tsconfig 严格配置（TS 7）
6. 测试数据不用 as：shoehorn
7. 模块边界：deep modules（可选）

## 1. 类型测试

复杂类型和运行时代码一样需要测试，而且测试要先于实现写：先列出“输入什么、期望得到什么”，再实现，最后跑 `tsc` 看断言是否全部成立。

### 断言工具

`assets/type-assert.ts` 提供 `Equal`、`Expect`、`ExpectFalse`、`NotEqual`、`IsAny`、`IsNever`、`Prettify`。`Equal` 必须用泛型函数技巧实现，朴素的双向 `extends` 写法有两个漏洞：

```ts
type NaiveEqual<A, B> = [A] extends [B] ? ([B] extends [A] ? true : false) : false;

type _t = [
  Expect<Equal<NaiveEqual<any, string>, true>>,              // 朴素写法把 any 判成与 string 相等
  Expect<Equal<NaiveEqual<{ readonly a: 1 }, { a: 1 }>, true>>, // 也分不清 readonly
  ExpectFalse<Equal<any, string>>,
  ExpectFalse<Equal<{ readonly a: 1 }, { a: 1 }>>,
  ExpectFalse<Equal<{ a: 1 } & { b: 2 }, { a: 1; b: 2 }>>,     // 严格：交叉不等于展开后的对象
  Expect<Equal<Prettify<{ a: 1 } & { b: 2 }>, { a: 1; b: 2 }>>, // 先 Prettify 再比较
];
```

`Equal` 对交叉类型的严格是有意的：如果被测类型返回交叉，要么在被测类型里加 `Prettify` 让悬停更可读，要么在测试里比较 `Prettify<Actual>`。

### 测试矩阵

每个公开的工具类型至少覆盖以下输入中适用的部分。大部分类型体操的 bug 出在这些边界上，而不是正常路径：

| 输入 | 为什么要测 |
|---|---|
| 正常路径的 2～3 个典型值 | 基本行为 |
| `never` | 分配后变成 `never`，是不是期望的结果 |
| `any` | 两个分支都走，结果可能是大联合 |
| `unknown` | 约束是否把它挡住 |
| 联合输入 | 分配式还是整体处理 |
| 空值：`[]`、`''`、`{}` | 递归终止条件 |
| 可选属性、`readonly` 属性 | 修饰符是否保留 |
| 数组与元组 | 两种形状的分支是否都对 |
| 嵌套与自引用 | 深度上限是否生效 |
| 非法输入 | 用 `@ts-expect-error` 确认确实报错 |

负向测试用 `// @ts-expect-error`：如果下一行**没有**报错，`tsc` 会报“未使用的 @ts-expect-error”，所以它本身就是断言。不要用 `@ts-ignore` 做负向测试，它在没有错误时静默通过。

### 反向确认

断言全绿只说明当前实现满足当前断言，不说明断言有区分能力。写完测试后，把实现临时改坏（比如把条件类型的两个分支对调，或者删掉一个终止条件），确认相应断言变红，再改回来。

### 项目中的类型测试

- **vitest**：`expectTypeOf` 写在 `*.test-d.ts` 文件里，用 `vitest --typecheck` 运行（vitest 5 实测仍支持）。常用断言：`toEqualTypeOf<T>()`（严格相等）、`toExtend<T>()`（可赋值）、`toMatchObjectType<T>()`（对象的部分匹配）。旧的 `toMatchTypeOf` 已被后两者取代。
- **没有测试框架**：把 `assets/type-assert.ts` 复制进项目，断言写在任意 `.ts` 文件里，只要被 `tsconfig` 包含，`tsc --noEmit` 就会检查。
- **tstyche、tsd**：面向库作者的专用类型测试工具，项目已在使用时沿用。

```ts
import { expectTypeOf, test } from 'vitest';

type Get<T, K extends keyof T> = T[K];

test('Get', () => {
  expectTypeOf<Get<{ a: string }, 'a'>>().toEqualTypeOf<string>();
  expectTypeOf({ a: 1, b: 'x' }).toExtend<{ a: number }>();
  expectTypeOf<Get<{ a: string }, 'a'>>().not.toEqualTypeOf<number>();
});
```

## 2. 性能优化

类型检查慢通常表现为编辑器悬停卡顿、补全延迟、CI 的 `tsc` 时间增长。优化前先测量：

```bash
tsc --noEmit --extendedDiagnostics        # 看 Instantiations、Types、Check time
tsc --noEmit --generateTrace ./trace      # 生成 trace.json，可在 ui.perfetto.dev 中打开
```

两个命令在 TS 7.0 上都可用。改动前后各跑一次，比较 `Instantiations` 和 `Check time`，用数字确认优化有效。

降低开销的做法，按通常的收益排序：

1. **限制生成联合的规模**。模板字面量的笛卡尔积、无深度限制的 `Paths` 是最常见的元凶。加深度参数，或改用宽类型模式加运行时校验。
2. **用 `interface extends` 代替对象类型的交叉**。接口的结构会被缓存，交叉类型每次使用时都要重新计算属性合并。`type A = B & C & { ... }` 在被大量引用时尤其明显。
3. **给中间结果命名**。把复杂表达式拆成具名类型别名，编译器可以缓存别名的实例化结果；同样的表达式内联写多遍会重复计算。
4. **为导出函数标注返回类型**。否则每个调用方都要推断一遍函数体的返回类型。写库时可以开启 `isolatedDeclarations` 强制这一点。
5. **减少大联合之间的比较**。两个大联合互相赋值时的检查开销接近成员数的乘积。能用基类型或判别字段表达的，不要做成几百个成员的联合。
6. **尾递归和深度上限**。非尾递归不仅容易撞到 TS2589，单次实例化也更深，见 `03-recursion.md`。

TS 7 的原生编译器让同样的类型检查快了很多，但上面这些问题造成的是指数或平方级的增长，编译器变快不能抵消它们。

## 3. 可读性与可维护性

类型体操的维护成本主要来自“三个月后没人看得懂”。几条实践：

- **一个别名做一件事**。`Paths` 拆成 `Paths`、`Leaves`、`Dot`、`Prop`，每个都能单独测试和理解。
- **给非显然的技巧写一行注释**。`[T] extends [never]`、`string & {}`、`0 extends 1 & T` 这类写法，第一次见的人不会知道为什么要这样写。
- **导出的工具类型写 JSDoc 和 `@example`**。编辑器悬停时直接显示用法。
- **让结果在悬停时可读**。对外暴露的结果类型包一层 `Prettify`，避免显示成五层交叉。
- **让错误信息可读**。计算失败时返回带说明的类型（`{ __error: 'Expected ...' }`），而不是 `never`，见 `05-patterns.md` 的 Parser 一节。
- **复用优先**：内置工具类型、项目已有的工具类型、`type-fest`，最后才自己写。
- **复杂度要有回报**。业务代码里一个类型需要三层以上的条件嵌套加递归时，先问能不能改 API 形状让类型变简单（比如分段参数代替点分路径，映射表代替条件返回类型）。类型体操最值得用在被大量调用的公共 API 上：写一次，所有调用方都得到补全和检查。

## 4. 与运行时 Zod 结合

TypeScript 的类型在运行时不存在，外部输入（HTTP 响应、表单、环境变量、`localStorage`、消息队列）必须在边界处做运行时校验。Zod 让 schema 成为类型的唯一来源，校验与类型不会互相漂移。以下示例基于 Zod 4（实测 4.6.6）。

```ts
import { z } from 'zod';

const UserId = z.string().regex(/^u_[a-z0-9]+$/).brand<'UserId'>();

const User = z.object({
  id: UserId,
  email: z.email(),                                    // Zod 4 的顶层格式校验器
  role: z.enum(['admin', 'member']),
  createdAt: z.iso.datetime().transform((s) => new Date(s)),
  nickname: z.string().optional(),
});

type User = z.infer<typeof User>;          // 解析后的类型（output）
type UserInput = z.input<typeof User>;     // 解析前的类型（input），transform 前后不同

function parseUser(raw: unknown): User {
  return User.parse(raw);                  // 失败时抛出 ZodError
}

const result = User.safeParse({ id: 'u_1' });
if (!result.success) {
  const issues = result.error.issues;      // 可辨识联合，success 分支才有 data
  void issues;
}

type _t = [
  Expect<Equal<User['createdAt'], Date>>,
  Expect<Equal<UserInput['createdAt'], string>>,
  Expect<Equal<User['role'], 'admin' | 'member'>>,
];

declare function getUser(id: User['id']): void;
// @ts-expect-error 普通字符串不是品牌类型 UserId，必须先经过 schema 解析
getUser('u_1');
```

### 已有类型时保持 schema 同步

项目里已经有手写的类型（或从 OpenAPI 生成的类型），想加 schema 又不想让两者漂移：

```ts
import { z } from 'zod';

type Order = { id: string; amount: number; status: 'paid' | 'refunded' };

const Order = z.object({
  id: z.string(),
  amount: z.number().int().nonnegative(),
  status: z.enum(['paid', 'refunded']),
}) satisfies z.ZodType<Order>;            // schema 的输出必须能赋值给 Order

type _t = Expect<Equal<z.infer<typeof Order>, Order>>; // 双向相等，字段多了少了都会报错
```

`satisfies z.ZodType<Order>` 只检查单向可赋值，schema 少一个可选字段时不会报错；再加一条 `Equal` 断言才能锁住双向一致。

### 可辨识联合与 schema

```ts
import { z } from 'zod';

const Event = z.discriminatedUnion('type', [
  z.object({ type: z.literal('click'), x: z.number(), y: z.number() }),
  z.object({ type: z.literal('key'), code: z.string() }),
]);
type Event = z.infer<typeof Event>;

function handle(e: Event) {
  switch (e.type) {
    case 'click': return e.x + e.y;
    case 'key': return e.code.length;
  }
}
```

分工原则：**类型体操负责编译期能确定的部分**（调用方传的字面量、内部数据流），**schema 负责运行时才知道的部分**（外部输入）。不要用类型体操去“证明”外部数据的形状，也不要在内部数据流里反复做运行时校验。

## 5. tsconfig 严格配置（TS 7）

TypeScript 7.0（原生编译器，2026 年的当前主版本）改变了几个默认值，并移除了一批旧选项。以下行为已在 7.0.2 上实测：

- 不写 `tsconfig` 时，`strict` 默认就是开启的。
- `tsc --init` 生成的配置默认包含 `strict`、`noUncheckedIndexedAccess`、`exactOptionalPropertyTypes`、`verbatimModuleSyntax`、`isolatedModules`、`moduleDetection: "force"`、`skipLibCheck`，以及 `"types": []`（需要 Node 类型时显式写 `"types": ["node"]`）。
- 以下选项已被移除，出现在配置里会直接报错：`baseUrl`、`moduleResolution: "node"`（即 `node10`）、`target: "es5"`、`esModuleInterop: false`、`module: "amd"`、`downlevelIteration`、`outFile`。从 TS 5.x 升级时先清理这些。

推荐配置：

```jsonc
{
  "compilerOptions": {
    "strict": true,                        // TS 7 已默认开启，显式写出表明意图，也兼容旧版本
    "noUncheckedIndexedAccess": true,      // arr[i]、record[k] 的结果带上 undefined
    "exactOptionalPropertyTypes": true,    // 区分“属性缺省”与“显式赋值 undefined”
    "noImplicitOverride": true,            // 覆盖父类方法必须写 override
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "verbatimModuleSyntax": true,          // 只用于类型的导入必须写 import type
    "isolatedModules": true,
    "moduleDetection": "force",
    "skipLibCheck": true,
    // 按运行环境二选一：
    // 打包器（Vite、webpack、esbuild）："module": "preserve", "moduleResolution": "bundler"
    // Node 直接运行："module": "nodenext"
    "target": "esnext"
  }
}
```

可选项：

- `erasableSyntaxOnly`：禁止 `enum`、`namespace`、构造函数参数属性这类需要编译生成代码的语法。代码要被 Node 原生的类型剥离（type stripping）直接运行时开启。
- `noPropertyAccessFromIndexSignature`：索引签名上的属性必须用 `obj['key']` 访问，让“这个键可能不存在”在代码上可见。
- `isolatedDeclarations`：要求导出项都有显式类型，便于并行生成声明文件，适合库。需要同时开启 `declaration`。

在已有项目上收紧配置时，一次只开一个选项，修完报错再开下一个。`noUncheckedIndexedAccess` 和 `exactOptionalPropertyTypes` 在大型项目上可能产生上千个报错，需要评估是否分目录逐步开启。不要为了让新代码通过而关闭已开启的严格选项。

## 6. 测试数据不用 as：shoehorn

测试里经常只需要一个大对象的少数字段，于是写成 `{ body: { id: '1' } } as Request`。这种断言要手动写目标类型，被测函数的参数类型变了也不会报错；故意传错误数据时还要写成 `as unknown as Request`。`@total-typescript/shoehorn` 提供三个函数代替这些断言：

| 函数 | 用途 |
|---|---|
| `fromPartial()` | 传入深度部分的数据，仍然检查已给出字段的类型 |
| `fromAny()` | 故意传入类型错误的数据（测试错误处理），保留自动补全 |
| `fromExact()` | 要求完整数据；先用它占位，以后可以换成 `fromPartial` |

```ts
import { fromAny, fromExact, fromPartial } from '@total-typescript/shoehorn';

type Request = {
  body: { id: string };
  headers: Record<string, string>;
  cookies: Record<string, string>;
  user: { id: string; roles: string[] };
};
declare function getUser(req: Request): string;

getUser(fromPartial({ body: { id: '123' } }));       // 不用伪造 headers、cookies、user
// @ts-expect-error 已给出的字段仍然检查类型
getUser(fromPartial({ body: { id: 123 } }));
getUser(fromAny({ body: { id: 123 } }));             // 测试错误输入
getUser(fromExact({ body: { id: '1' }, headers: {}, cookies: {}, user: { id: 'u', roles: [] } }));
```

**只在测试代码里使用。** 生产代码里需要部分数据，说明类型设计本身应该调整（拆小类型、用 `Pick`）。

迁移已有测试时，先找出测试中的断言：

```bash
rg -n ' as [A-Z]\w*|as unknown as' -g '*.test.ts' -g '*.spec.ts' -g '*.test.tsx' -g '*.spec.tsx'
```

`as Type` 换成 `fromPartial(...)`，`as unknown as Type` 换成 `fromAny(...)`，补上导入，跑一次 typecheck 和测试。

## 7. 模块边界：deep modules（可选）

这一节不属于类型体操本身，但与“让类型和接口保持小而深”是同一个目标：每个包对外只暴露少量入口文件，实现细节藏在子目录里，外部只能经由入口导入。仅在用户明确要求为仓库建立包边界时执行，因为它会安装依赖、新增配置和检查脚本。

用 `dependency-cruiser` 落地，配置模板在 `assets/dependency-cruiser.config.cjs`（来自 mattpocock/skills，MIT）。约定的目录形状：

```text
src/packages/
  <name>/
    index.ts      ← 入口（公开），包根目录下的文件都是入口，可以有多个
    client.ts     ← 另一个入口
    lib/          ← 实现，外部不可见，包内文件之间可自由导入
    tests/        ← 测试与 fixture，也是子目录，同样私有
```

四条规则都是 `error` 级：外部代码只能导入包根目录的入口文件；包内文件可以互相导入；`tests/` 下的测试只能通过入口测试（包括自己的包），不能深入导入实现；不允许循环依赖。

步骤：

1. 识别包管理器（看锁文件）和包根目录（有 `src/` 用 `src/packages`，否则 `packages`）。已有 `.dependency-cruiser.*` 时合并规则而不是覆盖。
2. 以 devDependency 安装 `dependency-cruiser`。
3. 把模板复制到仓库根目录，命名为 `.dependency-cruiser.cjs`（用 `.cjs` 才能在 `"type": "module"` 的仓库里使用 `module.exports`），把 `PACKAGES_ROOT` 改成第 1 步识别的目录。
4. 加 `lint:boundaries` 脚本（`depcruise <packages-root>`），并入已有的总检查命令（与 typecheck 同一个命令）。不改 `tsconfig`，不加路径别名。
5. **证明规则会生效**：先跑一次应通过；在测试文件里临时加一个深层导入（如 `import { x } from '../lib/impl'`），再跑应失败并报 `tests-through-entrypoints`；撤销后再跑应通过。看到“通过、失败、通过”三次结果才算完成。
6. 在包根目录写一份简短的 `README.md` 说明约定，明确不鼓励用一个大 barrel 文件重新导出整个子树；在仓库的 `CLAUDE.md` 或 `AGENTS.md` 加一行指向它。
