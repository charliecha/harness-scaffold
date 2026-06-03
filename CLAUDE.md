# crypto-snapshot — AI 工程准则 (Layer 1: Rule)

## 强制规则（红线，不可违反）

### 编译与测试
- 修改任何 `.go` 文件后，必须执行 **Build Skill**（`bash skills/build.sh`）验证通过
- 提交代码前必须执行 **Test Skill**（`bash skills/test.sh`）验证通过
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
- **git push 前必须 gatekeeper 通过**（由 `.claude/settings.json` hooks 强制执行）

## 开发工作流程

所有功能开发必须遵循六阶段流程，状态由 `.workflow-state.json` 追踪：

### 阶段命令

```bash
# 查看当前状态
bash scripts/workflow.sh status

# 启动新功能（进入 requirements 阶段）
bash scripts/workflow.sh start <feature-name>

# 记录阶段产物
bash scripts/workflow.sh set-artifact requirements docs/requirements/FR-XXX.md
bash scripts/workflow.sh set-artifact architecture docs/architecture/ADR-XXX.md
bash scripts/workflow.sh set-artifact review docs/reviews/RV-XXX.md

# 推进阶段（前置条件不满足则自动拒绝）
bash scripts/workflow.sh advance architecture   # requirements → architecture
bash scripts/workflow.sh advance dev            # architecture → dev
bash scripts/workflow.sh advance gatekeeper     # dev → gatekeeper
bash scripts/workflow.sh advance qa-review      # 需 gatekeeper_passed=true
bash scripts/workflow.sh advance pm-acceptance  # 需 review 产物存在

# gatekeeper 通过后自动由 hook 执行（也可手动）
bash scripts/workflow.sh gate-pass

# 完成功能
bash scripts/workflow.sh complete
```

### 阶段与角色对照

| 阶段 | 执行者 | 关键产物 | 进入下一阶段条件 |
|------|--------|---------|----------------|
| requirements | 需求分析师（`subagents/requirement-analyst.json`） | `docs/requirements/FR-XXX.md` | 用户确认 |
| architecture | 架构师（`subagents/architect.json`） | `docs/architecture/ADR-XXX.md` | 用户确认 |
| dev | 开发者 | 源码 + `bash skills/build.sh` + `bash skills/test.sh` | 两个 Skill PASSED |
| gatekeeper | 守门人（你运行） | `bash scripts/gatekeeper.sh` 退出码 0 | exit 0（hook 自动更新状态）|
| qa-review | QA（`subagents/qa-reviewer.json`） | `docs/reviews/RV-XXX.md` | Critical = 0 |
| pm-acceptance | PM（`subagents/pm-planner.json`） | 验收结论 | 所有 FR/NFR 满足 |

### Hook 机制（自动执行）

`.claude/settings.json` 配置了两个 hook：
- **PreToolUse**：每次 Bash 工具调用前，检查 `git push` 是否满足 gatekeeper 条件
- **PostToolUse**：`gatekeeper.sh` 执行成功后，自动执行 `workflow.sh gate-pass`

## 参考文档
- 编译 Skill：`skills/build.sh`
- 测试 Skill：`skills/test.sh`
- 守门人脚本：`scripts/gatekeeper.sh`
- 接口冒烟测试：`scripts/smoke_test.sh`
- 工作流状态管理：`scripts/workflow.sh`
- Push 拦截器：`scripts/check-phase.sh`
- 工作流协议：`WORKFLOW.md`（完整阶段定义）
- 角色配置：`subagents/*.json`
- 需求索引：`docs/requirements/INDEX.md`
- 架构索引：`docs/architecture/INDEX.md`
- 审查索引：`docs/reviews/INDEX.md`

