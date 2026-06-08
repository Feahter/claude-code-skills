# <TASK-ID>: 实现计划

> **For agentic workers:** 用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐 task 实施。每个 step 用 `- [ ]` / `- [x]` 跟踪。
> **禁止执行任何 git add/commit/push 操作。**

**Goal:** <一句话目标，复述 spec.md 的需求摘要>

**Architecture:** <2-4 行写清楚关键技术决策。不展开，详见 A 区块>

**Tech Stack:** <框架/库/版本>

**测试命令:** <如 `yarn test path/to/foo.test.ts` / `yarn typecheck`>

---

## A. 技术决策

<以下子项各 2-3 行，简短论述。不要写成 KV 列表。>

### 决策 1: <选型/方案名>
- **选什么**：<具体方案>
- **为什么**：<对比备选 + 理由 + 引用相关代码或文档>
- **代价**：<这种选择的副作用 / 限制>

### 决策 2: <…>
（同上）

---

## B. 任务拆分

> 每条粒度 ≤ 1 个 Session 可完成。粒度过大要继续拆。

### Task 1: <动词开头的标题>

**Files:**
- Test: `<相对路径>`
- Modify / Create: `<相对路径>`

- [ ] Step 1: 写失败测试（TDD RED）
- [ ] Step 2: 跑测试确认失败
- [ ] Step 3: 写最小实现
- [ ] Step 4: 跑测试确认通过（TDD GREEN）
- [ ] Step 5: 类型检查 / 重构

---

### Task 2: <…>
（同上结构）

---

## C. 排除范围回引

> 来源：spec.md 的"排除范围"区块。审查代理对照本节判断 AI 是否越界。

- <粘贴 spec.md 的排除范围条目，便于子 agent 直接读到>

---

## D. 验证证据

> **完成声明前必填**。每条都要贴实际命令 + 关键输出（≤ 30 行截取）。
> 没贴 = 没跑过 = 不能说"完成"。

### 类型检查
```bash
$ yarn typecheck
<贴最关键的 5-10 行；全绿则注明 "0 errors">
```

### 单元测试
```bash
$ yarn test <path/to/relevant.test.ts>
<贴 PASS 那几行的摘要>
```

### 集成 / E2E（如适用）
```bash
$ <命令>
<输出>
```

### 手动验证（如涉及 UI / 链上 / 三方接口）
- [ ] 操作步骤 1，预期 X，实际 X
- [ ] 操作步骤 2，预期 Y，实际 Y

### 风险等级核对
- 本次改动等级：<LOW / MEDIUM / HIGH / CRITICAL>
- 对应风险动作：<参考 risk-and-verify.md，写出已执行的动作>
