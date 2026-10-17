---
id: WF-CURRENT-PLAN
type: plan
title: 当前执行计划（S0 步行骨架启动）
status: active
version: V0.0.4
created: 2026-10-17
owner: 规划 Agent
reviewer: 用户
sources: [04_planning/slices.md, 04_planning/dag.md, 04_planning/ownership-matrix.md, 04_planning/cost-budget.md, 05_execution/task-index.md, 02_requirements/product-requirements.md, REQ-INBOX-20261017-003, docs/项目完整文档体系.txt §14/§40, docs/项目开发-多方案评审标准指令.txt 模块十七]
---

# Current Plan

## 1. 当前目标
**按 S0（步行骨架）启动 v1 开发**，交付 M0：从零代码到一条可演示、可自动回归的最小端到端链路——

> 注册 → 生成配对码 → 本机节点配对上线 → Web 发消息 → FakeAgent 回声显示；错误统一格式；一张表一次迁移。（`slices.md` S0）

S0 被选为第一刀的理由（`slices.md` 排序理由）：它打通“中转 ↔ 节点协议”这一最大技术未知，并为后续所有切片建立脚手架、契约生成、迁移、守卫与测试替身。

## 2. 范围
### Included（本轮）
| 任务 | 内容摘要 | 所有者 |
|---|---|---|
| TASK-001 | Monorepo 脚手架、根白名单文件、AGENTS.md、Makefile 骨架 | Agent-Guard |
| TASK-002 | 契约包构建：JSON Schema → TS 类型、ajv 校验器、示例校验测试、生成物漂移检查 | Agent-Contract |
| TASK-003 | 迁移运行器（relay/node 共用）+ 应用 0001 + 仓储基类（Kysely） | Agent-Data |
| TASK-004 | 中转启动层：Fastify、core、/health | Agent-Relay |
| TASK-005 | identity + tenancy：注册/登录/登出/me、会话 Cookie + CSRF、权限拦截器 | Agent-Relay |
| TASK-006 | devices：配对码、claim、node-gateway WSS（hello/welcome/ack/ping、outbox 续传、去重） | Agent-Relay |
| TASK-007 | 节点启动层：单实例锁、relay-link（单中转）、`workfleet-node pair`、本地 outbox 续传 | Agent-Node |
| TASK-008 | testkit：FakeAgent、FakeChannel、FakeRelay | Agent-QA |
| TASK-009 | Web 骨架：路由、登录/注册/配对/设备列表页、data-access、UX 状态组件 | Agent-App |
| TASK-010 | 中转 Web 渠道最小闭环：conversations/messages API、/api/v1/stream、prompt/output 转发 | Agent-Relay |
| TASK-011 | 节点回声执行面 | Agent-Node |
| TASK-012 | Web 聊天页（最小） | Agent-App |
| TASK-013 | 步行骨架 E2E（Playwright + 真中转 + 真节点 + FakeAgent） | Agent-QA |
| TASK-014 | CI 守卫：dependency-cruiser、根污染、命名、gitleaks、契约测试、三平台矩阵 | Agent-Guard |

### Excluded（本轮不做）
- S1…S10 的全部任务（TASK-021 及以后）。例外：`dag.md` 把 TASK-209（安装部署脚本，S10）放在 W5，**允许**在 S0 期间由 Agent-Guard 提前启动，但**不计入** M0 退出条件。
- 任何真实 IM 渠道、真实 ACP 智能体、总控、模型调用。
- 任何性能优化（`baseline-metrics.md §0`：没有基线前禁止优化任务）。
- 契约语义变更（契约包已冻结，`03_solution/contracts/README.md §4`）。

## 3. 关联需求
REQ-F-001（本机节点）、REQ-F-002（云中转与多租户）、REQ-F-003（权限拦截器部分，TASK-005）、REQ-F-015（Web 控制台对话，最小闭环）；REQ-NF-004（安全默认与 gitleaks）、REQ-NF-006（三平台矩阵）、REQ-NF-009（可测试）；REQ-C-001（TS/Node 22/React）、REQ-C-007（仓库治理）。

## 4. 关联方案
- 执行方案：`03_solution/solutions/SOL-001-v1交付方案.md`
- 架构：`03_solution/architecture.md`（§3 部署单元、§5 依赖方向、§6.4 Web 对话）
- 决策：ADR-001（部署分两侧）、ADR-002（契约唯一源）、ADR-003（SQLite）、ADR-004（Monorepo）、ADR-005（中转↔节点协议）、ADR-006（鉴权）、ADR-008（前端）、ADR-009（后端栈）、ADR-011（守卫）、ADR-012（命名）
- 契约：`packages/contracts/`（索引 `03_solution/contracts/README.md`）；迁移 `database/migrations/{relay,node}/0001_init.sql`

