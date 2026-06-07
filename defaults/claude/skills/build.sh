#!/bin/bash
# .claude/skills/build.sh — Build Skill dispatcher
# 读 .harness-config.json 的 language，调用 .harness/packs/<lang>/build.sh
set -euo pipefail
_d="$(cd "$(dirname "$0")" && pwd)"
while [ "$_d" != "/" ] && [ ! -f "$_d/.harness/lib.sh" ]; do _d="$(dirname "$_d")"; done
[ -f "$_d/.harness/lib.sh" ] || { echo "harness: .harness/lib.sh not found upward from $0" >&2; exit 1; }
source "$_d/.harness/lib.sh"
exec bash "$(harness_require_pack build.sh)"
