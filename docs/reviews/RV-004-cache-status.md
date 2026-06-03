# RV-004 缓存状态接口 QA 审查

## 元信息

| 字段 | 值 |
|------|----|
| 编号 | RV-004 |
| 标题 | 缓存状态接口 QA 审查 |
| 审查日期 | 2026-06-03 |
| 审查人 | QA 审查员 |
| 关联需求 | FR-004 |
| 关联 ADR | ADR-004 |
| 守门人状态 | PASSED（前置条件满足）|

---

## 审查范围

| 文件 | 说明 |
|------|------|
| `internal/cache/store.go` | Get 写锁升级、HitCount 递增、Status() 实现 |
| `internal/cache/store_test.go` | 命中计数和 Status 测试 |
| `internal/handler/handler.go` | CacheStatus handler |
| `internal/handler/handler_test.go` | CacheStatus 测试 |
| `cmd/server/main.go` | 路由注册 |

---

## Critical 发现

**Critical 数量：0**

### C1：Goroutine 泄漏 — 无问题

FR-004 新增的代码路径（`Get`、`Status`、`CacheStatus`）均不启动 goroutine。`cmd/server/main.go` 中已有的服务器 goroutine（第 88 行）在 `http.ErrServerClosed` 时正常退出，并有 `signal.Notify` + `srv.Shutdown` 的完整退出路径，与本次变更无关。

### C2：错误处理 — 无问题

- `internal/cache/store.go`：`Status()` 和 `Get()` 均不返回 `error`，无可被忽略的错误值。
- `internal/handler/handler.go`：`writeJSON`（第 193 行）使用 `_ = json.NewEncoder(w).Encode(v)` 显式丢弃编码错误。这是 Go HTTP 编程的标准做法——HTTP 响应头已写出后，Encode 错误无法传递给客户端，显式丢弃是正确处理。
- `CacheStatus`（第 140 行）不调用外部服务，不产生可被忽略的 error。

### C3：并发安全 — 无问题

- `Get`（`store.go` 第 42 行）：升级为 `s.mu.Lock()`（全写锁），命中时执行 `snap.HitCount++` 后回写 `s.items[coinID]`，符合 ADR-004 技术选型 A。
- `Set`（`store.go` 第 55 行）：使用 `s.mu.Lock()`，与 `Get` 一致。
- `Status`（`store.go` 第 68 行）：使用 `s.mu.RLock()`，只读扫描。与 `Get`/`Set` 的写锁互斥，不会产生数据竞争。
- `TestStore_ConcurrentAccess`（`store_test.go` 第 139 行）：并发测试覆盖了写-读交叉场景；goroutine 通过 `<-done` channel 同步退出，测试本身无 goroutine 泄漏。

### C4：内部错误泄漏 — 无问题

`CacheStatus` handler 仅调用 `h.cache.Status()`（无 error 返回、无外部调用），响应体仅包含 `coins` 业务数组。与 `/snapshot/` handler 的对比：后者的上游错误明确以 `"upstream unavailable"` 屏蔽，前者根本不存在错误传播路径。

### C5：硬编码密钥 — 无问题

审查范围内所有文件均无硬编码 API Key、Token、密码或 Secret。

---

## Warning 发现

**Warning 数量：2**

### W1：CacheStatus handler 无请求日志

- **文件**：`internal/handler/handler.go`，第 140–156 行
- **描述**：`CacheStatus` handler 不输出任何日志。其他 handler（`Snapshot`、`Health`）在关键路径均有 `h.logger.Info/Error` 调用，`CacheStatus` 缺少请求日志，会降低线上可观测性（无法通过日志追踪访问频率或异常调用方）。
- **建议**：在 handler 入口处添加一行 `h.logger.Debug("cache status queried")` 级别的日志，使日志一致性与其他路由对齐。
- **处理决定**：不阻塞本次发布。FR-004 未要求日志，可在后续迭代补充。

