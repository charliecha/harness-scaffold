# Python 专属红线

本文件列出 Python 项目专属的硬性规则。通用规则见 `.harness/rules/common.md`。

## 编译与测试

- 修改任何 `.py` 文件后，必须执行 **Build Skill**（`bash .claude/skills/build.sh`）验证通过
- 提交代码前必须执行 **Test Skill**（`bash .claude/skills/test.sh`）验证通过

## 日志规范

- 所有日志必须使用 `logging` 模块（或 `structlog`），禁止裸 `print(...)` 输出运行时信息
- 测试代码中可使用 `print()`（自动豁免）

## 代码质量

- 不得引入 `ruff check` 报出的警告或错误
- `mypy --ignore-missing-imports` 必须 clean（若已安装）

## 工具链

- 必须本地安装：`pip install ruff pytest pytest-cov`
- 可选工具（gatekeeper 会软跳过）：`mypy`
- 项目必须有 `pyproject.toml`
