#!/bin/bash
# scripts/smoke_test.sh — 项目业务专属冒烟测试
# 由 .harness/gatekeeper.sh 调用，退出码 0 = PASSED
# 新项目应在此处加入对外接口的冒烟测试（curl HTTP / CLI smoke / 等）。
# 当前为占位符——如本项目无对外接口（如 library），保留 exit 0 即可。

echo "smoke: nothing to test (replace with project-specific smoke tests)"
exit 0
