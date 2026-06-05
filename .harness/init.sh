#!/bin/bash
# .harness/init.sh — Harness 脚手架
# 在新项目根目录中跑：把 defaults/ 下的种子文件铺到正确位置，生成 config.json。
#
# 用法：
#   cd /path/to/new-project
#   cp -r <harness-repo>/.harness ./
#   bash .harness/init.sh --lang=python --name=my-app
#
# 选项：
#   --lang=<go|python|...>   语言 pack 名（必填）；必须在 .harness/packs/ 下存在
#   --name=<project-name>    项目名，写入 CLAUDE.md 标题；默认取当前目录名
#   --coverage=<n>           覆盖率阈值（默认 80）
#   --force                  覆盖已存在的目标文件
#
# 退出码 0 = 成功，非 0 = 失败

set -euo pipefail

# ─── 颜色（仅 tty） ────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

die() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }
ok()  { echo -e "${GREEN}✓ $1${NC}"; }
info(){ echo -e "${CYAN}→ $1${NC}"; }

# ─── 解析参数 ──────────────────────────────────────
LANG=""
NAME=""
COVERAGE=80
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --lang=*)     LANG="${arg#--lang=}" ;;
        --name=*)     NAME="${arg#--name=}" ;;
        --coverage=*) COVERAGE="${arg#--coverage=}" ;;
        --force)      FORCE=1 ;;
        -h|--help)
            sed -n '2,17p' "$0"; exit 0 ;;
        *)            die "未知参数: $arg" ;;
    esac
done

[ -z "$LANG" ] && die "缺少必填参数 --lang=<go|python|...>（运行 --help 查看用法）"

# ─── 定位 .harness 根 ─────────────────────────────
# init.sh 在 .harness/ 下，自己的 dirname 就是 .harness/
HARNESS_ROOT="$(cd "$(dirname "$0")" && pwd)"
DEFAULTS="$HARNESS_ROOT/defaults"
PACKS="$HARNESS_ROOT/packs"
PROJECT_ROOT="$(pwd)"

[ -d "$DEFAULTS" ] || die ".harness/defaults/ 不存在（当前 .harness 不完整）"
[ -d "$PACKS/$LANG" ] || die "未找到语言 pack: .harness/packs/$LANG/（可用：$(ls "$PACKS" 2>/dev/null | tr '\n' ' '))"

# ─── 项目名默认值 ──────────────────────────────────
[ -z "$NAME" ] && NAME="$(basename "$PROJECT_ROOT")"

# ─── 冲突检查 ──────────────────────────────────────
CONFLICTS=()
[ -e "$PROJECT_ROOT/.claude" ]               && CONFLICTS+=(".claude/")
[ -e "$PROJECT_ROOT/.workflow-state.json" ]  && CONFLICTS+=(".workflow-state.json")
[ -e "$PROJECT_ROOT/CLAUDE.md" ]             && CONFLICTS+=("CLAUDE.md")
[ -e "$PROJECT_ROOT/scripts/smoke_test.sh" ] && CONFLICTS+=("scripts/smoke_test.sh")
[ -e "$PROJECT_ROOT/docs/requirements/INDEX.md" ] && CONFLICTS+=("docs/requirements/INDEX.md")
[ -e "$PROJECT_ROOT/docs/architecture/INDEX.md" ] && CONFLICTS+=("docs/architecture/INDEX.md")
[ -e "$PROJECT_ROOT/docs/reviews/INDEX.md" ]      && CONFLICTS+=("docs/reviews/INDEX.md")

if [ ${#CONFLICTS[@]} -gt 0 ] && [ "$FORCE" -ne 1 ]; then
    echo -e "${RED}✗ 以下目标已存在：${NC}" >&2
    for c in "${CONFLICTS[@]}"; do echo -e "${RED}    $c${NC}" >&2; done
    echo -e "${YELLOW}使用 --force 覆盖，或手动移除后重试${NC}" >&2
    exit 1
fi

# ─── 开始铺设 ──────────────────────────────────────
info "Harness init: lang=$LANG name=$NAME coverage=$COVERAGE"
info "Project root: $PROJECT_ROOT"
echo ""

# 1. 写 config.json
cat > "$HARNESS_ROOT/config.json" << EOF
{"language":"$LANG","coverage_threshold":$COVERAGE,"artifact_name":"$NAME"}
EOF
ok "wrote .harness/config.json"

# 2. .claude/
mkdir -p "$PROJECT_ROOT/.claude"
cp -R "$DEFAULTS/claude/." "$PROJECT_ROOT/.claude/"
ok "seeded .claude/ (settings.json + agents/ + skills/)"

# 3. .workflow-state.json
cp "$DEFAULTS/workflow-state.json" "$PROJECT_ROOT/.workflow-state.json"
ok "seeded .workflow-state.json (phase=idle)"

# 4. CLAUDE.md — 替换占位符
sed -e "s/__PROJECT_NAME__/$NAME/g" -e "s/__LANG__/$LANG/g" \
    "$DEFAULTS/CLAUDE.md" > "$PROJECT_ROOT/CLAUDE.md"
ok "seeded CLAUDE.md (project=$NAME, lang=$LANG)"

# 5. scripts/smoke_test.sh
mkdir -p "$PROJECT_ROOT/scripts"
cp "$DEFAULTS/scripts/smoke_test.sh" "$PROJECT_ROOT/scripts/smoke_test.sh"
chmod +x "$PROJECT_ROOT/scripts/smoke_test.sh"
ok "seeded scripts/smoke_test.sh (placeholder)"

# 6. docs/{requirements,architecture,reviews}/INDEX.md
for sub in requirements architecture reviews; do
    mkdir -p "$PROJECT_ROOT/docs/$sub"
    cp "$DEFAULTS/docs/$sub/INDEX.md" "$PROJECT_ROOT/docs/$sub/INDEX.md"
done
ok "seeded docs/{requirements,architecture,reviews}/INDEX.md"

# ─── 后续提示 ──────────────────────────────────────
echo ""
echo -e "${GREEN}═══ Harness 初始化完成 ═══${NC}"
echo ""
echo "后续步骤："
echo "  1. 阅读项目红线："
echo "     - .harness/rules/common.md"
echo "     - .harness/rules/$LANG.md"
echo "  2. 准备语言工具链（详见 .harness/rules/$LANG.md）"
echo "  3. 开始第一个功能："
echo "     bash .harness/workflow.sh start <feature-name>"
echo ""
echo "查看当前状态：bash .harness/workflow.sh status"
