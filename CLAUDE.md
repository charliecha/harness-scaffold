# crypto-snapshot — AI 工程准则 (Layer 1: Rule)

## 强制规则（红线，不可违反）

### 编译与测试
- 修改任何 `.go` 文件后，必须调用 **Build Skill**（`skills/build.md`）验证通过
- 提交代码前必须调用 **Test Skill**（`skills/test.md`）验证通过
- 永远不能仅靠主观判断报告"完成"——必须有脚本退出码 = 0 作为依据

### 安全红线
- 禁止在代码中硬编码 API Key、密码、Token、Secret
- 所有外部凭证必须通过环境变量注入
- HTTP handler 不得直接暴露内部错误堆栈给客户端

### 日志规范
- 所有日志必须使用结构化日志（`log/slog`）
- 禁止在 `internal/` 目录下使用裸 `fmt.Println` / `fmt.Printf` 输出业务日志
- 错误日志必须包含 `err` 字段

### 代码质量
- 测试覆盖率不得低于 80%（`go test -coverprofile` 验证）
- 所有对外 HTTP 接口必须有对应单元测试
- 不得引入 `golangci-lint` 报出的警告或错误

### 流程规则
- 任何阶段失败（守门人脚本 exit != 0）不得向前推进
- 不允许为"通过检查"而修改检查标准本身
- Sub-Agent 角色之间只通过可验证产物交接，不接受口头承诺

## 开发工作流程

所有功能开发必须遵循 `WORKFLOW.md` 定义的六阶段流程，不得跳过任何阶段：

1. **Phase 1 需求确认** — 产出 `REQUIREMENTS.md`，用户确认后才能进入下一阶段
2. **Phase 2 架构设计** — 产出 `ARCHITECTURE.md`，守门人确认无安全风险后才能进入
3. **Phase 3 实现** — 必须依次通过 Build Skill + Test Skill，才能提交交接报告
4. **Phase 4 守门人校验** — 运行 `bash scripts/gatekeeper.sh`，exit 0 才能进入下一阶段
5. **Phase 5 QA 审查** — 产出 `review.md`，Critical = 0 才能进入
6. **Phase 6 PM 验收** — 逐条对照 `REQUIREMENTS.md` 验收

**禁止**：在用户未确认当前阶段产物的情况下，主动推进到下一阶段。

## 参考文档
- 编译 SOP：`skills/build.md`
- 测试 SOP：`skills/test.md`
- 校验 SOP：`skills/validate.md`
- 守门人脚本：`scripts/gatekeeper.sh`
- 工作流协议：`WORKFLOW.md`（完整阶段定义）
- 角色职责：`agents/ROLES.md`
- 需求索引：`docs/requirements/INDEX.md`
- 架构索引：`docs/architecture/INDEX.md`
- 审查索引：`docs/reviews/INDEX.md`
