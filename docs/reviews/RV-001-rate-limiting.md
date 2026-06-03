# RV-001 — 限流功能 QA 审查

**状态**：Passed
**审查时间**：2026-06-03
**关联需求**：[FR-001](../requirements/FR-001-rate-limiting.md)
**关联 ADR**：[ADR-001](../architecture/ADR-001-rate-limiting.md)

---

## Critical（必须修复）

无。

## Warning（建议修复）

**W-01：`X-Forwarded-For` 信任未加限制**

- 位置：`internal/middleware/ratelimit.go:54`
- 问题：直接信任客户端传入的 `X-Forwarded-For` 头，恶意客户端可以伪造 IP 绕过限流
- 建议：通过启动参数 `--trusted-proxy` 控制是否读取此头
- 处理决定：**接受风险**——需求文档未定义反向代理场景，后续迭代处理

**W-02：limiter 无清理机制，长期运行内存持续增长**

- 位置：`internal/middleware/ratelimit.go:47`（`sync.Map` 只增不减）
- 问题：每个新 IP 创建一个 limiter 永不释放
- 建议：后续迭代引入 TTL 淘汰
- 处理决定：**接受风险**——单实例场景可接受，后续迭代处理

## Info（供参考）

- `RegisterRoutes` 方法在 `handler` 包中已不再被调用，可考虑后续清理
- golangci-lint 未安装，建议补充：`brew install golangci-lint`

## 结论

**Critical = 0，Warning 均有明确处理决定。QA: PASSED。**
