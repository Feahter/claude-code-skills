---
name: clean-stale-branches
description: 一键清理当前 git 仓库中本项目用户创建、超过 N 天（默认 30 天）未更新的本地和远端分支。先安全删（已合并）再汇报未合并清单，远端删除前二次确认，支持 dry-run 预览和 reflog 恢复。触发场景：用户说"清理分支 / 清理旧分支 / 清理 30 天外的分支 / 收拾分支 / 归档分支 / clean stale branches / prune branches / 删掉我的老分支"。不适用于：跨仓库批量操作、按主题删分支、删别人的分支。
---

# Clean Stale Branches

按当前仓库 `git config user.email` 作者过滤，清理 N 天外的本地 + 远端分支。

## ⚠️ 先看：关于 squash merge 的误判

**如果项目用 GitLab/GitHub 的 squash merge（squash and merge），`git branch -d` 会把已并入 master 的分支判为"未合并"**——因为 squash 后 commit hash 变了，git 找不到原始 commit 的 merge 关系。

体现：跑完 Step 3 后 `unmerged-local.txt` 里一堆你记得明明合过的分支。**这不是 bug**，要向用户说明，让他看分支名判断能不能强删。

## 触发

用户说：
- "清理分支 / 清理旧分支 / 清理我创建的老分支 / 收拾分支 / 归档分支"
- "把 30 天外的分支删了 / 把我的过期分支删了"
- "clean stale branches / prune branches"

## 不触发

- 想清理别人的分支（应使用 GitLab/GitHub 后台操作，涉及他人工作）
- 想按分支名关键字删（手动 `git branch -D` 更合适）
- 不在 git 仓库

## 变体

- **"只清本地"** → 跳过 Step 5
- **"只清远端"** → 跳过 Step 3-4，Step 5 直接读 `remote-candidates.txt`
- **"dry run / 先预览 / 不要真删"** → Step 1-2 后，用 `--dry-run` 跑 delete 脚本，不执行任何删除

## 工作流（必须按序执行）

### Step 1：探明现状 + 参数确认

**并行执行**：
```bash
git config user.name && git config user.email && git symbolic-ref --short HEAD 2>/dev/null || echo "(detached HEAD)"
git fetch --all --prune 2>&1 | tail -20
```

**确认参数**（缺省用默认，用户指定则用用户的）：
- 天数窗口：默认 30，用户可说"保留最近 60 天"
- 作者邮箱：默认 `git config user.email`，用户可说"清理 xxx 创建的"
- 保护分支：默认 `master|main|pre|dev|HEAD`，按项目情况增减

### Step 2：生成候选清单并展示

跑 `scripts/list-candidates.sh <days> <author_email>`，产物：
- `tmp/branch-cleanup/local-candidates.txt`
- `tmp/branch-cleanup/remote-candidates.txt`
- `tmp/branch-cleanup/candidates-preview.txt`（带日期）

**必须把两个清单的前 20 条 + 总数展示给用户**，并用 `AskUserQuestion` 收集：

1. **本地未合并分支的处理策略**
   - 先用 `-d` 安全删，未合并的单独列出（推荐）
   - 全部 `-D` 强删（用户明确表示这些分支都可弃）
   - 只删已合并，未合并全保留

2. **远端执行方式**
   - 本地处理完后，远端清单再次给用户确认（推荐，不可逆）
   - 本地远端一起删

3. **敏感前缀分支**（如 `master-*`、`release-*`、`hotfix-*`）
   - 若候选里含敏感前缀，单独列出问用户是否保留

### Step 3：本地安全删

跑 `scripts/delete-local.sh`（加 `--dry-run` 先预览，加 `--force` 走 `-D`）：
- 成功的记入 `tmp/branch-cleanup/deleted-local.txt`
- 失败（未合并/其他错误）记入 `tmp/branch-cleanup/unmerged-local.txt`
- 错误原因落在 `tmp/branch-cleanup/delete-local.err.log`

注意 squash merge 场景——见开头警告。

### Step 4：未合并分支处理

把 `unmerged-local.txt` 内容按 `日期 | 分支名 | 短 hash | commit 主题` 格式展示，让用户选：
- 全部 `-D` 强删（走 `scripts/delete-local.sh --force`）
- 保存清单到 `.local/docs/unmerged-branches.md`，后续人工处理
- 全部保留

### Step 5：远端删除（需二次确认）

展示远端候选清单总数 + 部分条目，等用户"确认删"再执行。

**强烈建议先 `scripts/delete-remote.sh --dry-run` 给用户看一次最终计划**，再正式跑。

正式跑 `scripts/delete-remote.sh`：
- 分批 `git push origin :br1 :br2 ...`（每批 10 个，减少连接开销）
- 批量失败时自动回退到单条重试，避免一个坏分支连累整批
- 失败清单落在 `tmp/branch-cleanup/failed-remote.txt`

### Step 6：汇总

输出一张表：本地已删 / 本地保留 / 远端已删 / 失败数。说明临时产物在 `tmp/branch-cleanup/`，需要保留就留着。

**提示用户恢复方式**：
- 本地删除可通过 `scripts/restore-local.sh` 从 reflog 恢复（无参数列候选，带分支名交互恢复）
- 远端删除**不可恢复**，只能靠本地还留着的分支重新 push

## 禁止事项

- 不得跳过 Step 2 的清单展示，直接删分支
- 不得在 Step 5 前跳过"二次确认"直接推远端删除
- 不得删除非候选名单内的分支
- 不得动 `.gitconfig` 或其他项目级 git 配置
- 发现脚本执行异常（如权限、网络）立即停下汇报，不要改用别的命令硬凑

## 参数说明

- `list-candidates.sh <days> <author_email> [protected_regex]`
- `delete-local.sh [--force] [--dry-run]` （读 `tmp/branch-cleanup/local-candidates.txt`）
- `delete-remote.sh [--dry-run]` （读 `tmp/branch-cleanup/remote-candidates.txt`）
- `restore-local.sh [branch-name]` （无参数列候选，带分支名交互恢复）

默认 `protected_regex="^(master|main|pre|dev|HEAD)$"`。
