#!/bin/bash
# .harness/packs/python/test.sh — Python Test Skill 实现
# 退出码 0 = PASSED，非 0 = FAILED

set -uo pipefail
source "$(dirname "$0")/../../lib.sh"

THRESHOLD=$(harness_get coverage_threshold)

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; echo -e "${RED}   $2${NC}"; exit 1; }

echo "=== Test Skill (python) ==="

# Step 1: 运行测试 + 收集覆盖率
echo "Step 1: pytest with coverage"
if ! command -v pytest &>/dev/null; then
    fail "pytest" "未安装，请执行: pip install pytest pytest-cov"
fi

# 使用 pytest-cov 一次性运行：测试 + 覆盖率
OUTPUT=$(pytest --cov=. --cov-report=term --cov-fail-under="$THRESHOLD" -q 2>&1)
EXITCODE=$?
echo "$OUTPUT"
if [ $EXITCODE -ne 0 ]; then
    # 区分测试失败 vs 覆盖率不足
    if echo "$OUTPUT" | grep -q "FAIL Required test coverage"; then
        fail "coverage baseline" "覆盖率低于 ${THRESHOLD}% 基线"
    else
        fail "tests" "测试失败"
    fi
fi
ok "all tests passed (coverage ≥ ${THRESHOLD}%)"

echo ""
echo -e "${GREEN}Test Skill: PASSED${NC}"