## 5. 交付物
1. 可安装的 Monorepo 骨架（根白名单文件、`Makefile`：`make test` / `make lint` / `make guard`）。
2. `packages/contracts` 生成物与漂移检查；`packages/testkit`。
3. `apps/relay`：/health、注册登录、配对码、node-gateway WSS、Web 渠道最小 API 与流。
4. `apps/node`：单实例、`workfleet-node pair`、relay-link、回声执行面。
5. `apps/web`：登录/注册/配对/设备列表/最小聊天页。
6. CI：守卫 + 三平台单测矩阵 + ubuntu E2E。
7. 证据：EVD-001…EVD-014（每个任务一份，`06_validation/evidence/README.md`）；VAL-013（M0 验收）。

## 6. Work Packages
本项目以**垂直切片**作为 Work Package（`00_governance/document-standard.md §4.2`）。

| WP | 切片 | 状态 |
|---|---|---|
| S0 | 步行骨架 | **本轮执行** |
| S1 | 真实 ACP + Web 对话 | 待 M0 |
| S2 | 微信管理模式 | 待 M1 |
| S3 | 项目·多设备·多中转·写保护 | 待 M2 |
| S4 | 输入广度 | 待 M1（`milestones.md` 依赖图） |
| S5 | 飞书 + 团队/通知 + 汇总屏障 | 待 M2 |
| S6 | 其余四个 IM + 健康告警 | 待 M2 |
| S7 | 多用户·权限·审计·分身 | 待 M2/M3/M5 |
| S8 | 模型配置 + 总控把关 | 待 M3 |
| S9 | 总控会议 + 导入任务 | 待 M8 |
| S10 | 体验与运维（v1 验收） | 待 M6/M8（及 M0…M9 全部退出） |

## 7. 依赖
- **契约链**：TASK-002 冻结生成物前，任何实现任务不得并行（`dag.md §5`）。
- **外部**：Node 22 LTS、pnpm、SQLite/better-sqlite3、Fastify、ws、React/Vite、Playwright、GitHub Actions 三平台 runner（`00_governance/dependencies.md` DEP-01…34；版本由 TASK-001 首次锁定）。
- **人**：无（S0 不需要真机扫码，不需要用户裁定即可开工）。U-08（工期人力）不阻塞开工，只影响排期承诺。

## 8. 风险
| 风险 | 对本轮的影响 | 应对 |
|---|---|---|
| R-03 v1 范围大 | S0 若拖延，关键路径整体后移 | 严格只做 Included；熔断（`cost-budget.md §4`） |
| R-04 跨境链路 | S0 E2E 在本地/同城跑，不暴露跨境问题 | 跨境测量放 TASK-041 与 TASK-210 |
| R-09 三平台差异 | TASK-007 单实例锁、TASK-014 矩阵可能只在某平台失败 | 三平台矩阵从 S0 起就是 PR 硬门禁 |
| R-10 依赖版本漂移 | 首次锁定版本 | TASK-001 写锁文件，`dependencies.md` 回填 |
| A-13 better-sqlite3 预编译 | Windows/macOS 安装可能需编译 | TASK-003/014 矩阵首日验证 |
| 文档不一致（见 `08_knowledge/fact-baseline.md §5`） | 任务卡引用的路径/编号可能与现状不符 | 执行者遇冲突标 blocked，不自行改上层文档 |

## 9. 退出条件（= M0 退出条件）
1. TASK-001…014 全部 done（Done 定义见 §11）。
2. TASK-013 E2E 由独立验证者判定 PASS，VAL-013 与 EVD-013 齐全。
3. 在干净机器上按 S0 演示脚本复现一遍，录屏/截图入 EVD-013。
4. 故意违规样例（跨模块深层 import、根目录新文件、提交假密钥）在 PR 上被 `make guard` / CI 拦截，结果入 EVD-014。
5. `pnpm contracts:gen && git diff --exit-code` 无漂移（ADR-002）。
6. 风险表中 R-03/R-09/R-10 与 A-13 已复核并更新。

## 10. 当前状态（2026-10-17）
- V0.0.4 规划冻结；**业务代码 0 行**；84 张任务全部 `todo`（`05_execution/task-index.md`）。
- 契约包与 0001 迁移已在工作区生成（未提交、未在 CI 中验证）。
- 任务卡文件 `05_execution/tasks/TASK-xxx.md` 正在落盘（读取时仅见部分），以 `task-index.md` 与 `tasks.v1.json` 为准。
- 尚未开始任何 S0 任务。

## 11. 完成定义（Done）
> 照抄用户规划指令的 Done 口径：

**Done = 所有权内 diff 符合任务 ∧ 验收条目逐条有结果 ∧ 自动测试或脚本可复现 ∧ evidence 能让一周后的人复现 ∧ make guard 通过 ∧ 无新增同类错误记录 ∧ 未修改冻结契约**

