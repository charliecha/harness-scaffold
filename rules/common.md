# 通用红线（语言无关）

本文件列出所有项目共享的硬性规则，不依赖具体编程语言或工具链。语言专属规则见 `.harness/rules/$LANG.md`（$LANG 来自 `.harness-config.json` 的 `language` 字段）。

## 安全红线

- 禁止在代码中硬编码 API Key、密码、Token、Secret——必须通过环境变量或密钥管理服务注入
- HTTP handler 不得直接暴露内部错误堆栈给客户端
- 错误日志必须包含 `err` 字段（结构化日志的错误字段）
- 所有日志必须使用结构化日志（具体库由 `$LANG.md` 指定）

## 代码质量

- 测试覆盖率不得低于 `.harness-config.json` 中 `coverage_threshold` 字段配置的阈值
- 所有对外接口（HTTP / RPC / CLI）必须有对应单元测试；**缺失视为 Critical，QA 审查必须标记为 FAILED**
- Build Skill 和 Test Skill 必须通过才能进入 gatekeeper 阶段

## 流程规则

- 任何阶段失败（守门人脚本 exit != 0）不得向前推进
- 不允许为"通过检查"而修改检查标准本身
- Sub-Agent 角色之间只通过可验证产物（FR / ADR / RV 文档）交接，不接受口头承诺
- **git push 前必须 gatekeeper 通过**（由 `.claude/settings.json` hooks 强制执行）
- gatekeeper 失败 → 退回 dev 阶段
- QA Critical 问题 > 0 → 退回 dev 阶段重走 gatekeeper
- PM Reject → 退回对应阶段重做
