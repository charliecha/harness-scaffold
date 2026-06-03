# ARCHITECTURE.md — 限流功能

## 包结构变更

新增 `internal/middleware` 包，限流逻辑完全隔离，不侵入现有 handler。

```
internal/
  middleware/
    ratelimit.go       # 限流中间件 + per-IP limiter 管理
    ratelimit_test.go  # 单元测试
```

## 技术选型

- `golang.org/x/time/rate`：令牌桶算法，Go 官方扩展库，线程安全，支持 burst

## 核心接口

```go
type RateLimiter struct {
    limiters sync.Map   // key: IP string, value: *rate.Limiter
    r        rate.Limit
    b        int
    logger   *slog.Logger
}

func New(r rate.Limit, b int, logger *slog.Logger) *RateLimiter
func (rl *RateLimiter) Limit(next http.Handler) http.Handler
```

## 数据流

```
/snapshot/* → RateLimiter.Limit → 提取 IP → Allow()
                                    ├─ true  → 下游 handler
                                    └─ false → 429 + slog
/health, /version → 直接 handler（豁免）
```

## cmd/server/main.go 变更

新增 flag：
- `--rate-limit float`（默认 10.0）
- `--burst int`（默认 20）

路由注册：
```go
rl := middleware.New(rate.Limit(*rateLimit), *burst, logger)
mux.Handle("/snapshot/", rl.Limit(http.HandlerFunc(h.Snapshot)))
```

## 安全边界

无新增外部 API、无凭证、无硬编码值。
