# claude-code-skills

个人 Claude Code skills 备份库。每个子目录是一个独立 skill，包含 `SKILL.md` 与可选的 `scripts/` `assets/` 资产。

## 安装方法

```bash
# 把目标 skill 软链到 ~/.claude/skills/ 即可
ln -s "$(pwd)/<skill-name>" ~/.claude/skills/<skill-name>
```

或直接复制：

```bash
cp -R <skill-name> ~/.claude/skills/
```

## 已收录

| Skill | 用途 |
|---|---|
| [loss-analysis](./loss-analysis) | 复盘 Claude Code 历史会话的时间损耗与低效率信号，生成深色主题 HTML 报告 |
