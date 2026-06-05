#!/bin/bash
# .claude/skills/test.sh — Test Skill dispatcher
# 读 .harness/config.json 的 language，调用 .harness/packs/<lang>/test.sh
set -euo pipefail
source "$(git rev-parse --show-toplevel)/.harness/lib.sh"
exec bash "$(harness_require_pack test.sh)"
