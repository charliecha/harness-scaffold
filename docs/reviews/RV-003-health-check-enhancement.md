# RV-003 健康检查增强 QA 审查报告

## 元数据

| 字段 | 值 |
|------|----|
| **ID** | RV-003 |
| **关联需求** | FR-003 |
| **关联架构** | ADR-003 |
| **审查日期** | 2026-06-03 |
| **审查员** | QA Reviewer |
| **Gatekeeper 状态** | PASSED |

---

## 审查范围

按 ADR-003 变更清单逐文件审查：

| 文件 | 操作 |
|------|------|
| `internal/health/checker.go` | 新增 |
| `internal/health/coingecko.go` | 新增 |
| `internal/health/coingecko_test.go` | 新增 |
| `internal/handler/handler.go` | 修改（重点：`Health()` 方法） |
| `internal/handler/handler_test.go` | 修改（新增三个 health 测试） |
| `cmd/server/main.go` | 修改 |

---

## Critical 级别发现

**Critical 问题总数：0**

经逐项核查，以下 Critical 维度均无问题：

### C1 — Goroutine 泄漏

`internal/handler/handler.go` 第 73–90 行，`Health()` 方法在循环内调用：

```go
ctx, cancel := context.WithTimeout(r.Context(), h.probeTimeout)
result := c.Check(ctx)
cancel()
```

`cancel()` 在 `c.Check(ctx)` 返回后**立即同步调用**，无 defer 延迟也无 goroutine 逃逸路径。`Check()` 本身为同步阻塞调用，不启动 goroutine。父 context 为 `r.Context()`，客户端断连时整条链自动取消。**无 goroutine 泄漏。**

### C2 — 错误处理

`internal/health/coingecko.go`：

- 第 32–35 行：`http.NewRequestWithContext` 返回的 `err` 已处理，返回 `unavailable`。
- 第 37–41 行：`client.Do` 返回的 `err` 已处理，返回 `unavailable`。
- 第 42 行：`resp.Body.Close()` 使用 `_ =` 显式忽略，符合规范（关闭 body 的 error 在 HTTP client 场景下无实质意义）。

`internal/handler/handler.go` 第 171–175 行，`writeJSON` 中 `json.NewEncoder(w).Encode(v)` 返回值用 `_ =` 显式忽略。HTTP response writer 写入失败时已无法向客户端传递错误，显式忽略合理。

**无遗漏的 error 处理。**

### C3 — 并发安全

`Handler` 结构体中 `checkers []health.Checker` 在构造时赋值，之后只读不写，无并发写入路径。`CoinGeckoChecker` 持有 `*http.Client` 和 `pingURL` 均为只读字段；`http.Client` 本身并发安全（标准库保证）。

**无并发安全问题。**

### C4 — 内部错误泄漏

`internal/health/coingecko.go`：`Check()` 返回的 `Result` 仅包含 `"ok"` / `"unavailable"` 状态字符串和延迟毫秒数，不包含任何 `err.Error()` 内容、URL、IP 或堆栈信息。

`internal/handler/handler.go` `Health()` 响应体仅透传 `Result.Status` 和 `Result.LatencyMs`，未将任何内部错误详情写入响应。

`Snapshot()` 第 126–130 行：`"coin not found"` 分支返回 `errResponse("coin not found: "+coinID)`——将用户输入的 `coinID` 拼回响应是预期业务行为（非内部错误泄漏）。其余上游错误返回 `"upstream unavailable"`，无泄漏。

**无内部错误泄漏。**

### C5 — 硬编码密钥

全部审查文件中未发现任何硬编码 API Key、Token、Secret 或密码。`defaultPingURL` 为公开 CoinGecko Ping 端点 URL，不属于凭证。

**无硬编码密钥。**

---

## Warning 级别发现

### W1 — `cancel()` 调用位置（可读性边界）

**文件**：`internal/handler/handler.go`，第 74–76 行

```go
ctx, cancel := context.WithTimeout(r.Context(), h.probeTimeout)
result := c.Check(ctx)
cancel()
```

ADR-003 已明确说明此处故意不用 `defer cancel()`：`Check()` 为同步调用，循环内每次迭代都应立即释放 context，避免下一个 checker 启动时上一个 context 仍挂载。设计合理。

**建议**：添加一行注释说明不使用 `defer` 的意图，防止后续维护者"修正"为 `defer` 引入语义变化。

**处理决定**：建议修复（补注释），不影响通过。

### W2 — 测试覆盖：`NewCoinGeckoChecker` 与 `Name()` 未被测试

**文件**：`internal/health/coingecko.go`

