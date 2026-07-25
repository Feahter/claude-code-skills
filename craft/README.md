# craft

单个编码任务的自包含质量闭环。权威指令见 `SKILL.md`。

## 两个入口

1. 显式调用：`/craft [lite|full|ultra] <任务描述>`。
2. 编排调用：`auto-orchestrate` 在 `plan.md` 中标记
   `owner: craft`，并提供 task、lane、worktree、风险和验收标准。

普通编码关键词不会自动触发 craft。任务明显需要多个可独立执行单元时，
应交给 `auto-orchestrate`。

## 闭环

```text
侦察 -> 极简实现 -> 内联清理 -> 自审分流 -> 风险验证 -> 提交与证据
```

- 内联检查复用、重复、范围、复杂度、接口和测试，不依赖
  `simplify`。
- 不派生子 Agent；独立审查由父编排器安排。
- P2/P3 自动修复并重跑验证；P0/P1 返回父编排器或用户裁决。
- CRITICAL 在任何编辑前先核验父编排器授权或取得用户明确确认。
- 验证命令从项目配置探测，非 TypeScript 项目不会执行 TypeScript
  检查。
- 编排模式在任务分支内提交并返回 base/head SHA、diff package、
  验证结果和未验证项。

## Git 边界

编排模式允许在当前任务分支提交。始终禁止 push、merge、rebase、
reset、删除分支和删除 worktree。

## 职责边界

craft 负责一个实现单元；`auto-orchestrate` 负责 lane、worktree、独立
审查、integration 验证和最终用户决策。
