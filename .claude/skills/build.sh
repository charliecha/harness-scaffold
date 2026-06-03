#!/bin/bash
# skills/build.sh — Build Skill（可执行版本）
# 替代 skills/build.md，每步确定性执行，不依赖 AI 解读
# 退出码 0 = PASSED，非 0 = FAILED

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}"; echo -e "${RED}   $2${NC}"; exit 1; }

echo "=== Build Skill ==="

# Step 1: 同步并验证依赖
echo "Step 1: go mod tidy + verify"
go mod tidy 2>&1 || fail "go mod tidy" "依赖同步失败"
go mod verify 2>&1 | grep -q "all modules verified" || fail "go mod verify" "模块校验失败"
ok "dependencies synced and verified"

# Step 2: 静态分析
echo "Step 2: golangci-lint"
if ! command -v golangci-lint &>/dev/null; then
    fail "golangci-lint" "未安装，请执行: brew install golangci-lint"
fi
OUTPUT=$(golangci-lint run ./... 2>&1)
if [ $? -ne 0 ]; then
    fail "golangci-lint" "$OUTPUT"
fi
ok "golangci-lint clean"

# Step 3: 编译（注入版本元数据）
echo "Step 3: go build"
VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
BUILDTIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p bin
go build \
    -ldflags="-X main.Version=${VERSION} -X main.Commit=${COMMIT} -X main.BuildTime=${BUILDTIME}" \
    -o bin/crypto-snapshot \
    ./cmd/server 2>&1 || fail "go build" "编译失败"
ok "build succeeded: bin/crypto-snapshot"

# Step 4: 验证版本元数据注入
echo "Step 4: version metadata"
OUTPUT=$(./bin/crypto-snapshot --version 2>&1)
echo "$OUTPUT" | grep -q "version=" || fail "version metadata" "版本信息未注入: $OUTPUT"
echo "$OUTPUT" | grep -q "commit=" || fail "version metadata" "Commit 信息未注入: $OUTPUT"
ok "version metadata injected: $OUTPUT"

echo ""
echo -e "${GREEN}Build Skill: PASSED${NC}"
