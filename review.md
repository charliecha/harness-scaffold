# review.md — 限流功能 QA 审查

审查时间：2026-06-03

## Critical（必须修复）

无。

## Warning（建议修复）

**W-01：`X-Forwarded-For` 信任未加限制**

- 位置：`internal/middleware/ratelimit.go:54`
- 问题：直接信任客户端传入的 `X-Forwarded-For` 头，恶意客户端可以伪造 IP 绕过限流（每次请求换一个假 IP）
- 建议：仅在已知反向代理场景下信任此头，或通过启动参数 `--trusted-proxy` 控制是否读取
- 当前风险：本项目无反向代理前提说明，直接部署时存在绕过风险
- 处理决定：**接受风险**——需求文档（REQUIREMENTS.md）未定义反向代理场景，可在后续迭代中加 `--trusted-proxy` flag

**W-02：limiter 无清理机制，长期运行内存持续增长**

- 位置：`internal/middleware/ratelimit.go:47`（`sync.Map` 只增不减）
- 问题：每个新 IP 创建一个 limiter 永不释放，高并发或 IP 扫描场景下内存无界增长
- 建议：后续迭代引入 TTL 淘汰（如定期清理超过 N 分钟未访问的 limiter）
- 处理决定：**接受风险**——需求文档排除范围内，单实例场景可接受，记录为 TODO

## Info（供参考）

- `RegisterRoutes` 方法在 `handler` 包中已不再被调用（路由改在 `main.go` 直接注册），可考虑后续清理，但不影响功能
- golangci-lint 未安装，建议补充：`brew install golangci-lint`

## 结论

**Critical = 0，Warning 均有明确处理决定。QA: PASSED，可进入 Phase 6。**
