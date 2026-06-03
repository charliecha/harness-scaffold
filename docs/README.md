# docs/

项目文档根目录，按类型分三个子目录管理。

## 目录结构

```
docs/
  requirements/   # 功能需求（FR-XXX）
  architecture/   # 架构决策记录（ADR-XXX）
  reviews/        # QA 审查记录（RV-XXX）
```

每个子目录有 `INDEX.md` 维护该类文档的状态一览表。

## 开发新功能时

1. `docs/requirements/FR-XXX.md` — 需求分析师产出，用户确认
2. `docs/architecture/ADR-XXX.md` — 架构师产出，用户确认
3. 实现 → gatekeeper 通过
4. `docs/reviews/RV-XXX.md` — QA 产出
5. 更新三个 INDEX.md 中对应条目状态

## 编号规则

- 各类独立计数，三位数字：FR-001、ADR-001、RV-001
- 编号只增不减，废弃时标记 Deprecated，不删除文件
