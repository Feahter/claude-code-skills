#!/usr/bin/env bash
# 三方测试 skill 的入口路由同步门禁。
#
# 事实源：test-strategist/references/ownership.md 的「问法路由」节。
# description 是入口文本、必须自包含，所以三份 SKILL.md 各留一份精简分流句——
# 这是「绝不复制正文」的唯一例外，代价就是需要本脚本兜住漂移。
#
# 检查项：
#   1. 三份 description 都写全了另外两方（不允许单向指路）
#   2. 三份 description 都带「三方分流」锚点
#   3. 归 playbook 独占的入口词（选择器 / Page Object / flaky / 分层）不得出现在
#      另两方的「该用本 skill」正面声称里，只能出现在分流或不负责句中
#   4. ownership.md 的「问法路由」节与消歧表仍在
#
# 用法：bash ~/.claude/skills/test-strategist/scripts/check-routing-sync.sh
# 退出码：0 全通过；1 有漂移

set -uo pipefail

SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
OWNERSHIP="$SKILLS_DIR/test-strategist/references/ownership.md"
FAIL=0

fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }

# 取 SKILL.md 的 frontmatter description 块（第一对 --- 之间，去掉 name 行）
desc_of() {
  awk '/^---$/{n++; next} n==1' "$1" | grep -v '^name:'
}

# description 里"正面声称"的行：排除分流句与不负责句
positive_lines_of() {
  desc_of "$1" | grep -v '三方分流' | grep -v '不负责' | grep -v '^ *不适用' | grep -v '入口消歧'
}

echo "== 1/4 三方分流写全 =="
# 关联数组要 bash 4，macOS 自带 3.2，用 case 保持可移植
others_of() {
  case "$1" in
    playbook)         echo "test-strategist e2e-test-quality" ;;
    test-strategist)  echo "playbook e2e-test-quality" ;;
    e2e-test-quality) echo "playbook test-strategist" ;;
  esac
}
for skill in playbook test-strategist e2e-test-quality; do
  f="$SKILLS_DIR/$skill/SKILL.md"
  if [[ ! -f $f ]]; then fail "$skill/SKILL.md 不存在"; continue; fi
  d=$(desc_of "$f")
  for other in $(others_of "$skill"); do
    if grep -q -- "$other" <<<"$d"; then
      pass "$skill description 提到 $other"
    else
      fail "$skill description 未提到 $other —— 单向指路，被先扫到时看不到完整分流"
    fi
  done
done

echo "== 2/4 分流锚点存在 =="
for skill in playbook test-strategist e2e-test-quality; do
  f="$SKILLS_DIR/$skill/SKILL.md"
  [[ -f $f ]] || continue
  if desc_of "$f" | grep -q '三方分流'; then
    pass "$skill 带「三方分流」锚点"
  else
    fail "$skill description 缺「三方分流」锚点"
  fi
done

echo "== 3/4 playbook 独占入口词未被另两方正面声称 =="
# 这四个概念的判定权归 playbook（见 ownership.md 决策权矩阵）
# 用换行分隔而非数组：macOS bash 3.2 在 set -u 下展开数组会误报 unbound
PLAYBOOK_ONLY='选择器
Page Object
flaky
分层归属'
for skill in test-strategist e2e-test-quality; do
  f="$SKILLS_DIR/$skill/SKILL.md"
  [[ -f $f ]] || continue
  pos=$(positive_lines_of "$f")
  while IFS= read -r term; do
    [[ -n $term ]] || continue
    if grep -qF -- "$term" <<<"$pos"; then
      fail "$skill 在正面声称里出现「${term}」——该词归 playbook，只能写在分流或不负责句中"
    else
      pass "$skill 未越界声称「${term}」"
    fi
  done <<<"$PLAYBOOK_ONLY"
done

echo "== 4/4 事实源小节存在 =="
if [[ -f $OWNERSHIP ]]; then
  for anchor in '## 问法路由' '歧义问法消歧表' 'description 层的同步纪律'; do
    if grep -qF -- "$anchor" "$OWNERSHIP"; then
      pass "ownership.md 含「${anchor}」"
    else
      fail "ownership.md 缺「${anchor}」—— 事实源被删，description 分流句将无处对账"
    fi
  done
else
  fail "ownership.md 不存在：$OWNERSHIP"
fi

echo
if [[ $FAIL -eq 0 ]]; then
  echo "路由同步检查通过。"
else
  echo "存在漂移。按 ownership.md 的「问法路由」节收敛后重跑。"
fi
exit $FAIL