### W2：内联响应 struct 与 ADR 约定不一致

- **文件**：`internal/handler/handler.go`，第 141–144 行
- **描述**：ADR-004 规划了 `cacheEntryResponse` 和 `cacheStatusResponse` 作为包级私有类型（`internal/handler/handler.go`），但实现使用了函数内联的匿名 struct `entryResponse` / `statusResponse`。内联写法不影响正确性，但若其他 handler 未来复用相同结构则需重构。
- **建议**：如 ADR 中描述，将 struct 提升为包级私有类型以便维护和测试。
- **处理决定**：不阻塞本次发布。当前仅一处使用，内联写法减少了包级命名空间污染，可在重用需求出现时再提升。

---

## Info 发现

**Info 数量：3**

### I1：Get 写锁对高并发读吞吐的影响

- **文件**：`internal/cache/store.go`，第 42 行
- **描述**：将 `RLock` 升级为 `Lock` 是正确设计，但在极高并发读场景下会串行化所有 `Get` 调用。ADR-004 已在"已知遗留问题"中记录此权衡，NFR-3（P99 < 50ms，≤1000 条目）在当前规模下可接受。未来若 QPS 显著增长，可考虑 `atomic.Int64` 指针方案。

### I2：Status() 每次调用分配新切片

- **文件**：`internal/cache/store.go`，第 73 行
- **描述**：`make([]CacheEntry, 0, len(s.items))` 在每次调用时分配堆内存。对 ≤1000 条目、低频调用场景无影响，但在高频轮询场景下会产生 GC 压力。技术债务，可在性能需求驱动时引入对象池。

### I3：/cache/status 未受速率限制保护

- **文件**：`cmd/server/main.go`，第 69 行
- **描述**：按照 NFR-4，`/cache/status` 不经过 metrics 中间件（正确）。但同时也不经过 `rl.Limit` 速率限制中间件，理论上可被任意频率访问。FR-004 排除了认证/鉴权需求，当前设计与 FR-004 范围一致。若运营阶段发现滥用，可考虑补充限流。

---

## 需求验收矩阵

| 验收标准 | 实现位置 | 测试覆盖 | 状态 |
|---------|---------|---------|------|
| AC-1 空缓存返回 `{"coins":[]}` | `handler.go:151-155` | `TestCacheStatus_empty` | 通过 |
| AC-2 非空缓存条目数一致 | `store.go:68-86` | `TestCacheStatus_withEntries` | 通过 |
| AC-3 coin_id 字段正确 | `store.go:79` | `TestCacheStatus_withEntries` | 通过 |
| AC-4 TTL 向下取整 | `store.go:76` (`int64(remaining.Seconds())`) | `TestStore_Status_ttlPositive` | 通过 |
| AC-5 过期条目不返回 | `store.go:77-78` | `TestStore_Status_excludesExpired` | 通过 |
| AC-6 初始命中次数为 0 | `store.go:61` (`HitCount: 0`) | `TestStore_HitCount_initial` | 通过 |
| AC-7 命中次数递增 | `store.go:49-50` | `TestStore_HitCount_increments` | 通过 |
| AC-8 Set 后命中次数重置 | `store.go:59-63` | `TestStore_HitCount_resetOnSet` | 通过 |
| AC-9 Content-Type: application/json | `handler.go:191` (`writeJSON`) | `TestCacheStatus_empty` | 通过 |
| NFR-2 并发安全 | `sync.RWMutex` + `-race` | `TestStore_ConcurrentAccess` | 通过 |
| NFR-4 不计入 metrics | `main.go:69` (直接注册) | 架构设计保证 | 通过 |

---

## 结论

```
QA: PASSED
```

Critical = 0，Warning = 2（已给出处理决定，均不阻塞发布），Info = 3（参考性建议）。

