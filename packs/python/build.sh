#!/bin/bash
# .harness/packs/python/build.sh — Python Build Skill 实现
# 退出码 0 = PASSED，非 0 = FAILED

set -uo pipefail
source "$(dirname "$0")/../../lib.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; echo -e "${RED}   $2${NC}"; exit 1; }

echo "=== Build Skill (python) ==="

# Step 1: 依赖检查（pyproject.toml 存在）
echo "Step 1: pyproject.toml"
[ -f pyproject.toml ] || fail "pyproject.toml" "未找到 pyproject.toml"
ok "pyproject.toml present"

# Step 2: 静态分析（ruff）
echo "Step 2: ruff check"
if ! command -v ruff &>/dev/null; then
    fail "ruff" "未安装，请执行: pip install ruff"
fi
OUTPUT=$(ruff check . 2>&1)
if [ $? -ne 0 ]; then
    fail "ruff" "$OUTPUT"
fi
ok "ruff clean"

# Step 3: 语法编译验证（py_compile 全部 .py 文件）
echo "Step 3: py_compile"
OUTPUT=$(python3 -m compileall -q . 2>&1)
if [ $? -ne 0 ]; then
    fail "py_compile" "$OUTPUT"
fi
ok "all .py files compile"

echo ""
echo -e "${GREEN}Build Skill: PASSED${NC}"
