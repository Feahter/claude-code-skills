---
name: night-run
description: macOS 全局防睡眠开关,让长任务/夜间任务不被系统睡眠冻结中断。当用户说"任务跑一会儿就断、别让它睡、保持持续执行、防睡眠、夜间/整夜跑、开启/关闭保活、night-run"时触发。开着期间整机不空闲睡眠,当前及任何会话任务都免疫冻结,与会话解耦无需切换。不适用:"关终端后任务还继续"(那要 tmux,见下)、Linux/Windows。
---

# night-run:macOS 全局防睡眠开关

## 它治什么、不治什么

macOS `pmset` 默认 `sleep 1`(空闲 1 分钟整机睡眠),睡眠冻结所有进程 —— 这是"任务跑一会儿就断"最常见的根因。本开关起一条**纯后台长命 caffeinate**(和会话解耦),开着期间整机不睡,**当前及任何会话的任务都免疫冻结,无需切到别处**。

它**不治**"关掉终端后任务还继续":关终端会 SIGHUP 掉那个会话的 claude 进程本身,这是 OS 行为,任何后台开关都救不回。真要关终端走人,得把跑任务的会话放进 `tmux`(off 提示里给了命令),二者正交,可叠加使用。

## 开关怎么用

`~/.claude/scripts/night-run.sh`,三个子命令:

```bash
~/.claude/scripts/night-run.sh on 12    # 开启全局防睡眠 12h(默认12);当前会话任务立刻免疫
~/.claude/scripts/night-run.sh status   # 查看:开关状态 / 电源
~/.claude/scripts/night-run.sh off      # 关闭:结束本开关起的 caffeinate
```

开着就行,该在哪个会话跑任务就在哪跑,不用切换。只认自己 pidfile(`~/.claude/.night-run.pid`)里的进程,不误杀 claude 自带的短命 caffeinate。

## 硬前提(必须提醒用户)

- **开盖 + 插电源**:MacBook 合盖是硬睡眠,`caffeinate -i` 顶不住;电池耗尽同样断。`on` 时脚本检测电池供电会提醒。
- 需要合盖也跑,得改 `pmset`(另一档改动,本 skill 不含)。

## 校验

改脚本后 `bash -n ~/.claude/scripts/night-run.sh` 自检;`night-run.sh status` 核对开关状态与电源。