所有 FR-004 验收标准（AC-1 至 AC-9）和非功能需求（NFR-2、NFR-4）均有对应实现和测试覆盖。代码符合项目强制规则（结构化日志、无硬编码密钥、锁保护共享状态、不暴露内部错误）。

---

## 第二轮复审（2026-06-03）

### 复审背景

第一轮 QA 发现以下两项问题，开发者已提交修复：

- **AC-5**：`Status()` 过滤条件不足，导致 `ttl_sec` 可能输出 0，违反"剩余时间不足 1 秒的条目不应出现在响应中"的约束。
- **AC-8**：`handler_test.go` 中缺少通过 HTTP 层验证 `Set` 重置命中计数的专项测试。

### 变更逐项审查

#### 变更 1：`internal/cache/store.go` — `Status()` 过滤条件

原逻辑：`if remaining <= 0 { continue }`  
修复后：`if remaining < time.Second { continue }`

审查结论：

- 修复方向正确。原条件仅排除严格过期（`remaining <= 0`）的条目，当 `0 < remaining < 1s` 时，`int64(remaining.Seconds())` 会截断为 `0`，输出 `ttl_sec: 0`，违反 AC-5 的 `ttl_sec >= 1` 约束。
- 新条件 `remaining < time.Second` 正确排除所有剩余时间不足 1 秒的条目，保证进入响应的条目满足 `ttl_sec >= 1`。
- 边界分析：`remaining == time.Second` 时 `int64(remaining.Seconds()) == 1`，满足约束；`remaining < time.Second` 被过滤，符合预期。无新引入问题。

#### 变更 2：`internal/cache/store_test.go` — 新增 `TestStore_Status_excludesSubSecondTTL`

测试逻辑：以 500ms TTL 创建条目，等待 100ms 后调用 `Status()`，此时 `remaining ≈ 400ms < 1s`，断言返回 0 条。

审查结论：

- 测试覆盖了修复的边界场景（`0 < remaining < 1s`），能精确回归 AC-5 的边界约束。
- 等待时间（100ms）与 TTL（500ms）之间留有充足余量，不存在时序竞争导致假失败的风险。
- 测试使用独立 Store 实例，无副作用，符合单元测试隔离原则。无问题。

#### 变更 3：`internal/handler/handler_test.go` — 新增 `TestCacheStatus_hitCountResetOnSet`

测试逻辑：通过 handler 直接操作 `h.cache`，执行 Set → Get × 2 → Set（覆盖）后调用 `/cache/status`，断言 `hit_count == 0`。

审查结论：

- 直接访问 `h.cache`（包私有字段）在同包测试中合法（`package handler`），无问题。
- 该测试在 HTTP 响应层验证了 AC-8，与 `store_test.go` 的 `TestStore_HitCount_resetOnSet` 形成互补：前者验证 cache 层行为，后者验证通过 handler 暴露的 JSON 响应字段。覆盖完整。
- 测试结构清晰，断言精确，无副作用。无问题。

### 测试执行结果

执行 `bash .claude/skills/test.sh`（含 `-race` 竞态检测器）：

- `internal/cache`：coverage 100.0%，PASSED
- `internal/handler`：coverage 94.6%，PASSED
- 全局覆盖率：93.1%（>= 80% 强制规则）
- `-race` 检测：clean，无竞态告警

### 第二轮复审结论

| 修复项 | 修复正确性 | 新引入问题 |
| ------ | ---------- | ---------- |
| AC-5 `Status()` 过滤条件 | 正确 | 无 |
| AC-5 边界测试 `TestStore_Status_excludesSubSecondTTL` | 覆盖完整 | 无 |
| AC-8 HTTP 层专项测试 `TestCacheStatus_hitCountResetOnSet` | 覆盖完整 | 无 |

第一轮结论维持不变：

```text
QA: PASSED
```

Critical = 0（第一轮及第二轮均未发现 Critical 问题）。所有 FR-004 验收标准（AC-1 至 AC-9）经修复后均已满足，测试覆盖率合规。
