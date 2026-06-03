#!/bin/bash
# scripts/gatekeeper.sh — Layer 5: 硬性安检闸门
# 守门人脚本：客观验证，不接受主观豁免
# 退出码 0 = PASSED，非 0 = FAILED（不得向前推进）

set -uo pipefail

PASS=0
FAIL=0
FAILED_ITEMS=()

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✅ ${name}${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ ${name}${NC}"
        FAIL=$((FAIL + 1))
        FAILED_ITEMS+=("$name")
    fi
}

check_with_output() {
    local name="$1"
    local cmd="$2"
    local output
    if output=$(eval "$cmd" 2>&1); then
        echo -e "${GREEN}✅ ${name}${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ ${name}${NC}"
        echo -e "${YELLOW}   Output: ${output}${NC}"
        FAIL=$((FAIL + 1))
        FAILED_ITEMS+=("$name")
    fi
}

echo "============================================"
echo "  Gatekeeper: crypto-snapshot"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"
echo ""

# ── Check 1: 无硬编码密钥 ──────────────────────
check "no hardcoded secrets" \
    '! grep -rE "(api_key|apikey|api-key|secret|password|token)\s*[:=]\s*\"[^\"]{8,}\"" \
        --include="*.go" \
        --exclude-dir=".git" \
        --exclude-dir="vendor" \
        . 2>/dev/null'

# ── Check 2: 无裸 fmt.Println（internal/）────────
check "no bare fmt.Println in internal/" \
    '! grep -rn "fmt\.Println\|fmt\.Printf" ./internal/ 2>/dev/null'

# ── Check 3: golangci-lint 零警告 ─────────────────
if command -v golangci-lint &>/dev/null; then
    check_with_output "golangci-lint clean" \
        'golangci-lint run ./...'
else
    echo -e "${YELLOW}⚠️  golangci-lint not installed — skipping (install: brew install golangci-lint)${NC}"
fi

# ── Check 4: 编译成功 ──────────────────────────
check_with_output "build succeeds" \
    'go build ./...'

# ── Check 5: 竞态测试通过 ─────────────────────
check_with_output "race-free tests pass" \
    'go test -race -count=1 -timeout=60s ./...'

# ── Check 6: 覆盖率基线 ≥ 80% ──────────────────
echo -n "   Measuring coverage... "
COV_OUTPUT=$(go test -coverprofile=/tmp/cs_gatekeeper_cov.out -covermode=atomic ./internal/... 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ coverage check: test run failed${NC}"
    FAIL=$((FAIL + 1))
    FAILED_ITEMS+=("coverage >= 80%")
else
    COVERAGE=$(go tool cover -func=/tmp/cs_gatekeeper_cov.out 2>/dev/null | \
               grep "^total:" | awk '{print $3}' | tr -d '%')
    if [ -z "$COVERAGE" ]; then
        echo -e "${RED}❌ coverage check: could not parse coverage${NC}"
        FAIL=$((FAIL + 1))
        FAILED_ITEMS+=("coverage >= 80%")
    elif awk "BEGIN {exit !($COVERAGE >= 80)}"; then
        echo -e "${GREEN}✅ coverage: ${COVERAGE}% (≥ 80%)${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ coverage: ${COVERAGE}% (< 80% baseline)${NC}"
        FAIL=$((FAIL + 1))
        FAILED_ITEMS+=("coverage >= 80% (got ${COVERAGE}%)")
    fi
fi

# ── Check 7: 版本元数据可注入 ─────────────────
check_with_output "version metadata injectable" \
    'go build -ldflags="-X main.Version=gate-test" -o /tmp/cs_gate_test ./cmd/server && \
     /tmp/cs_gate_test --version 2>&1 | grep -q "gate-test" && \
     rm -f /tmp/cs_gate_test'

# ── Check 8: go mod tidy 幂等（无未提交变更）───
check "go.mod up to date" \
    'cp go.mod /tmp/cs_go_mod_bak && \
     go mod tidy 2>/dev/null && \
     diff -q go.mod /tmp/cs_go_mod_bak && \
     rm -f /tmp/cs_go_mod_bak'

echo ""
echo "============================================"
echo "  Result: ${PASS} passed, ${FAIL} failed"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo -e "${RED}GATE: FAILED — 以下检查未通过，不得推进到下一阶段：${NC}"
    for item in "${FAILED_ITEMS[@]}"; do
        echo -e "${RED}  • ${item}${NC}"
    done
    echo ""
    echo "修复上述问题后，重新运行此脚本。"
    exit 1
fi

echo ""
echo -e "${GREEN}GATE: PASSED — 可进入下一阶段（QA 审查）${NC}"
exit 0
