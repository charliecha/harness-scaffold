#!/bin/bash
# scripts/check-phase.sh — Hook 拦截器
# 由 Claude Code PreToolUse hook 调用
# 用途：在 git push 前检查 gatekeeper 是否通过
# 退出码 0 = 放行，非 0 = 拦截

STATE_FILE=".workflow-state.json"

# 不在项目目录内则直接放行
[ ! -f "$STATE_FILE" ] && exit 0

TOOL_INPUT="${1:-}"

# ── 只拦截 git push ────────────────────────────────
# 检查输入是否包含 git push
if ! echo "$TOOL_INPUT" | grep -q "git push"; then
    exit 0
fi

# ── 读取状态 ───────────────────────────────────────
PHASE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('phase','idle'))" 2>/dev/null || echo "idle")
GATE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('gatekeeper_passed', False))" 2>/dev/null || echo "False")
FEATURE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('feature',''))" 2>/dev/null || echo "")

# idle 或 complete 状态允许 push（非开发中）
if [ "$PHASE" = "idle" ] || [ "$PHASE" = "complete" ]; then
    exit 0
fi

# ── 开发中：检查 gatekeeper ────────────────────────
if [ "$GATE" != "True" ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         🚫  Git Push 被拦截                      ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "  当前功能  : $FEATURE"
    echo "  当前阶段  : $PHASE"
    echo "  Gatekeeper: ❌ 未通过"
    echo ""
    echo "  必须先通过安检才能 push："
    echo ""
    echo "    1. bash scripts/gatekeeper.sh"
    echo "    2. bash scripts/workflow.sh gate-pass"
    echo "    3. git push ..."
    echo ""
    exit 1
fi

# gatekeeper 已通过，放行
echo "  ✅ Gatekeeper 已通过，允许 push（feature: $FEATURE）"
exit 0
