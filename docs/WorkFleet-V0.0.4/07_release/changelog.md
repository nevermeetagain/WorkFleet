---
id: WF-CHANGELOG
type: release
title: 文档版本变更日志
status: active
version: V0.0.4
created: 2026-10-17
sources: [docs/WorkFleet-V0.0.3/00_governance/README.md, REQ-INBOX-20261017-003, 08_knowledge/meetings/qa-log.md QA-27, 08_knowledge/fact-baseline.md]
---

# Changelog（文档版本）

> 本文件记录**文档版本**（`docs/WorkFleet-V0.0.x/`）的变化；产品版本（v1/v2…）的功能变化记在 `04_planning/roadmap.md`。尚无任何产品发布（无 REL 记录）。
> 格式：每个版本按“新增 / 变更 / 取代 / 已知问题”分组。

## [V0.0.4] — 2026-10-17 · 规划冻结版
基线：分支 `docs/v0.0.4`，基于 `f7f603c`（docs/v0.0.3 头）；`origin/main` = `df09998`。触发：用户 2026-10-17 18:08 指令（REQ-INBOX-20261017-003、QA-27），否决“先切一小片”，要求按三份规范建立完整文档体系与全维度设计。

### 新增
- **完整文档体系目录** `00_governance … 09_archive`（按 `docs/项目完整文档体系.txt` §4，DEC-042）。
- 00_governance：文档规范（document-standard）、术语表、角色与责任、风险登记（R-01…R-16）、假设登记（A-01…A-13，对应 U-02…U-08）、外部依赖登记（DEP-xx，版本待锁定、许可待核实）。
- 01_product：产品愿景、产品目标（PG-01…10）、产品范围（v1 In/Out）、成功指标（SM-01…15，基线全部“尚无”）、大白话使用说明 v1 设计态（含“用微信管多个 ZCode 和 Claude Code”分步操作）。
- 02_requirements：v1 需求基线；REQ-F-001…036、REQ-NF-001…011、REQ-C-001…009 单文件；backlog（BL-001…011）；rejected（RJ-001…004）；inbox REQ-INBOX-20261017-003（开工指令原话）。
- 03_solution：v1 总体架构；ADR-001…014；契约冻结包索引（唯一源在 `packages/contracts/`）；详细设计 DESIGN-0xx 与执行方案 SOL-001（由其他规划任务落盘，以 project-map 状态为准）。
- 04_planning：路线图（延续 V0.0.3 并更新）、里程碑 M0…M10、垂直切片 S0…S10、依赖 DAG、所有权矩阵、档位与成本预算、基线指标（BM-01…05）、当前计划（S0 启动、Done 定义、防自证循环）、规划步骤索引 STEP-01…16。
- 05_execution：任务模板（16 项）、任务索引（84 张）、`tasks.v1.json`、任务卡目录。
- 06_validation：验证计划（六层验证、三值结论、守卫清单 GD-01…12）、验收记录模板（VAL）、证据目录规则（EVD）。
- 07_release：本文件。
- 08_knowledge：QA 记录（延续 V0.0.3 全部条目，追加 QA-26.5、QA-27）、规划快照与事实基线、经验教训。
- 09_archive：被 ADR 取代的 V0.0.3 决策登记（不删原文）。
- 仓库工作区（未提交）：`packages/contracts/`（契约 schema）、`database/migrations/{relay,node}/0001_init.sql`（由其他规划任务产出，见 fact-baseline）。

### 变更
- **默认渠道**：Web 控制台为默认渠道，6 个 IM 均为可选（DEC-057 落入 REQ-F-015）。
- **v1 范围**：全部主流 IM（微信、飞书/Lark、QQ、钉钉、Telegram、Discord）与 DEC-055 清单 13 个 ACP 智能体 + Coze + Webhook 进入 v1 需求基线。
- **路线图**：渠道健康告警 v2 → v1（REQ-F-030）；急停、doctor/配置导入导出、恢复密钥显式列入 v1；执行 Agent 分档（Q-15）行 cancelled；新增“按触发条件”节（BL-010）。
- **使用说明**：从“微信/飞书必选、总控规划中”更新为 v1 设计（默认网页、多设备、多中转、总控、公司场景）。
- **决策形式**：V0.0.3 的 DEC 冻结只读；V0.0.4 起新决策写 ADR 单文件（文档体系 §22–23）。

### 取代（superseded，原文保留）
- DEC-002/016/022/030 的“单机网关 / 只绑 127.0.0.1 / 不需要公网 IP”部分 → ADR-001（及 DEC-051）。
- DEC-025、DEC-052 的输入端清单 → DEC-055 / ADR-007。
- 详见 `09_archive/superseded/README.md`。

### 已知问题
- 业务代码 0；守卫、CI、锁文件均未落地，所有“可验证陈述”尚未验证。
- U-08 工期与人力未裁定；R-15 opus 券超额待批准。
- 文档内部不一致若干（如 TASK-210 入边缺 M4/M7/M9 收尾任务、ADR-011 Related 写 CI 为 TASK-008 而任务索引为 TASK-014），见 `08_knowledge/fact-baseline.md §5`。

## [V0.0.3] — 2026-10-17
- 以新仓、无代码的现实重新推演；产出 18 维分析、待定项方案比较、DEC-001…057、需求增补 G1…G25、QA 记录 QA-01…26、产品路线图、大白话使用说明、需求与场景代入核对。首次采用文档体系分类目录（DEC-042）。出处：`docs/WorkFleet-V0.0.3/00_governance/README.md`。

## [V0.0.2] — 早于 2026-10-17 12:46（main `df09998`）
- 六个参考项目与五个同类项目代码级分析、协议与端点矩阵、DDL 实测与评分底稿。出处：`docs/WorkFleet-V0.0.2/50-附录/02-V0.0.1到V0.0.2差异说明.md`。

## [V0.0.1]
- 初版研究包。出处：`docs/WorkFleet-V0.0.1/`。
