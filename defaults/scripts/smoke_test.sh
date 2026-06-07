#!/bin/bash
# scripts/smoke_test.sh — 项目业务专属冒烟测试
# 由 .harness/gatekeeper.sh 调用，退出码 0 = PASSED
#
# ⚠️  此文件是占位符，尚未填写实际测试。
# gatekeeper 会在此处 FAIL，直到你补充真实的冒烟测试为止。
#
# 填写指南：
#   - HTTP 服务：用 curl 或 TestClient 测试所有对外接口的 happy path 和关键 4xx
#   - CLI 工具：调用二进制并断言输出/退出码
#   - Library：in-process 调用公共 API 验证核心路径
#
# 填写完毕后，删除下方的 exit 1 和此注释块。

echo "❌ smoke_test.sh 尚未填写——请参照注释补充项目专属冒烟测试后删除此 exit 1"
exit 1
