# RV-002 — 接口统计功能 QA 审查

**状态**：Passed
**审查时间**：2026-06-03
**关联需求**：[FR-002](../requirements/FR-002-metrics.md)
**关联 ADR**：[ADR-002](../architecture/ADR-002-metrics.md)

---

## Critical（必须修复）

无。

## Warning（建议修复）

**W-01：`responseWriter.statusCode` 默认值为 0，handler 未显式调用 `WriteHeader` 时统计结果不准确**

- 位置：`internal/metrics/collector.go:74`
- 问题：`WriteHeader` 只在 handler 显式调用时才被拦截。若 handler 直接调用 `Write()` 写入响应体（Go 默认隐式返回 200），`statusCode` 保持 0，导致限流判断 `rw.statusCode == 429` 永远为 false
- 影响：`/health`、`/version` 用 `WrapFunc` 包装，已硬编码 `rateLimited=false`，不受影响。`/snapshot/*` 用 `Middleware`，但其内部限流 handler 显式调用了 `WriteHeader(429)`，当前场景正确
- 建议：在 `responseWriter` 中重写 `Write()` 方法，若 `statusCode` 为 0 则先设为 200
- 处理决定：**建议修复**，当前场景不受影响，但存在隐患，后续新接口若未显式调用 `WriteHeader` 会静默出错

**W-02：`handler.Metrics` 方法签名将 `*metrics.Collector` 暴露给 handler 层，造成跨包耦合**

- 位置：`internal/handler/handler.go:104`
- 问题：handler 包直接依赖 metrics 包，若后续替换统计后端（如换成 Prometheus）需要同时修改 handler
- 建议：定义一个 `StatsProvider` interface，handler 依赖接口而非具体类型
- 处理决定：**接受风险**——当前项目规模小，过早抽象增加复杂度，后续有需要再重构

## Info（供参考）

- `RegisterRoutes` 方法在 handler 包中仍然存在但未被调用（遗留自限流功能迭代），可在后续清理
- golangci-lint 未安装，建议补充：`brew install golangci-lint`

## 结论

**Critical = 0。W-01 已修复（补充 `Write()` 拦截，新增测试覆盖）；W-02 接受风险。QA: PASSED。**
