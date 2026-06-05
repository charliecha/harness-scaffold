#!/bin/bash
# .harness/packs/go/gatekeeper-checks.sh — Go 专属 gatekeeper 检查
# 由 .harness/gatekeeper.sh 在通用 helper（check/check_with_output）已定义的环境中 source
# 入参（来自骨架）：函数 check, check_with_output；变量 PASS, FAIL, FAILED_ITEMS

# ────────────────────────────────────────────────
# SECTION: 源码安全检查（Go）
# ────────────────────────────────────────────────

# 无硬编码密钥（Go 源文件）
check "no hardcoded secrets" \
    '! grep -rE "(api_key|apikey|api-key|secret|password|token)\s*[:=]\s*\"[^\"]{8,}\"" \
        --include="*.go" \
        --exclude-dir=".git" \
        --exclude-dir="vendor" \
        . 2>/dev/null'

# 无裸 fmt.Println（internal/）
check "no bare fmt.Println in internal/" \
    '! grep -rn "fmt\.Println\|fmt\.Printf" ./internal/ 2>/dev/null'

# 禁止 panic 进入 internal/
check "no panic in internal/" \
    '! grep -rn "panic(" ./internal/ 2>/dev/null'

# ────────────────────────────────────────────────
# SECTION: 静态分析
# ────────────────────────────────────────────────

# go vet
check_with_output "go vet clean" \
    'go vet ./...'

# golangci-lint（已安装时强制，未安装时 FAIL）
if command -v golangci-lint &>/dev/null; then
    check_with_output "golangci-lint clean" \
        'golangci-lint run ./...'
else
    echo -e "${RED}❌ golangci-lint not installed (required: brew install golangci-lint)${NC}"
    FAIL=$((FAIL + 1))
    FAILED_ITEMS+=("golangci-lint not installed")
fi

# govulncheck（已安装时运行，未安装时 warning）
if command -v govulncheck &>/dev/null; then
    check_with_output "govulncheck: no known vulnerabilities" \
        'govulncheck ./...'
else
    echo -e "${YELLOW}⚠️  govulncheck not installed — skipping (install: go install golang.org/x/vuln/cmd/govulncheck@latest)${NC}"
fi

# deadcode（已安装时运行，未安装时 warning）
if command -v deadcode &>/dev/null; then
    check_with_output "no dead code" \
        'deadcode -test ./... 2>&1 | grep -v "^$" | wc -l | xargs test 0 -eq'
else
    echo -e "${YELLOW}⚠️  deadcode not installed — skipping (install: go install golang.org/x/tools/cmd/deadcode@latest)${NC}"
fi

# ────────────────────────────────────────────────
# SECTION: 编译与测试
# ────────────────────────────────────────────────

check_with_output "build succeeds" \
    'go build ./...'

check_with_output "race-free tests pass" \
    'go test -race -count=1 -timeout=60s ./...'

# 覆盖率基线（阈值来自 .harness/config.json）
THRESHOLD=$(harness_get coverage_threshold)
echo -n "   Measuring coverage... "
COV_OUTPUT=$(go test -coverprofile=/tmp/harness_gatekeeper_cov.out -covermode=atomic ./internal/... 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ coverage check: test run failed${NC}"
    FAIL=$((FAIL + 1))
    FAILED_ITEMS+=("coverage >= ${THRESHOLD}%")
else
    COVERAGE=$(go tool cover -func=/tmp/harness_gatekeeper_cov.out 2>/dev/null | \
               grep "^total:" | awk '{print $3}' | tr -d '%')
    if [ -z "$COVERAGE" ]; then
        echo -e "${RED}❌ coverage check: could not parse coverage${NC}"
        FAIL=$((FAIL + 1))
        FAILED_ITEMS+=("coverage >= ${THRESHOLD}%")
    elif awk "BEGIN {exit !($COVERAGE >= $THRESHOLD)}"; then
        echo -e "${GREEN}✅ coverage: ${COVERAGE}% (≥ ${THRESHOLD}%)${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ coverage: ${COVERAGE}% (< ${THRESHOLD}% baseline)${NC}"
        FAIL=$((FAIL + 1))
        FAILED_ITEMS+=("coverage >= ${THRESHOLD}% (got ${COVERAGE}%)")
    fi
fi

# ────────────────────────────────────────────────
# SECTION: 产物验证
# ────────────────────────────────────────────────

# 版本元数据可注入
check_with_output "version metadata injectable" \
    'go build -ldflags="-X main.Version=gate-test" -o /tmp/harness_gate_test ./cmd/server && \
     /tmp/harness_gate_test --version 2>&1 | grep -q "gate-test" && \
     rm -f /tmp/harness_gate_test'

# go.mod 幂等
check "go.mod up to date" \
    'cp go.mod /tmp/harness_go_mod_bak && \
     go mod tidy 2>/dev/null && \
     diff -q go.mod /tmp/harness_go_mod_bak && \
     rm -f /tmp/harness_go_mod_bak'
