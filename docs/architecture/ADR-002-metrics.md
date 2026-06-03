# ADR-002 — 接口统计功能架构设计

**状态**：Accepted
**关联需求**：[FR-002](../requirements/FR-002-metrics.md)
**关联 Review**：待定

---

## 包结构变更

新增 `internal/metrics` 包，统计逻辑完全隔离。

```
internal/
  metrics/
    collector.go       # 计数器定义 + 原子操作
    collector_test.go  # 单元测试
```

## 技术选型

- `sync/atomic`（`atomic.Int64`）：原子计数器，无锁，满足 NFR-02 性能要求

## 核心接口

```go
type RouteStats struct {
    TotalRequests       atomic.Int64
    RateLimitedRequests atomic.Int64
}

type Collector struct {
    routes sync.Map  // key: string (route), value: *RouteStats
}

func New() *Collector
func (c *Collector) Record(route string, rateLimited bool)
func (c *Collector) Snapshot() map[string]RouteStatsJSON
```

## 数据流

```
请求到达任意路由
  ↓
middleware 调用 collector.Record(route, rateLimited)
  ↓
atomic.Int64 递增（无锁）

GET /metrics → collector.Snapshot() → JSON 响应
/metrics 自身不调用 Record（NFR-01）
```

## cmd/server/main.go 变更

```go
col := metrics.New()
mux.Handle("/snapshot/", col.Middleware("/snapshot/*", rl.Limit(http.HandlerFunc(h.Snapshot))))
mux.HandleFunc("/health",  col.WrapFunc("/health", h.Health))
mux.HandleFunc("/version", col.WrapFunc("/version", h.Version))
mux.HandleFunc("/metrics", h.Metrics(col))
```

## 安全边界

无新增外部 API、无凭证、无硬编码值。
