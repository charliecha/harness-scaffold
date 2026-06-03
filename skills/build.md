# Build Skill (Layer 2: Skill)

执行此 Skill 时，**必须按序完成以下所有步骤，不得跳过任一步**。
每步失败即停止，向上游报告失败原因，不得继续推进。

---

## Step 1：同步并验证依赖

```bash
go mod tidy
go mod verify
```

验证：`go mod verify` 输出 `all modules verified`，否则失败。

---

## Step 2：静态分析（零警告零错误）

```bash
golangci-lint run ./...
```

验证：退出码 = 0，无任何 warning 或 error 输出。
> 若本地未安装 golangci-lint，执行 `brew install golangci-lint` 或参考 https://golangci-lint.run/usage/install/

---

## Step 3：编译（注入版本元数据）

```bash
go build \
  -ldflags="-X main.Version=$(git describe --tags --always --dirty) \
            -X main.BuildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
            -X main.Commit=$(git rev-parse --short HEAD)" \
  -o bin/crypto-snapshot \
  ./cmd/server
```

验证：`bin/crypto-snapshot` 文件存在且为可执行文件（`file bin/crypto-snapshot`）。

---

## Step 4：验证版本元数据注入

```bash
./bin/crypto-snapshot --version
```

验证：输出包含 `Version`、`Commit` 字段，值非空非 `(devel)`。

---

## 完成条件

以上四步全部退出码 = 0，才可向上游报告 **"Build Skill: PASSED"**。

任一步失败 → 报告 **"Build Skill: FAILED at Step N"** + 完整错误输出。
