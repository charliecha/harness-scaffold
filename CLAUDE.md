# crypto-snapshot — AI 工程准则 (Layer 1: Rule)

## 强制规则（红线，不可违反）

本项目红线分两层：
- **通用红线**见 [.harness/rules/common.md](.harness/rules/common.md)
- **语言专属红线**见 `.harness/rules/$LANG.md`（$LANG 来自 [.harness-config.json](.harness-config.json) 的 `language` 字段，当前为 `go` → [.harness/rules/go.md](.harness/rules/go.md)）

Claude 在每个 dev 阶段前应读取这两个文件。

## 开发工作流程

所有功能开发必须遵循六阶段流程，状态由 `.workflow-state.json` 追踪：

### 阶段命令

```bash
bash .harness/workflow.sh status                                          # 查看当前状态
bash .harness/workflow.sh start <feature-name>                            # 启动新功能
bash .harness/workflow.sh set-artifact requirements docs/requirements/FR-XXX.md
bash .harness/workflow.sh set-artifact architecture docs/architecture/ADR-XXX.md
bash .harness/workflow.sh set-artifact review docs/reviews/RV-XXX.md
bash .harness/workflow.sh advance architecture   # requirements → architecture
bash .harness/workflow.sh advance dev            # architecture → dev
bash .harness/workflow.sh advance gatekeeper     # dev → gatekeeper
bash .harness/workflow.sh advance qa-review      # 需 gatekeeper_passed=true
bash .harness/workflow.sh advance pm-acceptance  # 需 review 产物存在
bash .harness/workflow.sh complete               # 完成功能
```

### 阶段与角色对照

| 阶段 | 执行者 | 关键产物 | 进入下一阶段条件 |
|------|--------|---------|----------------|
| requirements | 需求分析师（`.claude/agents/requirement-analyst.md`） | `docs/requirements/FR-XXX.md` | 用户确认 |
| architecture | 架构师（`.claude/agents/architect.md`） | `docs/architecture/ADR-XXX.md` | 用户确认 |
| dev | 开发者 | 源码 + `bash .claude/skills/build.sh` + `bash .claude/skills/test.sh` | 两个 Skill PASSED |
| gatekeeper | 守门人（你运行） | `bash .harness/gatekeeper.sh` 退出码 0 | exit 0（hook 自动更新状态）|
| qa-review | QA（`.claude/agents/qa-reviewer.md`） | `docs/reviews/RV-XXX.md` | Critical = 0 |
| pm-acceptance | PM（`.claude/agents/pm-planner.md`） | 验收结论 | 所有 FR/NFR 满足 |

### Hook 机制（自动执行）

`.claude/settings.json` 配置了两个 hook：
- **PreToolUse**：每次 Bash 工具调用前，检查 `git push` 是否满足 gatekeeper 条件
- **PostToolUse**：`gatekeeper.sh` 执行成功后，自动执行 `workflow.sh gate-pass`

## 参考文档
- 编译 Skill：`.claude/skills/build.sh`
- 测试 Skill：`.claude/skills/test.sh`
- 守门人脚本：`.harness/gatekeeper.sh`
- 接口冒烟测试：`scripts/smoke_test.sh`
- 工作流状态管理：`.harness/workflow.sh`
- Push 拦截器：`.harness/check-phase.sh`
- 角色配置：`.claude/agents/*.md`
- 需求索引：`docs/requirements/INDEX.md`
- 架构索引：`docs/architecture/INDEX.md`
- 审查索引：`docs/reviews/INDEX.md`
