# Test Skill (Layer 2: Skill)

执行此 Skill 时，**必须按序完成以下所有步骤，不得跳过任一步**。
每步失败即停止，向上游报告失败原因。

---

## Step 1：竞态检测下运行全部测试

```bash
go test -race -count=1 -timeout=60s ./...
```

验证：退出码 = 0，无 `DATA RACE` 报告。
`-count=1` 禁用测试缓存，确保每次真实执行。

---

## Step 2：生成覆盖率报告

```bash
go test -coverprofile=coverage.out -covermode=atomic ./...
go tool cover -func=coverage.out
```

---

## Step 3：验证覆盖率基线

```bash
COVERAGE=$(go tool cover -func=coverage.out | grep "^total:" | awk '{print $3}' | tr -d '%')
echo "Coverage: ${COVERAGE}%"
# 低于 80% 则失败
```

验证：total coverage ≥ 80%，否则失败并列出覆盖率最低的文件。

---

## Step 4：生成 HTML 覆盖率报告（可选，调试用）

```bash
go tool cover -html=coverage.out -o coverage.html
```

---

## 完成条件

- 所有测试通过（含竞态检测）
- 覆盖率 ≥ 80%

才可向上游报告 **"Test Skill: PASSED"**（须附上覆盖率数值）。

任一步失败 → 报告 **"Test Skill: FAILED at Step N"** + 完整错误输出。
