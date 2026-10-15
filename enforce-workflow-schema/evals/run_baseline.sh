#!/bin/bash
# 用法: run_baseline.sh [case_id...]   不带参数则跑 evals.json 里全部用例
# 每个用例在 /tmp/rsi-t5/run/<id>/ 的新 git 仓库里跑一次 claude -p, 结果追加到 baseline-2026-10-15.md。
# 每次调用都会花钱 (单次预算上限见 BUDGET), 先想好要跑哪几条。
HERE="$(cd "$(dirname "$0")" && pwd)"
EVALS="$HERE/evals.json"
GRADER="$HERE/grade_workflow.py"
REPORT="$HERE/baseline-2026-10-15.md"
RUN_ROOT=/tmp/rsi-t5/run
BUDGET=0.8
TIMEOUT=600
CLAUDE=/Users/me/.local/bin/claude
PY=/usr/bin/python3

mkdir -p "$RUN_ROOT"

if [ "$#" -gt 0 ]; then
  IDS="$*"
else
  IDS="$($PY -c "import json,sys;print(' '.join(str(e['id']) for e in json.load(open(sys.argv[1]))['evals']))" "$EVALS")"
fi

field() { # field <id> <key>
  $PY -c "import json,sys;e=[x for x in json.load(open(sys.argv[1]))['evals'] if str(x['id'])==sys.argv[2]][0];print(e[sys.argv[3]])" "$EVALS" "$1" "$2"
}

make_skeleton() { # make_skeleton <dir>
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"
  cat > "$d/README.md" <<'R'
# mini-sync
一个很小的 Python CLI，`python cli.py sync <src> <dst>` 把 src 目录复制到 dst。
R
  cat > "$d/cli.py" <<'R'
import argparse
from sync import sync_dir


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sync")
    s.add_argument("src")
    s.add_argument("dst")
    a = p.parse_args()
    if a.cmd == "sync":
        sync_dir(a.src, a.dst)


if __name__ == "__main__":
    main()
R
  cat > "$d/sync.py" <<'R'
import os
import shutil
import time


def sync_dir(src, dst, retries=3):
    for attempt in range(retries):
        try:
            if os.path.exists(dst):
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
            return
        except OSError:
            time.sleep(1)
    raise RuntimeError("sync failed")
R
  cat > "$d/utils.py" <<'R'
def clamp(x, lo, hi):
    return min(lo, max(x, hi))
R
  # 空的 .workflow/ 代表项目已有该目录传统 (SKILL.md 失败回退: 没有传统会先问用户, 首轮基线因此没落盘)
  mkdir -p "$d/.workflow" && : > "$d/.workflow/.gitkeep"
  ( cd "$d" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm init )
}

[ -f "$REPORT" ] || echo "# enforce-workflow-schema 基线 (2026-10-15)" > "$REPORT"

for id in $IDS; do
  d="$RUN_ROOT/$id"
  ctype="$(field "$id" case_type)"
  prompt="$(field "$id" prompt)"
  make_skeleton "$d"
  out="$d.out.json"; err="$d.err"
  start=$(date +%s)
  ( cd "$d" && exec "$CLAUDE" -p "$prompt" --model sonnet --max-budget-usd "$BUDGET" \
      --permission-mode acceptEdits --strict-mcp-config --no-session-persistence \
      --output-format json --settings '{"disableAllHooks":true}' > "$out" 2> "$err" < /dev/null ) &
  pid=$!
  ( sleep "$TIMEOUT"; kill "$pid" 2>/dev/null ) &
  killer=$!
  wait "$pid"; rc=$?
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
  secs=$(( $(date +%s) - start ))
  cost="$($PY -c "import json,sys;print(json.load(open(sys.argv[1])).get('total_cost_usd','?'))" "$out" 2>/dev/null || echo '?')"

  verdict=FAIL; reason=""
  wf_dirs="$(find "$d/.workflow" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)"
  if [ "$rc" -ne 0 ]; then
    reason="claude 退出码 $rc (143/137 多为超时被杀)"
  elif [ "$ctype" = "should_trigger" ]; then
    if [ -z "$wf_dirs" ]; then
      reason="未生成 .workflow/<task-id>/ (skill 没被触发或没落盘)"
    else
      verdict=PASS
      while IFS= read -r wd; do
        g="$($PY "$GRADER" "$wd" 2>&1)"; grc=$?
        if [ "$grc" -ne 0 ]; then
          verdict=FAIL; reason="$reason $(basename "$wd"): $(echo "$g" | grep '^FAIL' | tr '\n' ';')"
        fi
      done <<< "$wf_dirs"
    fi
  else
    if [ -n "$wf_dirs" ]; then reason="不该生成 .workflow/<task-id>/ 却生成了"; else verdict=PASS; fi
  fi

  {
    echo ""
    echo "### 用例 $id $(field "$id" name) ($ctype)"
    echo "- 结果: $verdict"
    echo "- 耗时: ${secs}s, 花费: \$${cost}, 退出码: $rc"
    [ -n "$reason" ] && echo "- 失败原因: $reason"
    echo "- 产物目录: $d (输出 $out)"
  } >> "$REPORT"
  echo "case $id: $verdict ${secs}s cost=$cost ${reason}"
done
