# FR-001 — 限流功能

**状态**：Done
**关联 ADR**：[ADR-001](../architecture/ADR-001-rate-limiting.md)
**关联 Review**：[RV-001](../reviews/RV-001-rate-limiting.md)

---

## 功能需求

- **FR-01**：对 `/snapshot/{coin}` 接口按 IP 限流
  - 验收标准：同一 IP 超过限制后返回 HTTP 429，响应体为 `{"error":"rate limit exceeded"}`
- **FR-02**：限流配置可通过启动参数调整
  - 验收标准：`--rate-limit`（默认 10 req/s）和 `--burst`（默认 20）参数生效
- **FR-03**：被限流的请求写入结构化日志
  - 验收标准：日志包含 `ip`、`path`、`"rate_limited":true` 字段

## 非功能需求

- **NFR-01**：`/health`、`/version` 接口豁免限流，不受影响
- **NFR-02**：`internal/` 测试覆盖率维持 ≥ 80%
- **NFR-03**：`bash scripts/gatekeeper.sh` 全部通过

## 排除范围

- 不做分布式限流（仅单实例内存）
- 不做用户维度限流（仅 IP 维度）

## 确认记录

- 用户确认时间：2026-06-03
- 默认参数：rate=10 req/s，burst=20，用户已确认
- 豁免接口：/health、/version，用户已确认
