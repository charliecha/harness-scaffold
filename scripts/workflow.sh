#!/bin/bash
# scripts/workflow.sh — 状态机管理器
# 读写 .workflow-state.json，驱动六阶段工作流
# 用法：
#   workflow.sh status              — 查看当前状态
#   workflow.sh start <feature>     — 启动新功能开发（进入 Phase 1）
#   workflow.sh advance <phase>     — 推进到指定阶段（需满足前置条件）
#   workflow.sh set-artifact <key> <path> — 记录产物路径
#   workflow.sh gate-pass           — 标记 gatekeeper 通过
#   workflow.sh gate-reset          — 重置 gatekeeper 状态（代码有变更时自动调用）
#   workflow.sh complete            — 完成当前功能，回到 idle
#   workflow.sh reset               — 强制重置（紧急用）

set -uo pipefail

STATE_FILE=".workflow-state.json"

# Only use color when stdout is a real terminal (not piped or redirected)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    NC=''
fi

PHASES=("idle" "requirements" "architecture" "dev" "gatekeeper" "qa-review" "pm-acceptance" "complete")

# ── 工具函数 ──────────────────────────────────────

get_field() {
    python3 -c "import json,sys; d=json.load(open('$STATE_FILE')); print(d.get('$1',''))"
}

set_field() {
    local key="$1"
    local value="$2"
    python3 -c "
import json
with open('$STATE_FILE', 'r') as f:
    d = json.load(f)
d['$key'] = '$value'
with open('$STATE_FILE', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print('updated $key=$value')
"
}

set_bool_field() {
    local field="$1"
    local val="$2"
    # Convert shell true/false to Python True/False
    local py_val
    if [ "$val" = "true" ]; then py_val="True"; else py_val="False"; fi
    python3 -c "
import json
with open('$STATE_FILE', 'r') as f:
    d = json.load(f)
d['$field'] = $py_val
with open('$STATE_FILE', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
}

set_artifact() {
    python3 -c "
import json
with open('$STATE_FILE', 'r') as f:
    d = json.load(f)
d.setdefault('artifacts', {})['$1'] = '$2'
with open('$STATE_FILE', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
print('artifact recorded: $1=$2')
"
}

append_history() {
    python3 -c "
import json, datetime
with open('$STATE_FILE', 'r') as f:
    d = json.load(f)
d.setdefault('history', []).append({
    'event': '$1',
    'phase': d.get('phase',''),
    'time': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')
})
# 只保留最近 20 条
d['history'] = d['history'][-20:]
with open('$STATE_FILE', 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
"
}

phase_index() {
    local phase="$1"
    for i in "${!PHASES[@]}"; do
        [ "${PHASES[$i]}" = "$phase" ] && echo "$i" && return
    done
    echo "-1"
}

# ── 命令处理 ──────────────────────────────────────

cmd="${1:-status}"

case "$cmd" in

status)
    PHASE=$(get_field phase)
    FEATURE=$(get_field feature)
    GATE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('gatekeeper_passed', False))")
    echo -e "${CYAN}╔══════════════════════════════════╗${NC}"
    echo -e "${CYAN}║      Workflow State              ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════╝${NC}"
    echo -e "  Phase   : ${YELLOW}${PHASE}${NC}"
    echo -e "  Feature : ${FEATURE:-（未开始）}"
    echo -e "  Gate    : $([ "$GATE" = "True" ] && echo -e "${GREEN}PASSED${NC}" || echo -e "${RED}NOT PASSED${NC}")"
    echo ""
    echo -e "  阶段流程："
    for p in "${PHASES[@]}"; do
        if [ "$p" = "$PHASE" ]; then
            echo -e "  ${GREEN}▶ $p  ← 当前${NC}"
        else
            echo -e "    $p"
        fi
    done
    echo ""
    python3 -c "
import json
d = json.load(open('$STATE_FILE'))
arts = d.get('artifacts', {})
if any(arts.values()):
    print('  产物：')
    for k,v in arts.items():
        if v: print(f'    {k}: {v}')
"
    ;;

start)
    FEATURE="${2:-}"
    if [ -z "$FEATURE" ]; then
        echo -e "${RED}用法: workflow.sh start <feature-name>${NC}"; exit 1
    fi
    CURRENT=$(get_field phase)
    if [ "$CURRENT" != "idle" ] && [ "$CURRENT" != "complete" ]; then
        echo -e "${RED}错误: 当前有进行中的功能 ($CURRENT)，请先完成或 reset${NC}"; exit 1
    fi
    python3 -c "
import json, datetime
d = {
    'phase': 'requirements',
    'feature': '$FEATURE',
    'started_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'gatekeeper_passed': False,
    'artifacts': {'requirements': '', 'architecture': '', 'review': ''},
    'history': [{'event': 'started', 'phase': 'requirements', 'time': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}]
}
json.dump(d, open('$STATE_FILE', 'w'), indent=2, ensure_ascii=False)
"
    echo -e "${GREEN}✅ 已启动：$FEATURE${NC}"
    echo -e "${YELLOW}→ 当前阶段：requirements${NC}"
    echo -e "  下一步：需求分析师产出 docs/requirements/FR-XXX.md"
    ;;

advance)
    TARGET="${2:-}"
    CURRENT=$(get_field phase)
    CURR_IDX=$(phase_index "$CURRENT")
    TARGET_IDX=$(phase_index "$TARGET")

    if [ "$TARGET_IDX" = "-1" ]; then
        echo -e "${RED}无效阶段: $TARGET${NC}"
        echo "有效阶段: ${PHASES[*]}"; exit 1
    fi

    # 前置条件检查
    case "$TARGET" in
    architecture)
        REQ=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['artifacts'].get('requirements',''))")
        if [ -z "$REQ" ] || [ ! -f "$REQ" ]; then
            echo -e "${RED}❌ 前置条件未满足：需先记录 requirements 产物${NC}"
            echo -e "   执行：workflow.sh set-artifact requirements docs/requirements/FR-XXX.md"
            exit 1
        fi
        ;;
    dev)
        ARCH=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['artifacts'].get('architecture',''))")
        if [ -z "$ARCH" ] || [ ! -f "$ARCH" ]; then
            echo -e "${RED}❌ 前置条件未满足：需先记录 architecture 产物${NC}"
            exit 1
        fi
        ;;
    gatekeeper)
        if [ "$CURRENT" != "dev" ]; then
            echo -e "${RED}❌ 只能从 dev 阶段进入 gatekeeper${NC}"; exit 1
        fi
        ;;
    qa-review)
        GATE=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('gatekeeper_passed', False))")
        if [ "$GATE" != "True" ]; then
            echo -e "${RED}❌ 前置条件未满足：gatekeeper 未通过${NC}"
            echo -e "   先运行：bash scripts/gatekeeper.sh，通过后执行 workflow.sh gate-pass"
            exit 1
        fi
        ;;
    pm-acceptance)
        REVIEW=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d['artifacts'].get('review',''))")
        if [ -z "$REVIEW" ] || [ ! -f "$REVIEW" ]; then
            echo -e "${RED}❌ 前置条件未满足：需先记录 review 产物${NC}"
            exit 1
        fi
        ;;
    esac

    set_field phase "$TARGET"
    append_history "advanced_to_$TARGET"
    echo -e "${GREEN}✅ 阶段推进：$CURRENT → $TARGET${NC}"
    ;;

