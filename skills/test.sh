#!/bin/bash
# skills/test.sh — Test Skill（可执行版本）
# 替代 skills/test.md，每步确定性执行
# 退出码 0 = PASSED，非 0 = FAILED

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; echo -e "${RED}   $2${NC}"; exit 1; }

echo "=== Test Skill ==="

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

if awk "BEGIN {exit !($COVERAGE >= 80)}"; then
    ok "coverage: ${COVERAGE}% (≥ 80%)"
else
    fail "coverage baseline" "覆盖率 ${COVERAGE}% 低于 80% 基线"
fi

echo ""
echo -e "${GREEN}Test Skill: PASSED (coverage: ${COVERAGE}%)${NC}"
