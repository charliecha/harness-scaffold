#!/bin/bash
# .harness/packs/go/test.sh — Go Test Skill 实现
# 由 .claude/skills/test.sh dispatcher 调用
# 退出码 0 = PASSED，非 0 = FAILED

set -uo pipefail

source "$(git rev-parse --show-toplevel)/.harness/lib.sh"

THRESHOLD=$(harness_get coverage_threshold)

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; echo -e "${RED}   $2${NC}"; exit 1; }

echo "=== Test Skill (go) ==="

# Step 1: 竞态检测下运行全部测试
echo "Step 1: go test -race"
go test -race -count=1 -timeout=60s ./... 2>&1 || fail "race-free tests" "竞态测试失败"
ok "all tests passed (race detector clean)"

# Step 2: 生成覆盖率报告
echo "Step 2: coverage"
go test -coverprofile=coverage.out -covermode=atomic ./internal/... 2>&1 || fail "coverage" "覆盖率测试运行失败"

# Step 3: 验证覆盖率基线
COVERAGE=$(go tool cover -func=coverage.out 2>/dev/null | grep "^total:" | awk '{print $3}' | tr -d '%')
if [ -z "$COVERAGE" ]; then
    fail "coverage baseline" "无法解析覆盖率数据"
fi

if awk "BEGIN {exit !($COVERAGE >= $THRESHOLD)}"; then
    ok "coverage: ${COVERAGE}% (≥ ${THRESHOLD}%)"
else
    fail "coverage baseline" "覆盖率 ${COVERAGE}% 低于 ${THRESHOLD}% 基线"
fi

echo ""
echo -e "${GREEN}Test Skill: PASSED (coverage: ${COVERAGE}%)${NC}"
