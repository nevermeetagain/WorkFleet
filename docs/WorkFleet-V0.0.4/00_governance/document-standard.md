---
id: WF-DOC-STANDARD
type: project
title: WorkFleet 文档规范（元数据 / Type / ID / 状态 / 命名）
status: active
version: V0.0.4
created: 2026-10-17
updated: 2026-10-17
owner: 规划 Agent
reviewer: 用户
sources: [docs/项目完整文档体系.txt §3/§4/§20/§30–§36, DEC-042, ADR-012, 05_execution/task-template.md]
---

# WorkFleet 文档规范

> 本文是 `docs/项目完整文档体系.txt`（下称“文档体系”）在本项目的落地版，只写**本项目的具体取值与偏离**；文档体系原文是上位规范，二者冲突时以文档体系为准，偏离点必须在本文 §8 登记。

## 1. 适用范围与版本目录
- 每个文档版本在 `docs/` 下新建子目录：`docs/WorkFleet-V0.0.x/`（用户裁定，DEC-042，QA-13）。
- 版本内部按文档体系 §4 分 `00_governance … 09_archive`，**按需建目录**（文档体系 §3.3“完整不等于文件多”，禁止为凑完整创建空文档）。
- 旧版本目录（V0.0.1–V0.0.3）只读，不回溯重排（文档体系 §3.6）。被本版取代的旧决策在 `09_archive/superseded/README.md` 登记，原文保留在原处。
- 产品版本（v1、v2…）与文档版本（V0.0.x）是两套编号（`04_planning/roadmap.md` 规则）。

## 2. Front Matter（文档体系 §30）
所有正式文档以 YAML Front Matter 开头。

### 2.1 必填字段
| 字段 | 规则 | 例 |
|---|---|---|
| `id` | 见 §4，稳定不变，不随标题改 | `REQ-F-009`、`WF-ROADMAP` |
| `type` | 见 §3 | `requirement-feature` |
| `title` | 中文标题，与正文一级标题一致 | 输出端：微信 ClawBot |
| `status` | 见 §5，表达生命周期而非个人意见 | `active` |
| `version` | 所在文档版本目录名的版本号 | `V0.0.4` |
| `created` | 首次创建日期，Asia/Shanghai，`YYYY-MM-DD` | `2026-10-17` |

### 2.2 选填字段
`updated`、`owner`、`reviewer`、`sources`（上游 DEC/ADR/REQ/QA/文件路径列表）、`related`、`superseded_by`、`supersedes`、类型专属字段（如需求的 `priority`、`slices`；任务的 `slice`、`tier`、`size`）。

### 2.3 时间与引用写法
- 文档内日期时间一律 CST（UTC+08:00），精确到分钟时写 `2026-10-17 18:08`；与 API/DB 的时间格式（ADR-012：RFC 3339 UTC）不是一回事。
- 引用其他文档：写 ID（`DEC-044`、`ADR-005`、`REQ-F-015`、`QA-26`）或相对版本根的路径（`03_solution/architecture.md §6.1`）；引用旧版本写完整路径（`docs/WorkFleet-V0.0.3/...`）。
- 任何事实性断言须带出处或证据标签（§6）；不得编造。

## 3. Type 取值（文档体系 §31）
| 本项目用 | 文档体系标准名 | 用于 |
|---|---|---|
| `project` | project | 文档规范、项目级说明 |
| `product` | product | 01_product 全部 |
| `requirement-inbox` | requirement-inbox | 02_requirements/inbox |
| `requirement-feature` / `requirement-non-functional` / `requirement-constraint` | 同名 | features / non-functional / constraints |
| `solution` · `design` · `architecture` · `decision` | 同名 | 03_solution |
| `plan` · `milestone` · `release-plan` · `work-package` | 同名 | 04_planning |
| `task` | task | 05_execution/tasks |
| `validation` · `evidence` | 同名 | 06_validation |
| `release` | release | 07_release |
| `risk` · `assumption` · `dependency` · `project-map` | 同名 | 00_governance |
| `knowledge` · `meeting` · `retrospective` | 同名 | 08_knowledge |

**已存在的别名（不改原文件，读时按右列理解）**：`adr`→decision；`requirement`→按目录判定为 feature/non-functional/constraint；`requirement-baseline`、`backlog`、`index`、`glossary`、`contract-index`、`template`→project（治理/索引类）；`roadmap`→plan；`qa-log`→meeting；`baseline`（事实基线）→knowledge。新文件一律使用上表左列取值。

