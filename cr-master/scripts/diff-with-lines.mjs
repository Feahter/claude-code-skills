#!/usr/bin/env node
/**
 * diff-with-lines.mjs — 输出本地 git diff，并为每个 +/- 行标注真实文件行号
 *
 * 本地 `git diff` 本身不带行号，模型只能靠 hunk header 心算定位，行内标注常飘。
 * 这个脚本把行号算好直接写进 diff，让审查意见能精确落到 file:line。
 *
 * 用法：
 *   node diff-with-lines.mjs                     # 工作区改动（未暂存 + 已暂存）
 *   node diff-with-lines.mjs --staged            # 仅暂存区
 *   node diff-with-lines.mjs --commit <sha>      # 单个 commit 对比其父
 *   node diff-with-lines.mjs --range <a>..<b>    # 两个 ref 之间
 *
 * 标注格式：
 *   +[L42] added code        新文件第 42 行
 *   -[L10] removed code      旧文件第 10 行
 *    [L42] context line      上下文（标新文件行号）
 *
 * 低价值文件（i18n / lock / *.d.ts / snapshot / 纯删除）只列文件名，不展开 diff。
 * 退出码：0 成功，1 参数错误，2 git 执行失败。
 */
import { execFileSync } from "child_process";

// ── 参数解析 ──────────────────────────────────────────────

const args = process.argv.slice(2);
let mode = "worktree";
let ref = "";

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--staged") {
    mode = "staged";
  } else if (args[i] === "--commit" && args[i + 1]) {
    mode = "commit";
    ref = args[++i];
  } else if (args[i] === "--range" && args[i + 1]) {
    mode = "range";
    ref = args[++i];
  } else {
    console.error(`未知参数: ${args[i]}`);
    console.error("用法: node diff-with-lines.mjs [--staged | --commit <sha> | --range <a>..<b>]");
    process.exit(1);
  }
}

// ── git diff 命令构造 ─────────────────────────────────────

function diffArgs() {
  switch (mode) {
    case "staged":
      return ["diff", "--cached"];
    case "commit":
      // ^! 等价于 diff 该 commit 与其父；根 commit 无父，git 会报错并以 exit 2 退出
      return ["diff", `${ref}^!`];
    case "range":
      return ["diff", ref];
    default:
      // 工作区全部改动：HEAD 到工作区，覆盖已暂存 + 未暂存
      return ["diff", "HEAD"];
  }
}

function git(gitArgs) {
  return execFileSync("git", gitArgs, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
}

// ── 低价值文件过滤 ───────────────────────────────────────

const LOW_VALUE_PATTERNS = [
  /^src\/strings\//,
  /\/locales\//,
  /\.i18n\./,
  /\.(d\.ts|lock)$/,
  /package-lock\.json$/,
  /yarn\.lock$/,
  /pnpm-lock\.yaml$/,
  /__snapshots__\//,
  /\.(generated|auto)\./,
];

function isLowValue(filePath) {
  return LOW_VALUE_PATTERNS.some((p) => p.test(filePath));
}

// ── diff 行号标注（移植自 review-mr/fetch-mr.mjs） ────────

function annotateDiff(diff) {
  const lines = diff.split("\n");
  let newLine = 0;
  let oldLine = 0;
  const result = [];

  for (const line of lines) {
    const hunkMatch = line.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
    if (hunkMatch) {
      oldLine = parseInt(hunkMatch[1], 10);
      newLine = parseInt(hunkMatch[2], 10);
      result.push(line);
      continue;
    }

    if (line.startsWith("+") && !line.startsWith("+++")) {
      result.push(`+[L${newLine}] ${line.slice(1)}`);
      newLine++;
    } else if (line.startsWith("-") && !line.startsWith("---")) {
      result.push(`-[L${oldLine}] ${line.slice(1)}`);
      oldLine++;
    } else if (line.startsWith("\\")) {
      result.push(line);
    } else if (line.startsWith(" ")) {
      result.push(` [L${newLine}] ${line.slice(1)}`);
      oldLine++;
      newLine++;
    } else {
      // diff header（diff --git / index / @@ 之外的行）原样保留
      result.push(line);
    }
  }

  return result.join("\n");
}

// ── 把整段 diff 按文件切分 ────────────────────────────────

function splitByFile(fullDiff) {
  const blocks = [];
  let current = null;

  for (const line of fullDiff.split("\n")) {
    const header = line.match(/^diff --git a\/(.+?) b\/(.+)$/);
    if (header) {
      if (current) blocks.push(current);
      current = { path: header[2], lines: [line] };
    } else if (current) {
      current.lines.push(line);
    }
  }
  if (current) blocks.push(current);
  return blocks;
}

// ── 主流程 ───────────────────────────────────────────────

function main() {
  let fullDiff;
  try {
    fullDiff = git(diffArgs());
  } catch (err) {
    console.error(`git diff 执行失败: ${err.message}`);
    process.exit(2);
  }

  if (!fullDiff.trim()) {
    console.log("(无变更)");
    return;
  }

  const blocks = splitByFile(fullDiff);
  const key = [];
  const skipped = [];

  for (const b of blocks) {
    if (isLowValue(b.path)) {
      skipped.push(b.path);
    } else {
      key.push(b);
    }
  }

  const out = [];
  out.push(`# Diff（模式: ${mode}${ref ? ` ${ref}` : ""}） — ${key.length} 个关键文件，${skipped.length} 个跳过`);
  out.push("");

  for (const b of key) {
    out.push(`=== ${b.path} ===`);
    out.push(annotateDiff(b.lines.join("\n")));
    out.push("");
  }

  if (skipped.length) {
    out.push("--- 跳过的低价值文件（仅列出，未展开 diff）---");
    for (const p of skipped) out.push(`  ${p}`);
  }

  console.log(out.join("\n"));
}

main();
