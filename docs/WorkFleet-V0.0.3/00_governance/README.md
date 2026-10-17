---
id: WF-V0.0.3-INDEX
type: index
title: WorkFleet V0.0.3 版本说明与索引
status: active
version: V0.0.3
created: 2026-10-17
updated: 2026-10-17
---

# WorkFleet V0.0.3 · 版本说明与索引

## 1. 本版定位
- 基于 `nevermeetagain/WorkFleet` main `df09998`（2026-10-17 12:46 +0800）与六个参考项目的 V0.0.2 代码级分析，**以 WorkFleet 新仓、无代码的现实重新推演一次项目**。
- 产出：18 维全景分析、待定项方案比较、已拍板决策、需求增补、QA 记录。
- 本版**不含**实现代码、契约文件、迁移文件、任务卡（这些在待用户裁定项关闭后的 V0.0.4 规划版产出）。

## 2. 目录组织说明
- 用户裁定（DEC-042）：每个版本在 `docs/` 下新建子目录（本版 `docs/WorkFleet-V0.0.3/`）；版本内部按 `docs/项目完整文档体系.txt` §4 的信息类型分类，只建用得上的目录（§3.3“完整不等于文件多”）。
- V0.0.1、V0.0.2 保持原样，不回溯重排（§3.6 历史不覆盖）。
- 本版已建：`00_governance/`（入口）、`01_product/`（使用说明）、`02_requirements/inbox/`（原始说明书、增补需求）、`03_solution/`（分析、方案比较、决策）、`08_knowledge/`（事实基线、QA 记录）。V0.0.4 起补 `04_planning/`、`05_execution/`、`06_validation/`。
- 所有 QA 的用户原话与意见逐条记入 `08_knowledge/meetings/qa-log.md`。

## 3. 文件索引
| 文件 | 内容 | 状态 |
|---|---|---|
| `08_knowledge/fact-baseline.md` | 仓库、参考项目、平台约束的已核实事实 | active |
| `03_solution/analysis-18-dimensions.md` | 需求/前端/后端/数据/交互/逻辑/组件/复用/拓展/性能/配置/知识库/响应/存储/资源/通信/警告通知/异常报告，逐维对照六个参考项目并给出 WorkFleet 取舍 | active |
| `03_solution/option-comparison.md` | 每个待定项的方案、优劣、推荐、是否需要用户拍板 | active |
| `03_solution/decisions/decision-log.md` | 规划者直接拍板的 DEC-001…（可逆、有证据、不涉及用户偏好/资金/法务） | approved（可被用户推翻） |
| `02_requirements/inbox/REQ-INBOX-20261017-002-需求增补.md` | 推演发现、原需求未覆盖的增补需求（G1–G12） | proposed |
| `08_knowledge/meetings/qa-log.md` | 与用户的关键问答：问题、选项、推荐、用户原话、意见要点、落点 | active |
| `02_requirements/inbox/REQ-INBOX-20261017-001-原始设计说明书.md` | 用户设计说明书原文（逐字） | received |
| `01_product/user-guide.md` | 大白话使用说明（给用户和朋友看） | draft |

## 4. 标签
`已确认`（有直接证据）/`部分确认`（推断或单一来源）/`证据不足`（未验证）；决策状态 `approved`（已拍板）/`pending-user`（待用户）。

## 5. 与前版关系
- V0.0.1、V0.0.2 研究包为参考资料（REFERENCE）；其中对旧内部项目代码的引用已按用户要求移除（DEC-036），依赖“同仓 / 闭源”的结论（C2 82 分、A-10、A-45、相关体检类 PoC）在本版判为失效，见 `08_knowledge/fact-baseline.md §3`。
- `AnalyzeOthers/` 为其他模型分析，作为待审查输入，其中已识别的事实错误见 `08_knowledge/fact-baseline.md §4`。