set-artifact)
    KEY="${2:-}"; PATH_VAL="${3:-}"
    if [ -z "$KEY" ] || [ -z "$PATH_VAL" ]; then
        echo -e "${RED}用法: workflow.sh set-artifact <key> <path>${NC}"; exit 1
    fi
    set_artifact "$KEY" "$PATH_VAL"
    append_history "artifact_set_$KEY"
    echo -e "${GREEN}✅ 产物已记录: $KEY = $PATH_VAL${NC}"
    ;;

gate-pass)
    set_bool_field gatekeeper_passed true
    append_history "gatekeeper_passed"
    echo -e "${GREEN}✅ Gatekeeper 状态已标记为 PASSED${NC}"
    echo -e "${YELLOW}→ 现在可以推进到 qa-review 阶段${NC}"
    echo -e "   执行：workflow.sh advance qa-review"
    ;;

gate-reset)
    set_bool_field gatekeeper_passed false
    append_history "gatekeeper_reset"
    echo -e "${YELLOW}⚠️  Gatekeeper 状态已重置（代码有变更）${NC}"
    ;;

complete)
    PHASE=$(get_field phase)
    if [ "$PHASE" != "pm-acceptance" ]; then
        echo -e "${RED}❌ 只能从 pm-acceptance 阶段完成功能${NC}"; exit 1
    fi
    FEATURE=$(get_field feature)
    set_field phase "complete"
    append_history "completed"
    echo -e "${GREEN}✅ 功能完成：$FEATURE${NC}"
    echo -e "   执行 workflow.sh start <next-feature> 开始下一个功能"
    ;;

reset)
    python3 -c "
import json
d = {'phase': 'idle', 'feature': '', 'started_at': '', 'gatekeeper_passed': False,
     'artifacts': {'requirements': '', 'architecture': '', 'review': ''}, 'history': []}
json.dump(d, open('$STATE_FILE', 'w'), indent=2, ensure_ascii=False)
"
    echo -e "${YELLOW}⚠️  工作流已强制重置到 idle${NC}"
    ;;

*)
    echo "用法: workflow.sh <status|start|advance|set-artifact|gate-pass|gate-reset|complete|reset>"
    ;;
esac
