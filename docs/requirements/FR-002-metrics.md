# FR-002 — 接口统计功能

**状态**：Active
**关联 ADR**：待定
**关联 Review**：待定

---

## 功能需求

- **FR-01**：新增 `/metrics` 端点，返回各接口的请求统计
  - 验收标准：响应 JSON 包含每个路由的 `total_requests`、`rate_limited_requests`
- **FR-02**：统计数据在服务运行期间持续累计（内存存储）
  - 验收标准：连续发送请求后，`total_requests` 数值递增
- **FR-03**：统计数据按路由分组（`/snapshot/*`、`/health`、`/version`）
  - 验收标准：各路由统计独立，不互相污染

## 非功能需求

- **NFR-01**：`/metrics` 端点本身不被统计（避免自递归）
- **NFR-02**：统计采集不影响现有接口性能（无额外锁竞争导致延迟）
- **NFR-03**：`internal/` 测试覆盖率维持 ≥ 80%
- **NFR-04**：`bash scripts/gatekeeper.sh` 全部通过

## 排除范围

- 不做 Prometheus 格式导出，仅 JSON
- 不做持久化存储，重启清零
- 不做历史时序数据，仅累计值
- 不做鉴权保护

## 确认记录

- 用户确认时间：2026-06-03
- avg_response_ms 不做，用户已确认
- /metrics 不需要鉴权，用户已确认
