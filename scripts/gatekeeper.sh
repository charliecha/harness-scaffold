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

# ────────────────────────────────────────────────
# SECTION 1: 安全检查
# ────────────────────────────────────────────────

# Check 1: 无硬编码密钥
check "no hardcoded secrets" \
    '! grep -rE "(api_key|apikey|api-key|secret|password|token)\s*[:=]\s*\"[^\"]{8,}\"" \
        --include="*.go" \
        --exclude-dir=".git" \
        --exclude-dir="vendor" \
        . 2>/dev/null'

# Check 2: 无裸 fmt.Println（internal/）
check "no bare fmt.Println in internal/" \
    '! grep -rn "fmt\.Println\|fmt\.Printf" ./internal/ 2>/dev/null'

# Check 3: 禁止 panic 进入 internal/
check "no panic in internal/" \
    '! grep -rn "panic(" ./internal/ 2>/dev/null'

# ────────────────────────────────────────────────
# SECTION 2: 静态分析
# ────────────────────────────────────────────────

# Check 4: go vet（golangci-lint 未安装时的兜底）
check_with_output "go vet clean" \
    'go vet ./...'

# Check 5: golangci-lint（已安装时强制，未安装时 FAIL）
if command -v golangci-lint &>/dev/null; then
    check_with_output "golangci-lint clean" \
        'golangci-lint run ./...'
else
    echo -e "${RED}❌ golangci-lint not installed (required: brew install golangci-lint)${NC}"
    FAIL=$((FAIL + 1))
    FAILED_ITEMS+=("golangci-lint not installed")
fi

# Check 6: govulncheck（已安装时运行，未安装时 warning）
if command -v govulncheck &>/dev/null; then
    check_with_output "govulncheck: no known vulnerabilities" \
        'govulncheck ./...'
else
    echo -e "${YELLOW}⚠️  govulncheck not installed — skipping (install: go install golang.org/x/vuln/cmd/govulncheck@latest)${NC}"
fi

# Check 7: deadcode（已安装时运行，未安装时 warning）
if command -v deadcode &>/dev/null; then
    check_with_output "no dead code" \
        'deadcode -test ./... 2>&1 | grep -v "^$" | wc -l | xargs test 0 -eq'
else
    echo -e "${YELLOW}⚠️  deadcode not installed — skipping (install: go install golang.org/x/tools/cmd/deadcode@latest)${NC}"
fi

# ────────────────────────────────────────────────
# SECTION 3: 编译与测试
# ────────────────────────────────────────────────

# Check 8: 编译成功
check_with_output "build succeeds" \
    'go build ./...'

# Check 9: 竞态测试通过
check_with_output "race-free tests pass" \
    'go test -race -count=1 -timeout=60s ./...'

# Check 10: 覆盖率基线 ≥ 80%
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

# ────────────────────────────────────────────────
# SECTION 4: 产物验证
# ────────────────────────────────────────────────

# Check 11: 版本元数据可注入
check_with_output "version metadata injectable" \
    'go build -ldflags="-X main.Version=gate-test" -o /tmp/cs_gate_test ./cmd/server && \
     /tmp/cs_gate_test --version 2>&1 | grep -q "gate-test" && \
     rm -f /tmp/cs_gate_test'

# Check 12: go.mod 幂等
check "go.mod up to date" \
    'cp go.mod /tmp/cs_go_mod_bak && \
     go mod tidy 2>/dev/null && \
     diff -q go.mod /tmp/cs_go_mod_bak && \
     rm -f /tmp/cs_go_mod_bak'

# ────────────────────────────────────────────────
# SECTION 5: 接口冒烟测试
# ────────────────────────────────────────────────

# Check 13: 接口冒烟测试（Validate Skill 脚本化）
check_with_output "smoke tests pass" \
    'bash scripts/smoke_test.sh'

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
