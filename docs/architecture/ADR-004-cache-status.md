# ADR-004 缓存状态接口架构设计

## 元信息

| 字段 | 值 |
|------|----|
| 编号 | ADR-004 |
| 标题 | 缓存状态接口架构设计 |
| 创建日期 | 2026-06-03 |
| 作者 | 架构师 |
| 状态 | Accepted |
| 关联需求 | FR-004 |

---

## 背景

`cache.Store` 目前存储 `Snapshot{Price, ExpiresAt}`，但没有暴露任何可观测接口。FR-004 要求新增 `GET /cache/status`，返回所有未过期条目的 `coin_id`、剩余 TTL（秒整数）和累计命中次数。

本 ADR 描述为满足该需求所做的最小结构性变更：仅扩展 `cache.Store`，新增一个 handler 方法，并在 `main.go` 中挂载路由。

---

## 包结构

### 修改的文件

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `internal/cache/store.go` | 修改 | `Snapshot` 增加 `HitCount int64` 字段；`Get` 升级为写锁以原子递增命中计数；新增 `Status()` 方法 |
| `internal/cache/store_test.go` | 修改 | 新增命中计数、`Status()` 的单元测试 |
| `internal/handler/handler.go` | 修改 | 新增 `CacheStatus` handler 方法；新增响应 struct `cacheStatusResponse` / `cacheEntryResponse` |
| `cmd/server/main.go` | 修改 | 在 mux 中挂载 `GET /cache/status`，**不经过** metrics 中间件 |

### 不变的文件

`internal/client/`、`internal/metrics/`、`internal/middleware/`、`internal/health/` 均无需改动。

---

## 核心接口定义

### 1. `cache` 包扩展

```go
// internal/cache/store.go

// Snapshot 增加命中计数字段
type Snapshot struct {
    Price     *client.CoinPrice
    ExpiresAt time.Time
    HitCount  int64  // 新增：自 Set 以来的缓存命中累计次数
}

// CacheEntry 是 Status() 返回给调用方的只读视图
type CacheEntry struct {
    CoinID   string
    TTLSec   int64  // 剩余 TTL，秒，向下取整，始终 >= 1
    HitCount int64
}

// Status 返回当前所有未过期条目的快照视图。
// 顺序不保证；已过期条目不包含在内。
func (s *Store) Status() []CacheEntry

// Get 签名不变，但内部使用写锁以递增 HitCount。
// func (s *Store) Get(coinID string) (*client.CoinPrice, bool)
```

**命中计数递增策略**：`Get` 从 `RLock` 升级为 `Lock`（全写锁），在命中路径上执行 `snap.HitCount++` 后回写 `s.items[coinID]`。理由见下文"技术选型"。

### 2. `handler` 包扩展

```go
// internal/handler/handler.go

// CacheStatus 处理 GET /cache/status
func (h *Handler) CacheStatus(w http.ResponseWriter, r *http.Request)

// 内部响应结构（仅在 handler 包内可见）
type cacheEntryResponse struct {
    CoinID   string `json:"coin_id"`
    TTLSec   int64  `json:"ttl_sec"`
    HitCount int64  `json:"hit_count"`
}

type cacheStatusResponse struct {
    Coins []cacheEntryResponse `json:"coins"`
}
```

### 3. 路由注册（`main.go`）

```go
// 直接挂载，不经过 col.Middleware 和 rl.Limit
mux.HandleFunc("/cache/status", h.CacheStatus)
```

---

## 数据流

```
客户端 GET /cache/status
        │
        ▼
   http.ServeMux  ──→  handler.CacheStatus(w, r)
                              │
                              │  h.cache.Status()
                              ▼
                       cache.Store.Status()
                         ├─ s.mu.RLock()
                         ├─ 遍历 s.items
                         │    过滤 time.Now().After(snap.ExpiresAt)
                         │    计算 TTLSec = int64(snap.ExpiresAt.Sub(now).Seconds())
                         │    收集 CacheEntry{CoinID, TTLSec, HitCount}
                         └─ s.mu.RUnlock()
                              │
                              ▼
                  []CacheEntry → cacheStatusResponse{Coins: [...]}
                              │
                              ▼
                    writeJSON(w, 200, cacheStatusResponse)
                    Content-Type: application/json
```

