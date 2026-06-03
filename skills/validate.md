# Validate Skill (Layer 2: Skill)

后置校验 Skill，在 Build Skill 和 Test Skill 通过后执行。
验证产物的正确性，而非代码本身。

---

## Step 1：API 端点冒烟测试

启动服务（后台）：
```bash
./bin/crypto-snapshot &
SERVER_PID=$!
sleep 1
```

测试健康检查端点：
```bash
curl -sf http://localhost:8080/health | jq .
```
验证：HTTP 200，返回 `{"status":"ok"}` 结构。

测试快照端点：
```bash
curl -sf "http://localhost:8080/snapshot/bitcoin" | jq .
```
验证：HTTP 200，响应 JSON 包含 `coin`、`price_usd`、`timestamp` 字段。

测试无效 coin：
```bash
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/snapshot/invalid_coin_xyz")
```
验证：HTTP 404 或 400（不得返回 500）。

停止服务：
```bash
kill $SERVER_PID 2>/dev/null
```

---

## Step 2：结构化日志验证

```bash
./bin/crypto-snapshot &
SERVER_PID=$!
sleep 1
curl -s http://localhost:8080/health > /dev/null
kill $SERVER_PID 2>/dev/null
```

验证：服务标准输出的每行日志可被 `jq` 解析（结构化 JSON 格式），
无裸文本行（`grep -v '^{' log_output.txt` 应为空）。

---

## Step 3：版本端点验证

```bash
curl -sf http://localhost:8080/version | jq .
```
验证：包含 `version`、`commit`、`build_time` 字段，值非空。

---

## 完成条件

全部端点响应正确，日志格式合规。

才可向上游报告 **"Validate Skill: PASSED"**。

任一步失败 → 报告 **"Validate Skill: FAILED at Step N"** + curl 响应内容。
