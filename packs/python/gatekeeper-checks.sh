#!/bin/bash
# .harness/packs/python/gatekeeper-checks.sh — Python 专属 gatekeeper 检查
# 由 .harness/gatekeeper.sh source。复用骨架的 check/check_with_output/PASS/FAIL/颜色。

# ────────────────────────────────────────────────
# SECTION: 源码安全检查（Python）
# ────────────────────────────────────────────────

check "no hardcoded secrets" \
    '! grep -rE "(api_key|apikey|api-key|secret|password|token)\s*[:=]\s*\"[^\"]{8,}\"" \
        --include="*.py" \
        --exclude-dir=".git" \
        --exclude-dir=".venv" \
        --exclude-dir="venv" \
        --exclude-dir="__pycache__" \
        . 2>/dev/null'

# 无裸 print()（除非有显式 noqa 注释豁免）
check "no bare print() in non-test code" \
    '! grep -rn --include="*.py" --exclude="test_*.py" --exclude="*_test.py" \
        --exclude-dir=".git" --exclude-dir=".venv" --exclude-dir="venv" \
        --exclude-dir="__pycache__" \
        "^[^#]*\bprint(" . 2>/dev/null | grep -v "# noqa"'

# ────────────────────────────────────────────────
# SECTION: 静态分析
# ────────────────────────────────────────────────

if command -v ruff &>/dev/null; then
    check_with_output "ruff clean" 'ruff check .'
else
    echo -e "${RED}❌ ruff not installed (required: pip install ruff)${NC}"
    FAIL=$((FAIL + 1))
    FAILED_ITEMS+=("ruff not installed")
fi

if command -v mypy &>/dev/null; then
    check_with_output "mypy clean" 'mypy --ignore-missing-imports .'
else
    echo -e "${YELLOW}⚠️  mypy not installed — skipping (install: pip install mypy)${NC}"
fi

# ────────────────────────────────────────────────
# SECTION: 编译与测试
# ────────────────────────────────────────────────

check_with_output "py_compile succeeds" \
    'python3 -m compileall -q .'

# pytest + coverage 一次性运行（阈值从 .harness-config.json）
THRESHOLD=$(harness_get coverage_threshold)
check_with_output "pytest passes with coverage >= ${THRESHOLD}%" \
    "pytest --cov=. --cov-fail-under=${THRESHOLD} -q"
