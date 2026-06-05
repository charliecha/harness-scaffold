# Harness 框架

`.harness/` 是一个**语言无关的 AI 工程脚手架**：六阶段工作流（requirements → architecture → dev → gatekeeper → qa-review → pm-acceptance）+ 守门人安检 + 语言专属 build/test/lint。

## 一键初始化新项目

```bash
# 1. 在新项目根目录下，拷贝 .harness/
cd /path/to/new-project
cp -r /path/to/harness-source/.harness ./

# 2. 跑 init
bash .harness/init.sh --lang=python --name=my-app

# 3. 完成。现在项目根下会有：
#    .claude/                     ← Claude Code 配置（hooks + agents + skills）
#    .harness/                    ← 本框架（保持不动）
#    .workflow-state.json         ← 工作流状态机（phase=idle）
#    CLAUDE.md                    ← 项目级 AI 工程准则（已填好项目名 + 语言）
#    scripts/smoke_test.sh        ← 业务冒烟测试占位符
#    docs/{requirements,architecture,reviews}/INDEX.md
```

### init.sh 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `--lang=<go\|python\|...>` | ✅ | 语言 pack 名，必须在 `.harness/packs/` 下存在 |
| `--name=<project-name>` | | 项目名，写入 CLAUDE.md 标题；默认取当前目录名 |
| `--coverage=<n>` | | 覆盖率阈值，写入 `.harness/config.json`，默认 80 |
| `--force` | | 覆盖已存在的目标文件 |

冲突保护：默认情况下，如果项目根下已存在 `.claude/`、`CLAUDE.md`、`.workflow-state.json` 等任何 init 会铺设的文件，会**报错退出**。用 `--force` 才会覆盖。

## 目录结构

```
.harness/
├── init.sh                ← 脚手架入口（用户唯一需要直接调用的命令）
├── config.json            ← 项目级配置：language / coverage_threshold / artifact_name
├── lib.sh                 ← 共享 helper：harness_get / harness_lang / harness_require_pack
│
├── workflow.sh            ← 六阶段状态机（语言无关）
├── gatekeeper.sh          ← 安检骨架，delegate 到 packs/<lang>/gatekeeper-checks.sh
├── check-phase.sh         ← git push 拦截器（Claude Code PreToolUse hook 调用）
│
├── rules/                 ← 红线文档（Layer 1: Rule）
│   ├── common.md          ← 通用红线（Secret、结构化日志、流程规则等）
│   ├── go.md              ← Go 专属
│   └── python.md          ← Python 专属
│
├── packs/                 ← 语言专属实现（pack 协议）
│   ├── go/
│   │   ├── build.sh                ← exec 调用（独立 skill，自带退出码契约）
│   │   ├── test.sh                 ← exec 调用
│   │   └── gatekeeper-checks.sh    ← source 调用（共享骨架 PASS/FAIL）
│   └── python/
│       ├── build.sh
│       ├── test.sh
│       └── gatekeeper-checks.sh
│
└── defaults/              ← init 时铺到项目根的种子文件
    ├── CLAUDE.md          ← 项目 CLAUDE.md 模板（含 __PROJECT_NAME__ / __LANG__ 占位符）
    ├── workflow-state.json
    ├── claude/            → .claude/
    │   ├── settings.json
    │   ├── agents/*.md
    │   └── skills/{build,test}.sh
    ├── scripts/
    │   └── smoke_test.sh  ← 项目业务冒烟测试占位（exit 0）
    └── docs/
        ├── requirements/INDEX.md
        ├── architecture/INDEX.md
        └── reviews/INDEX.md
```

## 设计原则

### 骨架 vs 皮肤

- **骨架**（`.harness/` 下，不含 `packs/`）：语言无关、跨项目复用
- **皮肤**（`.harness/packs/<lang>/`）：语言专属实现

骨架文件零修改即可切换语言——靠 `.harness/config.json` 的 `language` 字段路由到对应 pack。

### Pack 调用协议

| Pack 脚本 | 调用方 | 调用方式 | 理由 |
|---|---|---|---|
| `build.sh` | `.claude/skills/build.sh` | `exec bash` | 独立 skill，自带退出码契约 |
| `test.sh` | `.claude/skills/test.sh` | `exec bash` | 独立 skill |
| `gatekeeper-checks.sh` | `.harness/gatekeeper.sh` | `source` | 共享骨架的 PASS/FAIL 累加器 |

### 路径定位策略

| 位置 | 找 lib.sh 的方式 |
|---|---|
| `.claude/skills/*.sh`、`scripts/smoke_test.sh` | 从脚本位置向上找包含 `.harness/lib.sh` 的目录 |
| `.harness/<x>.sh` | `$(dirname "$0")/lib.sh` |
| `.harness/packs/<lang>/*.sh` | `$(dirname "$0")/../../lib.sh` |

**不依赖 git**——`git init` 之前 harness 也能工作。

## 增加新语言

假设要支持 Rust：

1. 建 `.harness/packs/rust/{build,test,gatekeeper-checks}.sh`，遵循 pack 调用协议
2. 写 `.harness/rules/rust.md`（Rust 专属红线）
3. 测试：`mkdir /tmp/rust-test && cd /tmp/rust-test && cp -r .../.harness ./ && bash .harness/init.sh --lang=rust && ...`

无需修改骨架。

## 维护约定

### `.harness/defaults/claude/` vs 本仓库 `.claude/`

- 本仓库 `.claude/` 是 **harness 维护者自己用的**（也可能积累项目特定微调）
- `.harness/defaults/claude/` 是 **给新项目用的种子**（保持通用）

两者大体同源但**不必同步**。修改 agent 定义时主动判断是否要同步到 defaults。

### 不要把项目运行时状态放进 `.harness/`

`.workflow-state.json`、`docs/requirements/FR-*.md`、`scripts/smoke_test.sh` 等都属于**项目运行时**，不属于 harness 框架。它们的初始版本在 `defaults/`，但运行时实例在项目根。

### 升级 harness

未来若把 `.harness/` 改成独立 git 仓库（L3），现有用户的升级路径：

```bash
cd project-root
rm -rf .harness
cp -r .../updated-harness/.harness ./
# 不重新跑 init.sh——init 只在新项目首次使用
```

`.claude/`、`CLAUDE.md`、`.workflow-state.json` 不受影响。