## 4. ID 规则（文档体系 §32）
### 4.1 实例类文档（一事一文件）
| 前缀 | 含义 | 文件位置与命名 | 编号 |
|---|---|---|---|
| `REQ-INBOX-YYYYMMDD-NNN` | 原始需求 | `02_requirements/inbox/REQ-INBOX-20261017-001-<短名>.md` | 当日三位序号 |
| `REQ-F-NNN` / `REQ-NF-NNN` / `REQ-C-NNN` | 正式需求 | `features/REQ-F-009-<中文短名>.md` 等 | 三位，按类型独立计数 |
| `SOL-NNN` | 执行方案 | `03_solution/solutions/SOL-001-<短名>.md` | 三位 |
| `DESIGN-NNN` | 详细设计 | `03_solution/design/DESIGN-001-<短名>.md` | 三位（architecture §8 已占用 001–022） |
| `ADR-NNN` | 技术决策 | `03_solution/decisions/ADR-001-<短名>.md` | 三位，只增不复用 |
| `TASK-NNN` | 原子任务 | `05_execution/tasks/TASK-001.md` | 按切片分段（task-index：S0 001–020 … S10 201–220） |
| `VAL-NNN` | 验证记录 | `06_validation/acceptance/VAL-013.md` | **与被验证任务同号** |
| `EVD-NNN` | 证据目录 | `06_validation/evidence/EVD-013/` | **与任务同号** |
| `REL-NNN` | 发布记录 | `07_release/release-records/REL-001.md` | 三位 |

### 4.2 登记册条目（在一个文件内管理，不单独成文件）
| 前缀 | 含义 | 所在文件 | 说明 |
|---|---|---|---|
| `R-NN` | 风险 | `00_governance/risks.md` | 等价文档体系 `RISK-xxx`；沿用 architecture §9 已用的 R-01…R-06 |
| `A-NN` | 假设 | `00_governance/assumptions.md` | 等价 `ASM-xxx`；与未知登记册 `U-NN` 一一或多对一对应 |
| `DEP-NN` | 外部依赖 | `00_governance/dependencies.md` | 等价 `DEP-xxx` |
| `U-NN` | 未知项 | `02_requirements/product-requirements.md §7` | 沿用 V0.0.3 编号 |
| `M0…M10` | 里程碑 | `04_planning/milestones.md` | 等价 `MILE-xxx`；与切片 S0…S10 一一对应 |
| `S0…S10` | 垂直切片（= Work Package） | `04_planning/slices.md` | 等价 `WP-xxx` |
| `BL-NNN` / `RJ-NNN` | 待办 / 被拒 | `backlog.md` / `rejected.md` | — |
| `QA-NN` | 关键问答 | `08_knowledge/meetings/qa-log.md` | 按时间只追加；插入既有两条之间的补记用小数（如 QA-26.5） |
| `DEC-NNN` | V0.0.3 决策 | `docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md` | 冻结于 V0.0.3；V0.0.4 起新决策写 ADR |
| `G1…G25` | V0.0.3 需求增补（原文无连字符） | `docs/WorkFleet-V0.0.3/02_requirements/inbox/REQ-INBOX-20261017-002-需求增补.md` | 只引用 |
| `PG-NN` / `SM-NN` | 产品目标 / 成功指标 | `01_product/product-goals.md` / `success-metrics.md` | — |
| `BM-NN` | 基线指标 | `04_planning/baseline-metrics.md` | 首次测量后口径冻结 |
| `GD-NN` | 自动化守卫（PR 硬门禁） | `06_validation/validation-plan.md §4` | 用 GD 而非 G，避免与 G1…G25 混淆 |
| `F-NN` | 已核事实 | `08_knowledge/fact-baseline.md` | — |
| `L-NN` | 经验教训 | `08_knowledge/lessons-learned.md` | — |

### 4.3 单例文档
无实例编号的单例文档用 `WF-<英文大写短名>`（如 `WF-ARCH`、`WF-ROADMAP`、`WF-CURRENT-PLAN`）。同一 ID 跨版本延续表示“同一份文档的新版本”，`version` 字段区分。

### 4.4 文件命名
- 实例类：`<ID>-<中文或英文短名>.md`；任务、验证只用 ID（`TASK-001.md`、`VAL-001.md`）。
- 单例：小写英文 + 连字符（`current-plan.md`、`baseline-metrics.md`）。
- 禁止 `*_final*`、`*_old*`、`*_copy*`、`*.bak`（`docs/项目完整目录结构.txt` 第六节 AI 硬约束）。
- 证据目录内文件名见 `06_validation/evidence/README.md`。

## 5. 状态（文档体系 §20、§33、§34）
### 5.1 通用文档状态
`draft → proposed → under-review → approved → active → superseded / archived`；特殊：`rejected`、`cancelled`。