逐项解释（判定由独立验证者执行，见 `06_validation/validation-plan.md`）：
| 条件 | 怎么判 |
|---|---|
| 所有权内 diff 符合任务 | PR diff 中每个文件都落在任务卡“允许修改”内，且不触碰“禁止修改”；脚本按前缀比对（`ownership-matrix.md`） |
| 验收条目逐条有结果 | 任务卡第 6 节每一条都有 PASS/FAIL/UNKNOWN 与证据指针，不允许“整体通过” |
| 自动测试或脚本可复现 | 第 7 节验证命令可直接复制执行并得到同样结果 |
| evidence 能让一周后的人复现 | EVD 目录含命令、输出、环境、commit、复现步骤（`06_validation/evidence/README.md`） |
| make guard 通过 | 在合并前的最终提交上运行并留存输出 |
| 无新增同类错误记录 | 本任务未引入与已登记问题同类的新错误（如同类守卫违规、同类测试失败、同类死信）；对照 VAL 的 Issues 与 CI 历史 |
| 未修改冻结契约 | diff 不含 `packages/contracts/**`、`database/migrations/**` 已有文件（契约变更必须是独立任务 + ADR） |

任一不满足 → 不是 done；状态只能是 `in_review`、`blocked` 或退回 `in_progress`。

## 12. 防自证循环规则
依据 `docs/项目开发-多方案评审标准指令.txt` 模块十七与文档体系 §50：
1. **执行者不得自证**：实现任务的 Agent 不能给自己的任务出 PASS；验收由独立验证者完成，独立验证者不参与该任务实现、不修改被验代码。
2. **证据先于结论**：结论必须指向 EVD 中可复现的命令输出 / 截图 / 日志；“我已完成”“测试应该能过”不构成证据（文档体系 §50.3）。
3. **AI 分析不升格为事实**：AI 产生的分析（含 `docs/AnalyzeOthers/`、V0.0.1/V0.0.2 研究包、本轮规划中的“推断”项）不能被后续任务当作已确认事实引用；要升格必须有实测证据并更新证据标签。
4. **不回写上层事实**：执行中发现需求 / ADR / 契约 / 范围冲突时，标 `blocked` 并记录原因、缺失信息、已尝试方案、需谁决策；不得改上层文档“让测试变绿”（文档体系 §41、§50.4）。
5. **测试不得为通过而改**：修改既有测试断言需在 PR 说明理由并由独立验证者确认；禁止删除或跳过失败用例来达成 PASS。
6. **熔断**：同一任务连续 2 次验收 FAIL → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked（`cost-budget.md §4`）。

## 13. 第一刀与启动顺序
第一刀 = **S0**；启动顺序按 `dag.md` 波次（每波 ≤3 个写入 Agent，文件所有权两两不相交）：

```text
W1  TASK-001（Guard）                                    ← 先建骨架与 Makefile
W2  TASK-002（Contract） ∥ TASK-003（Data）              ← 契约生成 与 迁移运行器 并行
W3  TASK-004（Relay） ∥ TASK-007（Node） ∥ TASK-008（QA）
W4  TASK-009（App） ∥ TASK-014（Guard）
W5  TASK-005（Relay） ∥ TASK-011（Node）［∥ TASK-209（Guard，可选提前，不计入 M0）］
W6  TASK-006（Relay）
W7  TASK-010（Relay）
→   TASK-012（App）      （依赖 009、010；dag 波次 W10）
→   TASK-013（QA）       （依赖 011、012；dag 波次 W13）＝ M0 验收
```
说明：
- 上表只摘 `dag.md §4` 中属于 S0 的任务；同一波次里属于 S1/S3 的任务（如 W6 的 TASK-021、TASK-061）在本轮**不启动**，M0 退出后按 dag 波次继续。
- TASK-002 完成并冻结生成物后，W3 起的实现任务才可并行（契约链）。
- opus 券：S0 用 3 张（TASK-005、TASK-006 执行 + 1 张切片前契约审），未超限（`cost-budget.md §2`）。
- M0 退出后进入 S1（TASK-021 起），并同时更新本文件。

## 14. 待用户裁定（不阻塞 S0）
- U-08 / A-07：v1 工期与人力预算。
- R-15：S2（TASK-045）与 S8（TASK-164）opus 券各超 1 张，默认按替代方案执行。
- `ownership-matrix.md §1` 对规划指令 §8.1 的一处偏离（仓储随模块归属）。

## 15. 变更记录
| 日期 | 旧状态 | 新状态 | 原因 | 变更者 |
|---|---|---|---|---|
| 2026-10-17 | — | active | V0.0.4 规划冻结，按 S0 启动 | 规划 Agent |
