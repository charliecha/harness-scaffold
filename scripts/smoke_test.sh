#!/bin/bash
# scripts/smoke_test.sh — 接口冒烟测试（对应 Validate Skill）
# 启动服务，验证所有端点响应正确，退出码 0 = PASSED

set -uo pipefail

_d="$(cd "$(dirname "$0")" && pwd)"
while [ "$_d" != "/" ] && [ ! -f "$_d/.harness/lib.sh" ]; do _d="$(dirname "$_d")"; done
[ -f "$_d/.harness/lib.sh" ] || { echo "harness: .harness/lib.sh not found upward from $0" >&2; exit 1; }
source "$_d/.harness/lib.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0
SERVER_PID=""
BINARY="${1:-./bin/$(harness_get artifact_name)}"

cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    lsof -ti:8080 | xargs kill -9 2>/dev/null || true
}
trap cleanup EXIT

# ── 启动前清理端口 ────────────────────────────────
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
sleep 0.3

# ── 二进制必须已构建好（构建是 build skill 的责任）─
if [ ! -f "$BINARY" ]; then
    echo -e "${RED}❌ binary not found: $BINARY${NC}"
    echo "请先运行: bash .claude/skills/build.sh"
    exit 1
fi

# ── 启动服务 ──────────────────────────────────────
"$BINARY" --rate-limit 1000 --burst 1000 &>/tmp/cs_smoke_server.log &
SERVER_PID=$!
# 等待服务就绪
for i in $(seq 1 10); do
    curl -sf http://localhost:8080/health &>/dev/null && break
    sleep 0.3
done

smoke() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "${GREEN}✅ ${name}${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ ${name}${NC}"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Smoke Tests ==="

# ── /health ───────────────────────────────────────
smoke "/health returns 200" \
    'curl -sf http://localhost:8080/health | grep -q "ok"'

smoke "/health status field" \
    'curl -sf http://localhost:8080/health | python3 -c "import sys,json; d=json.load(sys.stdin); assert d[\"status\"]==\"ok\""'

# ── /version ──────────────────────────────────────
smoke "/version returns 200" \
    'curl -sf http://localhost:8080/version | grep -q "version"'

smoke "/version has commit field" \
    'curl -sf http://localhost:8080/version | python3 -c "import sys,json; d=json.load(sys.stdin); assert \"commit\" in d"'

# ── /snapshot ─────────────────────────────────────
smoke "/snapshot missing coin returns 400" \
    '[ "$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/snapshot/)" = "400" ]'

smoke "/snapshot invalid coin does not return 500" \
    '[ "$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/snapshot/zzz_invalid_coin_xyz)" != "500" ]'

# ── /metrics ──────────────────────────────────────
smoke "/metrics returns 200" \
    'curl -sf http://localhost:8080/metrics'

smoke "/metrics returns JSON object" \
    'curl -sf http://localhost:8080/metrics | python3 -c "import sys,json; json.load(sys.stdin)"'

smoke "/metrics does not count itself (NFR-01)" \
    '! curl -sf http://localhost:8080/metrics | python3 -c "import sys,json; d=json.load(sys.stdin); assert \"/metrics\" in d"'

# 发几个请求，再验证计数递增
curl -sf http://localhost:8080/health &>/dev/null
curl -sf http://localhost:8080/health &>/dev/null
smoke "/metrics health counter increments" \
    'curl -sf http://localhost:8080/metrics | python3 -c "
import sys,json
d=json.load(sys.stdin)
assert \"/health\" in d, \"/health key missing\"
assert d[\"/health\"][\"total_requests\"] >= 2, f\"expected >=2, got {d[\"/health\"][\"total_requests\"]}\"
"'

# ── 限流 429 ──────────────────────────────────────
# 用极低 rate 的独立进程验证 429
kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
sleep 0.5  # 等待端口释放
"$BINARY" --rate-limit 0.001 --burst 1 &>/tmp/cs_smoke_rl.log &
SERVER_PID=$!
for i in $(seq 1 20); do
    curl -sf http://localhost:8080/health &>/dev/null && break
    sleep 0.3
done

curl -sf http://localhost:8080/snapshot/bitcoin &>/dev/null  # 消耗 burst
smoke "/snapshot rate limit returns 429" \
    '[ "$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/snapshot/bitcoin)" = "429" ]'

smoke "/snapshot 429 body is correct" \
    'curl -s http://localhost:8080/snapshot/bitcoin | grep -q "rate limit exceeded"'

echo ""
echo "=== Result: ${PASS} passed, ${FAIL} failed ==="

[ "$FAIL" -eq 0 ] && echo -e "${GREEN}SMOKE: PASSED${NC}" && exit 0
echo -e "${RED}SMOKE: FAILED${NC}" && exit 1