| 类型 | 允许的状态 | 本项目补充 |
|---|---|---|
| 需求、Solution、Design | draft / proposed / approved / superseded / rejected / cancelled | — |
| ADR | proposed / accepted / rejected / superseded | 文档体系 §22 原文 |
| 契约索引 | frozen | 冻结后改契约 = 新任务 + ADR（`03_solution/contracts/README.md §4`） |
| 架构 | approved-for-planning | 已存在取值，等价 approved（仅限规划，代码落地后转 active） |
| 计划、登记册、索引 | draft / active / superseded | — |
| 验证记录 | 结论字段见 §5.3，文档本身 active | — |

### 5.2 任务状态
以 `05_execution/task-template.md` 为准：`todo | ready | in_progress | in_review | blocked | done | cancelled`。与文档体系 §20 的对应：todo≈draft、in_review≈review、done≈verified+completed（Done 定义见 `04_planning/current-plan.md §11`，独立验证 PASS 前不得标 done）。

### 5.3 验证结论
独立验证者只输出 **PASS / FAIL / UNKNOWN**（`06_validation/validation-plan.md`）。文档体系 §25 的 PARTIAL 记为 FAIL（附已通过条目），BLOCKED 记为 UNKNOWN（附阻塞原因）。

### 5.4 状态变更记录（文档体系 §34）
重大状态变化在文档末尾“变更记录”表登记：旧状态、新状态、时间（CST）、原因、变更者。superseded 文档在 front matter 写 `superseded_by`，**不删除原文**（文档体系 §3.6、§36）。

## 6. 证据标签
沿用 V0.0.3：`已确认`（有直接证据）/ `部分确认`（推断或单一来源）/ `证据不足`（未验证）/ `推断`（规划者推理）。负证据写“在已扫描范围内未找到”，不写“不存在”（`docs/项目开发-多方案评审标准指令.txt` 4.8 负证据规则）。

## 7. 单一事实源（文档体系 §3.2）
| 信息 | 权威来源（本版） |
|---|---|
| 产品愿景/目标/范围/指标 | `01_product/` |
| 正式需求 | `02_requirements/features|non-functional|constraints/`；基线汇总 `product-requirements.md` |
| 技术决策 | `03_solution/decisions/ADR-*`（V0.0.3 的 DEC 冻结只读） |
| 架构 | `03_solution/architecture.md` |
| 契约 | 仓库 `packages/contracts/`（ADR-002），文档只做索引 |
| 路线图 / 里程碑 / 当前计划 | `04_planning/roadmap.md` / `milestones.md` / `current-plan.md` |
| 任务清单与状态 | `05_execution/task-index.md`（机器源 `tasks.v1.json`）与 `tasks/TASK-*.md` |
| 验证与证据 | `06_validation/acceptance/VAL-*`、`evidence/EVD-*/` |
| 风险/假设/依赖 | `00_governance/risks.md` / `assumptions.md` / `dependencies.md` |
| 用户原话与意见 | `08_knowledge/meetings/qa-log.md`（DEC-042） |
| 文档版本变化 | `07_release/changelog.md` |

其他文档只引用、不复制维护第二份。

## 8. 与文档体系的偏离登记
| # | 偏离 | 原因 | 依据 |
|---|---|---|---|
| D1 | 按版本建子目录，跨版本存在重复 | 用户裁定 | DEC-042、QA-13 |
| D2 | 风险/假设/依赖用 `R-`/`A-`/`DEP-` 短号，里程碑 `M0…`，Work Package 用切片 `S0…` | 与 architecture §9、slices.md 已用编号一致，避免改号 | 本文 §4.2 |
| D3 | 验证结论三值（PASS/FAIL/UNKNOWN） | 用户规划指令要求独立验证者只输出三值 | `06_validation/validation-plan.md` |
| D4 | 任务状态用 task-template 的 7 值 | 模板已冻结并被 84 张任务引用 | `05_execution/task-template.md` |
| D5 | V0.0.3 决策用 DEC 编号且集中在一个 decision-log | 历史文档不改；V0.0.4 起回到 ADR 单文件 | 文档体系 §22–23 |

## 9. 防自证循环（`docs/项目开发-多方案评审标准指令.txt` 模块十七）
- AI 产生的分析（含 `docs/AnalyzeOthers/`、V0.0.1/V0.0.2 研究包）是**参考输入**，不自动成为正式设计依据；采纳必须经 ADR 或需求文件显式引用，并标证据标签。
- 正式文档中的“规划者推断”必须标 `推断`/`部分确认`，后续文档引用时不得把标签去掉。

## 10. 变更记录
| 日期 | 变更 | 变更者 |
|---|---|---|
| 2026-10-17 | 初版（draft→active），随 V0.0.4 规划冻结 | 规划 Agent |
