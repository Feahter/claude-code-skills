#!/usr/bin/env bash
# 门禁脚本的回归自测。改 validate-package.sh 之后必须跑一次。
# 覆盖边界行为：quick 模式、纯 accept 例外、证据封顶临界、组合处置、oracle 长度下限。
# 用法：selftest-gate.sh          退出码 0 = 全部符合预期
set -uo pipefail

GATE="$(cd "$(dirname "$0")" && pwd)/validate-package.sh"
TMPF="$(mktemp -t ts-gate-XXXXXX).yaml"
trap 'rm -f "$TMPF"' EXIT

PASS=0; FAIL=0

# check <用例名> <预期退出码> [预期输出含的关键词]；yaml 从 stdin 读
check() {
  local name="$1" want="$2" kw="${3:-}"
  cat > "$TMPF"
  local out code
  out="$(bash "$GATE" "$TMPF" 2>&1)"; code=$?
  local ok=1
  [ "$code" -eq "$want" ] || ok=0
  if [ -n "$kw" ] && ! grep -q -- "$kw" <<<"$out"; then ok=0; fi
  if [ "$ok" -eq 1 ]; then
    PASS=$((PASS+1)); printf '  ✅ %s\n' "$name"
  else
    FAIL=$((FAIL+1))
    printf '  ❌ %s\n     期望退出码 %s' "$name" "$want"
    [ -n "$kw" ] && printf '，输出含「%s」' "$kw"
    printf '\n     实际退出码 %s：%s\n' "$code" "$(head -3 <<<"$out" | tr '\n' ' ')"
  fi
}

echo "门禁回归自测"
echo

check "quick 模式可省略三分清单与反证复核" 0 <<'EOF'
scope: 小改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: test
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "full 模式缺三分清单要拦" 1 "evidence_summary" <<'EOF'
scope: 改动
input_kind: diff
mode: full
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: test
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "P2 不强制验证义务" 0 <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: monitor
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "P1 缺验证义务要拦" 1 "必须有 validation_obligation" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P1
    disposition: test
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "P1 义务缺 observable 要拦" 1 "observable" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P1
    disposition: test
    validation_obligation:
      precondition: 前置条件
      oracle: 记录数 == 1
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "纯 accept 的 P0 免义务（有 owner）" 0 <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 不可逆资金损失
    priority: P0
    disposition: accept
    owner: 张三
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "accept 缺 owner 要拦" 1 "owner" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: accept
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "证据封顶：no-evidence + P2 放行" 0 <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: assumption-no-evidence
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: explore
    confidence: low
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "证据封顶：no-evidence + P1 要拦" 1 "证据封顶" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: assumption-no-evidence
    failure_mode: 具体故障描述
    impact: 后果
    priority: P1
    disposition: test
    validation_obligation:
      precondition: 前置条件
      observable: 观察项
      oracle: 记录数 == 1
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "三段组合处置 test-and-monitor-and-design-fix 合法" 0 <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: test-and-monitor-and-design-fix
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "非法 disposition 要拦" 1 "未知值" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: todo-later
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "并行 agent 的字母前缀 risk_id 合法（R-A01）" 0 <<'EOF'
scope: 模块 A 的扫描片段
input_kind: diff
mode: quick
risks:
  - risk_id: R-A01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: test
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "risk_id 缺数字要拦（R-AB）" 1 "应形如" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-AB
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: test
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "非法 confidence 要拦" 1 "confidence" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: test
    confidence: very-high
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "oracle 过短要拦" 1 "过短" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P1
    disposition: test
    validation_obligation:
      precondition: 前置条件
      observable: 观察项
      oracle: n==1
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "risks 为空要拦" 1 "risks" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks: []
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "not_covered 缺 reason 要拦" 1 "not_covered" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P2
    disposition: test
not_covered:
  - item: 只有条目没写理由
EOF

check "risk_id 重复要拦" 1 "重复" <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述甲
    impact: 后果
    priority: P2
    disposition: test
  - risk_id: R-01
    evidence: src/b.ts:2
    failure_mode: 具体故障描述乙
    impact: 后果
    priority: P3
    disposition: explore
not_covered:
  - item: 某项
    reason: 某原因
EOF

check "block scalar 写含冒号的 oracle 不炸" 0 <<'EOF'
scope: 改动
input_kind: diff
mode: quick
risks:
  - risk_id: R-01
    evidence: src/a.ts:1
    failure_mode: 具体故障描述
    impact: 后果
    priority: P1
    disposition: test
    validation_obligation:
      precondition: 执行 npm test
      observable: 输出与退出码
      oracle: |
        输出含 Tests: N passed，且 "<" 之后首字符不为 "+"
not_covered:
  - item: 某项
    reason: 某原因
EOF

echo
printf '通过 %d，失败 %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
