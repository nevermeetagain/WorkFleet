---
id: WF-V0.0.4-README
type: governance
title: WorkFleet V0.0.4 文档入口
status: active
version: V0.0.4
created: 2026-10-17
---

# WorkFleet V0.0.4 —— v1 完整规划与设计（冻结版）

## 与前版关系
- V0.0.3：需求澄清与决策（DEC-001…057，QA-01…26）。本版不重复其内容，引用为准。
- V0.0.4：按 `docs/项目完整文档体系.txt` §4 建完整文档体系；按 `docs/项目完整目录结构.txt` 设计目标代码结构；按用户 12:32 规划指令输出 16 节（`04_planning/steps/`）；按 `docs/项目开发-多方案评审标准指令.txt` 做方案比较与证据标注（ADR 的 Options/Rationale）。
- 同时在仓库根落盘契约 `packages/contracts/` 与迁移 `database/migrations/`（规划指令 §11 允许路径）。

## 阅读顺序（10 分钟版）
1. `01_product/user-guide.md`（大白话怎么用）
2. `03_solution/architecture.md`（一页架构）
3. `02_requirements/product-requirements.md`（需求基线）
4. `04_planning/slices.md` → `dag.md` → `current-plan.md`（怎么做、先做什么）
5. `05_execution/task-index.md`（84 张任务卡）
6. `06_validation/self-check.md`（自检与待裁决 10 项）

## 15 个设计维度 → 文件
需求 `02_requirements/` · 前端 DESIGN-001 · 后端 DESIGN-002/003 · 数据 DESIGN-004 + 迁移 · 交互 DESIGN-005 · 逻辑 DESIGN-006 · 组件 DESIGN-007 · 复用 DESIGN-008 · 拓展 DESIGN-009 · 性能 DESIGN-010 · 配置 DESIGN-011 · 知识库 DESIGN-012 · 响应 DESIGN-013 · 存储 DESIGN-014 · 资源 DESIGN-015；另含通信 016、告警 017、异常 018、安全 019、总控 020、分身 021、模型费用 022。

完整清单见 `document-index.md`。
