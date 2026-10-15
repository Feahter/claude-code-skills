// 类型测试断言工具。复制到项目的测试目录（如 src/types/__tests__/assert.ts）后按需导入。
// 用法：type _t1 = Expect<Equal<Actual, Expected>>;  断言失败时 tsc 报错，通过时零运行时开销。

/**
 * 严格判等。借助“泛型函数的延迟条件类型只有在两侧类型完全相同时才可互相赋值”这一编译器行为，
 * 能区分 any 与其他类型、readonly 与可变、交叉类型与展开后的对象。
 * 朴素写法 [A] extends [B] ? [B] extends [A] ? ... 会把 any 判成与任何类型相等。
 */
export type Equal<X, Y> =
  (<T>() => T extends X ? 1 : 2) extends (<T>() => T extends Y ? 1 : 2) ? true : false;

export type NotEqual<X, Y> = true extends Equal<X, Y> ? false : true;

export type Expect<T extends true> = T;
export type ExpectFalse<T extends false> = T;

/** A 能赋值给 B（宽松，只验证兼容性，不验证完全相同）。 */
export type Extends<A, B> = [A] extends [B] ? true : false;

export type IsAny<T> = 0 extends 1 & T ? true : false;
export type IsNever<T> = [T] extends [never] ? true : false;
export type IsUnknown<T> = IsAny<T> extends true ? false : unknown extends T ? true : false;

/** 展开交叉类型，便于与对象字面量类型做 Equal 比较，也让悬停提示更可读。 */
export type Prettify<T> = { [K in keyof T]: T[K] } & {};
