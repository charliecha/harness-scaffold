# Go 专属红线

本文件列出 Go 项目专属的硬性规则。通用规则见 `.harness/rules/common.md`。

## 编译与测试

- 修改任何 `.go` 文件后，必须执行 **Build Skill**（`bash .claude/skills/build.sh`）验证通过
- 提交代码前必须执行 **Test Skill**（`bash .claude/skills/test.sh`）验证通过

## 日志规范

- 所有日志必须使用 `log/slog`，禁止裸 `fmt.Println` / `fmt.Printf`

## 代码质量

- 不得引入 `golangci-lint` 报出的警告或错误
- `go vet` 必须 clean
- 禁止 `panic(...)` 进入 `internal/` 包

## 工具链

- `golangci-lint` 必须本地安装（`brew install golangci-lint`）
- 可选工具（gatekeeper 会软跳过）：`govulncheck`、`deadcode`
