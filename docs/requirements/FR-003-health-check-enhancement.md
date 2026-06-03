# FR-003 健康检查增强

## 概述

在现有 `/health` 接口基础上，加入上游 API（CoinGecko）可用性探测，使调用方（负载均衡器、监控系统、运维人员）能够通过单一接口判断服务本身及其关键依赖的健康状态。

**状态**：Active  
**创建日期**：2026-06-03  
**作者**：需求分析师

---

## 背景与现状

当前 `/health` 实现（`internal/handler/handler.go`）仅返回：

```json
{"status": "ok"}
```

该响应永远为 200，无法反映上游 CoinGecko API 是否可达。当 CoinGecko 故障时，`/snapshot/:coinID` 会返回 503，但 `/health` 仍显示正常，导致监控系统误判服务健康。

---

## 功能需求

### FR-003-1　依赖状态字段

`/health` 响应体必须包含顶层 `dependencies` 对象，列出每个上游依赖的探测结果。

**验收标准**：
- AC-1a：响应 JSON 包含 `dependencies.coingecko.status` 字段，值为 `"ok"` 或 `"unavailable"`。
- AC-1b：响应 JSON 包含 `dependencies.coingecko.latency_ms` 字段，值为非负整数，表示本次探测的往返延迟（毫秒）。
- AC-1c：响应 JSON 保留顶层 `status` 字段，值为 `"ok"` 或 `"degraded"`。

### FR-003-2　整体状态聚合

顶层 `status` 必须根据所有依赖的探测结果聚合计算。

**验收标准**：
- AC-2a：所有依赖均为 `"ok"` 时，顶层 `status` = `"ok"`，HTTP 状态码 = **200**。
- AC-2b：任意依赖为 `"unavailable"` 时，顶层 `status` = `"degraded"`，HTTP 状态码 = **200**（不改变为 5xx，避免触发负载均衡器摘除）。

> 设计说明：使用 200+degraded 而非 503，是为了让监控系统能读到响应体中的具体依赖状态，而不是被网络层拦截。

### FR-003-3　探测超时

上游探测必须有独立超时，不阻塞 `/health` 接口的响应时间。

**验收标准**：
- AC-3a：单次依赖探测超时时间可配置，默认值为 **3 秒**。
- AC-3b：若探测超时，`dependencies.coingecko.status` = `"unavailable"`，`latency_ms` = 探测实际耗时（不超过超时上限）。
- AC-3c：在上游探测超时的情况下，`/health` 整体响应时间不得超过探测超时上限 + 100ms。

### FR-003-4　探测端点

探测 CoinGecko 可用性时，必须使用轻量级端点，避免消耗业务配额。

**验收标准**：
- AC-4a：探测使用 CoinGecko `/ping` 端点（`https://api.coingecko.com/api/v3/ping`）。
- AC-4b：探测结果仅作健康判断，不写入缓存，不触发业务指标计数。

### FR-003-5　响应结构示例

接口响应体必须符合以下结构（字段名称与类型不可变更）：

```json
{
  "status": "ok",
  "dependencies": {
    "coingecko": {
      "status": "ok",
      "latency_ms": 42
    }
  }
}
```

---

## 非功能需求

### NFR-1　性能

- `/health` P99 响应时间 ≤ 探测超时 + 100ms（探测成功时通常 ≤ 500ms）。

### NFR-2　可观测性

- 每次依赖探测结果必须以结构化日志记录（`log/slog`），包含字段：`dependency`、`status`、`latency_ms`。
- 日志级别：探测成功用 `Debug`，探测失败/超时用 `Warn`。

### NFR-3　测试覆盖

- `/health` handler 的单元测试覆盖率 ≥ 80%，必须覆盖：上游正常、上游超时、上游返回错误 三种场景。

### NFR-4　向后兼容

- 新响应体为原有 `{"status":"ok"}` 的超集，不移除任何现有字段，不改变字段类型。

---

## 排除范围

以下内容**不在本需求范围内**：

1. 缓存命中率、内存使用率等内部指标暴露（属于 `/metrics` 职责）。
2. 多个上游 API 的并发探测策略（本次仅探测 CoinGecko）。
3. 探测结果的历史记录或时间序列存储。
4. 主动告警或通知机制（由外部监控系统消费 `/health` 响应决定）。
5. 鉴权/限流对 `/health` 的特殊处理。

---

## 确认记录

| 字段 | 值 |
|------|----|
| 确认人 | （待填写） |
| 确认时间 | （待填写） |
| 确认方式 | （待填写） |
| 备注 | （待填写） |
