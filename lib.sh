#!/bin/bash
# .harness/lib.sh — Harness 共享工具库
# 供 dispatcher 脚本 source：读 .harness-config.json 的字段

# 用法：source .harness/lib.sh 后可用：
#   harness_get <field>           — 读 .harness-config.json 中的字符串/数值字段
#   harness_lang                  — 返回 language 字段
#   harness_pack_dir              — 返回当前语言的 pack 目录绝对路径
#   harness_require_pack <script> — 检查 pack 下指定脚本存在，否则报错退出

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# config 在项目根（HARNESS_ROOT 的父目录），不在 .harness/ 里——避免跨项目同步污染
HARNESS_CONFIG="$(dirname "$HARNESS_ROOT")/.harness-config.json"

harness_get() {
    local field="$1"
    [ -f "$HARNESS_CONFIG" ] || { echo "harness: config not found: $HARNESS_CONFIG" >&2; return 1; }
    python3 -c "import json,sys; d=json.load(open('$HARNESS_CONFIG')); v=d.get('$field',''); print(v)"
}

harness_lang() {
    harness_get language
}

harness_pack_dir() {
    local lang
    lang=$(harness_lang)
    [ -z "$lang" ] && { echo "harness: language not set in config" >&2; return 1; }
    echo "$HARNESS_ROOT/packs/$lang"
}

harness_require_pack() {
    local script="$1"
    local pack
    pack=$(harness_pack_dir) || return 1
    local path="$pack/$script"
    if [ ! -f "$path" ]; then
        echo "harness: pack script missing: $path" >&2
        echo "        (language=$(harness_lang) — check .harness-config.json)" >&2
        return 1
    fi
    echo "$path"
}