**命中计数递增数据流**（`GET /snapshot/{coinID}` 触发）：

```
handler.Snapshot
    │  h.cache.Get(coinID)
    ▼
cache.Store.Get(coinID)
    ├─ s.mu.Lock()          ← 写锁（而非 RLock）
    ├─ 检查是否存在且未过期
    ├─ snap.HitCount++
    ├─ s.items[coinID] = snap  ← 回写
    └─ s.mu.Unlock()
    return snap.Price, true
```

---

## 技术选型及理由

### 选型 A：`Get` 升级为写锁（已选）

将 `Get` 中的 `s.mu.RLock()` 改为 `s.mu.Lock()`，命中时在 map 中原地修改并回写。

**理由**：
- 实现最简单，无需额外依赖。
- `cache.Store` 本身已有写锁用于 `Set`，语义一致。
- 命中时的写锁竞争代价可接受：NFR-3 要求 P99 < 50ms（≤1000 条目），写锁竞争远低于该量级下的网络/序列化开销。
- 不会因为写锁延迟 `Set` 超过必要时间（NFR-2）：`Get` 锁持有时间极短（map 读 + 自增 + 回写），与 `Set` 的锁持有时间量级相同。

**放弃的替代方案**：
- `sync/atomic` + `HitCount *int64`（指针原子操作）：可以保留 `RLock`，但需要在 `Snapshot` 中存储指针，`Set` 重置时需 `atomic.StoreInt64`，代码复杂度上升，收益有限。
- 单独的 `sync.Map` 存命中计数：引入两份独立状态，一致性维护困难，排除。

### 选型 B：`Status()` 使用 `RLock`（已选）

`Status()` 是只读扫描，使用 `s.mu.RLock()` 即可。与 `Get` 的写锁不会同时持有（各自独立加锁解锁），满足 NFR-2。

### 选型 C：路由不经过 metrics 中间件（已选）

与 `/metrics` 路由同等对待，直接 `mux.HandleFunc("/cache/status", h.CacheStatus)` 注册，不包装 `col.Middleware`，满足 NFR-4。

---

## 安全边界说明

1. **只读接口**：`CacheStatus` handler 仅调用 `Store.Status()`，不执行任何写操作，满足 FR-004 排除范围第 1 条。
2. **不暴露内部错误堆栈**：handler 内无需调用外部服务，无错误传播路径；`writeJSON` 封装保证响应体仅含业务字段。
3. **无认证/鉴权**：与现有路由一致，FR-004 明确将认证排除在外。
4. **无分页**：内存遍历上限由 NFR-3 的 ≤1000 条目约束；超出范围行为不在本需求覆盖内，不引入额外限制逻辑。
5. **数据竞争**：`Status()` 的 `RLock` 与 `Get` 的 `Lock` 均通过 `sync.RWMutex` 保证互斥，`-race` 检测可验证。

---

## 已知遗留问题

1. **`Get` 从 RLock 升级为 Lock 会略微降低高并发读吞吐**：当前系统规模下可接受；若未来 QPS 极高，可考虑 atomic 指针方案，但需单独立项评估。
2. **`Status()` 返回的是时间点快照**：在高频更新场景下，TTL 可能在读取和序列化之间产生微小误差（< 1ms），属已知可接受偏差，需在测试中用容差断言而非精确等于。
3. **`store_test.go` 现有测试未覆盖命中计数**：新增的测试须覆盖 AC-6、AC-7、AC-8，覆盖率须维持 ≥ 80%（CLAUDE.md 强制规则）。

---

## 确认记录

| 字段 | 值 |
|------|----|
| 确认人 | 用户 |
| 确认时间 | 2026-06-03 |
| 确认方式 | 对话确认 |
| 备注 | 架构方案确认通过，进入开发阶段 |
