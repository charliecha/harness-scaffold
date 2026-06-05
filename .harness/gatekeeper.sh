#!/bin/bash
# .harness/gatekeeper.sh — Layer 5: 硬性安检闸门（骨架）
# 通用骨架 + 语言特定检查（delegate 到 .harness/packs/<lang>/gatekeeper-checks.sh）
# 退出码 0 = PASSED，非 0 = FAILED（不得向前推进）

set -uo pipefail

source "$(git rev-parse --show-toplevel)/.harness/lib.sh"

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

PROJECT=$(basename "$(git rev-parse --show-toplevel)")
echo "============================================"
echo "  Gatekeeper: ${PROJECT} ($(harness_lang))"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================"
echo ""

# ────────────────────────────────────────────────
# 语言特定检查（delegate 到 pack）
# pack 复用本文件的 check / check_with_output / PASS / FAIL / FAILED_ITEMS / 颜色变量
# ────────────────────────────────────────────────
PACK_CHECKS=$(harness_require_pack gatekeeper-checks.sh) || exit 1
source "$PACK_CHECKS"

# ────────────────────────────────────────────────
# 通用：接口冒烟测试（项目级脚本）
# ────────────────────────────────────────────────
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
