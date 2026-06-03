# ADR-003 健康检查增强架构设计

## 元数据

| 字段 | 值 |
|------|----|
| **ID** | ADR-003 |
| **状态** | Proposed |
| **关联需求** | FR-003 |
| **创建日期** | 2026-06-03 |
| **作者** | 架构师 |

---

## 背景

当前 `/health` 实现（`internal/handler/handler.go: Health()`）仅返回硬编码的 `{"status":"ok"}`，永远不反映上游 CoinGecko 的真实状态。FR-003 要求加入 CoinGecko `/ping` 探测，并以结构化 JSON 体暴露依赖状态，同时保证 `/health` 响应时间受探测超时上限约束。

---

## 决策

### 1. 包结构：新增 `internal/health` 包，`handler` 最小改动

```
internal/
  health/                         ← 新增包
    checker.go                    ← Checker 接口 + DependencyResult 类型
    coingecko.go                  ← CoinGeckoChecker 实现（探测 /ping）
    coingecko_test.go             ← 单元测试（mock HTTP server）
  handler/
    handler.go                    ← 修改：Health() 方法接收 Checker，构造聚合响应
    handler_test.go               ← 修改：补充 health 三场景测试
cmd/server/
  main.go                         ← 修改：构造 CoinGeckoChecker 并注入 Handler
```

**理由**：探测逻辑独立于 HTTP 层，便于单独测试和未来扩展（FR 排除范围中提到"多个上游并发探测"是未来事项）。将 `Checker` 定义在 `internal/health` 而非 `handler`，避免 `handler` 包承载业务探测逻辑。

---

### 2. 核心接口定义

```go
// internal/health/checker.go

package health

import (
    "context"
    "time"
)

// Result 表示单次依赖探测的结果。
type Result struct {
    Status    string        // "ok" 或 "unavailable"
    LatencyMs int64         // 往返延迟，毫秒，非负整数
}

// Checker 抽象一个可探测的依赖。
// 实现必须在 ctx 超时前返回；调用方用带超时的 context 控制上限。
type Checker interface {
    Name() string
    Check(ctx context.Context) Result
}
```

`Handler` 持有 `[]health.Checker`（初期只有一个），`Health()` 方法依次调用并聚合结果：

```go
// internal/handler/handler.go（修改后签名）

// Handler 新增字段
type Handler struct {
    cache    *cache.Store
    client   PriceFetcher
    logger   *slog.Logger
    version  VersionInfo
    checkers []health.Checker       // ← 新增
}

// New 新增参数
func New(c *cache.Store, fetcher PriceFetcher, logger *slog.Logger,
    v VersionInfo, checkers []health.Checker) *Handler
```

`Health()` 响应类型（内部结构体，不对外暴露包级类型）：

```go
type healthResponse struct {
    Status       string                        `json:"status"`
    Dependencies map[string]dependencyStatus   `json:"dependencies"`
}

type dependencyStatus struct {
    Status    string `json:"status"`
    LatencyMs int64  `json:"latency_ms"`
}
```

---

### 3. 数据流：请求 → 探测 → 响应

```
客户端 GET /health
       │
       ▼
handler.Health(w, r)
       │
       ├─ 为每个 Checker 创建带超时 context（默认 3s，可配置）
       │        context.WithTimeout(r.Context(), probeTimeout)
       │
       ├─ 顺序调用（本期仅一个）：checker.Check(ctx)
       │        └─ CoinGeckoChecker.Check(ctx)
       │                 ├─ 记录 t0
       │                 ├─ GET https://api.coingecko.com/api/v3/ping
       │                 │     （使用 http.NewRequestWithContext，ctx 携带超时）
       │                 ├─ 记录 latencyMs = time.Since(t0).Milliseconds()
       │                 ├─ 成功（2xx）→ Result{Status:"ok", LatencyMs:latencyMs}
       │                 └─ 失败/超时 → Result{Status:"unavailable", LatencyMs:latencyMs}
       │
       ├─ 聚合：所有 checker 均 ok → topStatus="ok"；任一 unavailable → topStatus="degraded"
       │
       ├─ slog 记录每个探测结果（Debug/Warn）
       │
       └─ writeJSON(w, 200, healthResponse{...})
              └─ HTTP 200（无论 ok/degraded，见 FR-003-2 设计说明）
```

**关键约束**：`r.Context()` 作为父 context，若客户端断连则探测也会取消，避免资源泄漏。

---

### 4. 技术选型及理由

#### 4.1 超时控制：`context.WithTimeout`，不用 `http.Client.Timeout`