`go tool cover` 显示 `NewCoinGeckoChecker`（第 20 行）和 `Name()`（第 27 行）覆盖率为 0%。测试文件 `coingecko_test.go` 通过 `newTestChecker` 直接构造结构体，绕过了 `NewCoinGeckoChecker` 和 `Name()`。

- `Name()` 是接口方法，在 `handler_test.go` 中通过 `mockChecker` mock 覆盖，实际生产路径未被单元测试直接覆盖。
- `internal/health` 包整体覆盖率为 80.0%，恰好达到 80% 下限，无余量。

**建议**：为 `TestCoinGeckoChecker_ok` 增加 `Name()` 断言；或增加一个调用 `NewCoinGeckoChecker()` 的简单测试，顺带验证 `Name()` 返回值。

**处理决定**：建议修复，当前覆盖率紧贴下限，抗风险性低。不影响通过。

### W3 — `probeTimeout` 未在响应体中反映

**文件**：`internal/handler/handler.go` `Health()` 方法

当探测超时时（`ctx` 被取消），`LatencyMs` 反映的是超时时刻的延迟（即约等于 `probeTimeout` 值），而非实际上游响应时间，可能使调用方误判上游延迟。当前行为符合 ADR-003 设计，但文档中未明确说明此边界情况的含义。

**处理决定**：纯信息性，归 Info 级别更合适，降级为 Info。

---

## Info 级别发现

### I1 — `http.Client` 连接池独立

ADR-003 已知遗留问题第 2 条。`CoinGeckoChecker` 持有独立 `*http.Client`，与 `internal/client` 中的实例相互独立，存在两份连接池。当前规模影响可忽略，未来可通过依赖注入共享 `http.Transport`。

### I2 — 探测频率无限制

ADR-003 已知遗留问题第 3 条。高频 `/health` 调用（如 LB 每秒数百次）会对 CoinGecko 免费层造成压力。建议运维层通过 LB 健康探测间隔配置缓解，或未来版本在内存中缓存最近一次探测结果（TTL 5–10s）。

### I3 — `w3.timeout` 超时语义

W3 降级：当 context 超时时，`LatencyMs` 约等于 `probeTimeout`，而非上游实际响应时间。调用者应将超时场景的 `latency_ms` 理解为"超过阈值"而非精确测量值。可在 `/health` 文档或 OpenAPI 注释中说明。

### I4 — 测试中 `_ = json.Decode(...)` 不检查 decode 错误

**文件**：`internal/handler/handler_test.go`，多处（第 78、103、121 行）

```go
_ = json.NewDecoder(rec.Body).Decode(&body)
```

若响应体格式错误，`body` 为零值，后续断言会以误导性的方式失败而非明确报告解析错误。生产代码质量不受影响，但测试可读性可提升。

---

## 验收准则核查（对应 FR-003）

| AC ID | 描述 | 验证方式 | 结果 |
|-------|------|---------|------|
| AC-1a | `/health` 返回 `{"status": "ok"\|"degraded", "dependencies": {...}}` | `TestHealth_allOk`、`TestHealth_degraded` | PASS |
| AC-1b | 依赖项包含 `status` 和 `latency_ms` 字段 | `TestHealth_allOk` 断言 `cg["status"]` | PASS |
| AC-2a | 所有上游正常 → `status: "ok"` | `TestHealth_allOk` | PASS |
| AC-2b | 任一上游不可用 → HTTP 200 + `status: "degraded"` | `TestHealth_degraded` 明确注释 AC-2b | PASS |
| AC-3a | 探测超时可配置（`-health-probe-timeout` flag，默认 3s） | `cmd/server/main.go` 第 36 行 | PASS |
| AC-3b | 超时由 context 控制，不阻塞 handler | `coingecko.go` 使用 `http.NewRequestWithContext(ctx, ...)` | PASS |
| AC-4a | 仅检查 CoinGecko `/ping` HTTP 状态码，不解析响应体 | `coingecko.go` 第 44–47 行 | PASS |
| AC-4b | 探测错误细节不透传响应体 | C4 章节验证 | PASS |

---

## 测试运行结果（审查时快照）

```
=== go test -race ===
ok  internal/health     2.917s
ok  internal/handler    1.944s
✅ all tests passed (race detector clean)

=== coverage ===
internal/health:   80.0% (≥ 80%)
internal/handler:  93.9% (≥ 80%)
overall:           92.1% (≥ 80%)
```

---

## 结论

**Critical 问题数：0**
**Warning 问题数：2**（W1 注释缺失、W2 覆盖率紧贴下限）
**Info 问题数：4**

---

## QA: PASSED
