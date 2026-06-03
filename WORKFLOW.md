# crypto-snapshot 工作流协议 (Layer 4: Workflow)

## 阶段状态机

```
[用户请求] → Phase 1: 需求确认
           → Phase 2: 架构设计
           → Phase 3: 实现
           → Phase 4: 守门人校验  ──失败──→ Phase 3
           → Phase 5: QA 审查     ──Critical──→ Phase 3
           → Phase 6: PM 验收     ──Reject──→ 对应阶段
           → [完成]
```

---

## Phase 1：需求确认

**触发条件**：用户提交功能请求。

**执行者**：需求分析师

**必须产出**：`REQUIREMENTS.md`（含功能需求、非功能需求、排除范围、每条需求的验收标准）

**进入下一阶段条件**：
- [ ] 用户明确确认 `REQUIREMENTS.md` 内容
- [ ] 每条功能需求有可验证的验收标准

**失败处理**：用户提出修改 → 需求分析师更新文档 → 重新确认。

---

## Phase 2：架构设计

**触发条件**：`REQUIREMENTS.md` 已由用户确认。

**执行者**：架构师

**必须产出**：`ARCHITECTURE.md`（含包结构、核心接口、数据流、技术选型）

**进入下一阶段条件**：
- [ ] `ARCHITECTURE.md` 存在且覆盖所有功能需求
- [ ] 守门人确认架构文档不包含安全风险描述（如明文存储密钥的方案）

**失败处理**：守门人发现安全风险 → 退回架构师修改。

---

## Phase 3：实现

**触发条件**：`ARCHITECTURE.md` 已审核通过。

**执行者**：开发者

**强制步骤**（缺一不可）：
1. 按 `ARCHITECTURE.md` 实现代码
2. 调用 **Build Skill**（`skills/build.md`）→ 必须 PASSED
3. 调用 **Test Skill**（`skills/test.md`）→ 必须 PASSED

**必须产出**：
- 源代码（符合 `ARCHITECTURE.md` 包结构）
- `bin/crypto-snapshot`（可执行文件）
- `coverage.out`（覆盖率数据）

**进入下一阶段条件**：
- [ ] Build Skill: PASSED
- [ ] Test Skill: PASSED（覆盖率须附数值）
- [ ] 开发者提交交接报告（含两个 Skill 的输出摘要）

**注意**：开发者通过 Skill 是"自评"，不是最终门。真正的门在 Phase 4。

---

## Phase 4：守门人校验

**触发条件**：Phase 3 交接报告提交。

**执行者**：守门人（自动化，无人工干预）

**唯一操作**：
```bash
bash scripts/gatekeeper.sh
```

**检查项**（见脚本内注释）：
- 无硬编码密钥
- golangci-lint 零警告
- 编译成功
- 竞态测试通过
- 覆盖率 ≥ 80%
- 版本元数据注入
- 无裸 fmt.Println

**结果**：
- exit 0 → **进入 Phase 5**，附完整脚本输出
- exit 非0 → **退回 Phase 3**，附失败项列表，开发者必须修复后重新提交

**严格规定**：守门人不得因任何理由手动放行失败项。

---

## Phase 5：QA 审查

**触发条件**：守门人 PASSED。

**执行者**：QA/Reviewer

**必须产出**：`review.md`（Critical / Warning / Info 分级）

**进入下一阶段条件**：
- [ ] Critical 问题数量 = 0
- [ ] 所有 Warning 问题有处理计划（修复或接受风险，须说明理由）

**失败处理**：Critical > 0 → 退回 Phase 3（开发者修复）→ 重回 Phase 4（守门人重新验证）。

---

## Phase 6：PM 验收

**触发条件**：QA 审查 PASSED。

**执行者**：PM

**操作**：逐条对照 `REQUIREMENTS.md` 中的验收标准检查。

**结果**：
- Accept：所有 FR/NFR 满足 → **流程完成**
- Reject：列出未满足项 + 回退到相应阶段

---

## 上下文纪律

每个阶段的 Agent 只持有以下上下文：
- 自己阶段的输入产物
- 自己角色的职责定义（`agents/ROLES.md`）
- 本工作流文档

**不得**将其他阶段的讨论历史带入当前阶段，防止认知污染。

---

## 产物清单

| 产物 | 创建阶段 | 创建者 |
|------|---------|--------|
| `REQUIREMENTS.md` | Phase 1 | 需求分析师 |
| `ARCHITECTURE.md` | Phase 2 | 架构师 |
| `bin/crypto-snapshot` | Phase 3 | 开发者（via Build Skill） |
| `coverage.out` | Phase 3 | 开发者（via Test Skill） |
| Gatekeeper 报告 | Phase 4 | 守门人（脚本输出） |
| `review.md` | Phase 5 | QA/Reviewer |
| 验收结论 | Phase 6 | PM |