`CoinGeckoChecker` 持有一个**不设全局 Timeout 的** `http.Client`（或超时设为探测超时上限），超时完全由调用方传入的 `ctx` 控制。

理由：
- `http.Client.Timeout` 是实例级全局值，无法在每次调用时动态调整。
- `context.WithTimeout` 让调用方（`Health()`）成为超时的单一控制点，符合 AC-3a（可配置）。
- 与现有 `Snapshot()` 中 `context.WithTimeout(r.Context(), 8s)` 模式一致。

#### 4.2 探测端点：CoinGecko `/ping`

使用 `https://api.coingecko.com/api/v3/ping`，响应体为 `{"gecko_says":"(V3) To the Moon!"}` 且极轻量。探测仅检查 HTTP 状态码为 2xx，不解析响应体，满足 AC-4a、AC-4b。

探测结果**不写入** `cache.Store`，不调用 `metrics.Collector.Record()`。

#### 4.3 超时默认值：3 秒，通过启动参数注入

在 `main.go` 新增 `-health-probe-timeout` flag（默认 `3s`），构造 `CoinGeckoChecker` 时传入，满足 AC-3a。超时值存储为 `CoinGeckoChecker` 的字段，由 `Health()` 读取后调用 `context.WithTimeout`。

#### 4.4 聚合逻辑：线性扫描，无并发（本期）

本期仅一个上游，无需并发 goroutine。保持实现简单，与排除范围"多个上游并发探测"对应。未来如需扩展，可在 `Health()` 中引入 `sync.WaitGroup` + goroutine，接口无需变更。

#### 4.5 HTTP 状态码：始终 200

顶层 `status` 为 `"degraded"` 时仍返回 HTTP 200，满足 AC-2b。理由见 FR-003-2 设计说明：避免负载均衡器因 5xx 摘除服务节点。

---

### 5. 安全边界说明

| 边界 | 处理方式 |
|------|---------|
| 探测错误信息 | `CoinGeckoChecker.Check()` 只返回 `Result`，不将上游错误细节透传至响应体，仅写入 slog |
| 超时泄漏 | 使用 `context.WithTimeout` + `defer cancel()`，超时后 HTTP 连接由 net/http 关闭 |
| 内部路径暴露 | 响应体仅含 `status` / `latency_ms`，不暴露探测 URL、服务器 IP 或堆栈信息 |
| 无鉴权 | `/health` 不引入鉴权（FR-003 排除范围第 5 条），调用方可无凭证访问 |
| 无写操作 | 探测为只读 HTTP GET，不触发缓存写入或计数器更新 |

---

### 6. 文件级变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `internal/health/checker.go` | 新增 | `Checker` 接口、`Result` 类型 |
| `internal/health/coingecko.go` | 新增 | `CoinGeckoChecker` 实现，含探测超时字段 |
| `internal/health/coingecko_test.go` | 新增 | 使用 `httptest.NewServer` mock，覆盖正常/超时/错误场景 |
| `internal/handler/handler.go` | 修改 | `Handler` 增加 `checkers` 字段；`New()` 增加参数；`Health()` 重写为聚合逻辑 |
| `internal/handler/handler_test.go` | 修改 | 补充 health 三场景测试（上游正常、超时、错误）；原 `TestHealth` 更新 |
| `cmd/server/main.go` | 修改 | 新增 `-health-probe-timeout` flag；构造 `CoinGeckoChecker`；注入 `Handler` |

---

### 7. 已知遗留问题

1. **`Handler.New()` 签名变更为破坏性变更**：现有 `newTestHandler()` 测试辅助函数需同步更新，传入空 `checkers` 切片（`nil` 或 `[]health.Checker{}`）以维持向后兼容。

2. **`http.Client` 实例共享**：`CoinGeckoChecker` 持有独立的 `http.Client`，与 `CoinGecko`（`internal/client`）中的 `http.Client` 相互独立，存在两份连接池。本期影响可忽略，未来可考虑通过依赖注入共享 transport。

3. **探测频率未限制**：`/health` 被高频调用时，每次都会发出一次对 CoinGecko 的 HTTP 请求。FR-003 明确探测不计入业务配额，且排除了缓存探测结果，但若调用频率极高（如 LB 每秒数百次），可能消耗 CoinGecko 免费层配额。该风险留给运维层通过限制 LB 探测频率处理，不在本期代码层面解决。

---

## 确认记录

| 字段 | 值 |
|------|----|
| 确认人 | 用户 |
| 确认时间 | 2026-06-03 |
| 确认方式 | 对话确认 |
| 备注 | 架构方案通过，进入开发阶段 |
