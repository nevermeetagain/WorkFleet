---
id: WF-FACTS
type: knowledge
title: WorkFleet V0.0.4 规划快照与事实基线
status: active
version: V0.0.4
created: 2026-10-17
sources: [git（本地仓库，分支 docs/v0.0.4）, docs/WorkFleet-V0.0.3/08_knowledge/fact-baseline.md, 02_requirements/product-requirements.md, packages/contracts/, database/migrations/]
---

# 规划快照与事实基线

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断（`00_governance/document-standard.md §6`）。“已确认（本次核对）”指本文件编写时在仓库内用命令直接核对过。
> V0.0.3 的平台与参考项目事实（F-01…F-19）继续有效，原文见 `docs/WorkFleet-V0.0.3/08_knowledge/fact-baseline.md`，此处只引用不复制。

## 1. 规划快照
```yaml
planning_date: 2026-10-17            # Asia/Shanghai
repo: nevermeetagain/WorkFleet
git_branch: docs/v0.0.4
based_on_commit: f7f603c             # f7f603cf040ccfd884c7c4f8ade17136fb1635af，docs/v0.0.3 头，2026-10-17 10:01:01 UTC
origin_main: df09998                 # df09998d333a40a6adbd385e20c6d268a7402e74，2026-10-17 12:46:02 +0800
commits_df09998_to_f7f603c: 21       # 全部为 docs(V0.0.3) / chore(LICENSE) 提交
worktree_before_planning: clean      # 用户/规划指令陈述；见 §1.1
tracked_files: 128                   # git ls-files | wc -l
tracked_outside_docs: [.gitignore, LICENSE]   # 其余 126 个全部位于 docs/
business_code_files: 0               # 无 *.ts/*.tsx/*.js/package.json/Makefile（docs/ 之外）
apps_dir: absent                     # apps/relay、apps/node、apps/web 均不存在
test_command: 无（尚无代码；无 package.json、无 Makefile、无 CI 配置）
lockfile: 无
license: Apache-2.0（LICENSE 文件，提交 12ed15d，DEC-033）
```

### 1.1 工作区当前状态（本文件编写时，`git status --porcelain`）
| 路径 | 状态 | 性质 |
|---|---|---|
| `docs/WorkFleet-V0.0.4/` | 未跟踪 | 本轮规划产出（文档） |
| `packages/` | 未跟踪 | 本轮规划产出：`packages/contracts/`（契约 JSON Schema / OpenAPI / 码表，非业务代码） |
| `database/` | 未跟踪 | 本轮规划产出：`database/migrations/{relay,node}/0001_init.sql` |

规划开始前工作区干净为指令陈述（部分确认：本次核对时 HEAD 仍为 f7f603c，未见已修改的被跟踪文件，未跟踪内容均为本轮规划产物）。本轮约定不 commit/push。

## 2. 需求文档清单
| 类别 | 位置 | 数量 | 状态 |
|---|---|---|---|
| 原始需求 | `docs/WorkFleet-V0.0.3/02_requirements/inbox/REQ-INBOX-20261017-001-原始设计说明书.md` | 1 | received（逐字原文） |
| 需求增补 G1…G25 | `docs/WorkFleet-V0.0.3/02_requirements/inbox/REQ-INBOX-20261017-002-需求增补.md` | 1 | proposed（已被 V0.0.4 基线吸收） |
| V0.0.4 开工指令 | `02_requirements/inbox/REQ-INBOX-20261017-003-V0.0.4开工指令.md` | 1 | triaged |
| 需求基线 | `02_requirements/product-requirements.md` | 1 | approved |
| 功能需求 REQ-F | `02_requirements/features/` | 36（REQ-F-001…036） | approved（REQ-F-036 → v2） |
| 非功能需求 REQ-NF | `02_requirements/non-functional/` | 11（REQ-NF-001…011） | approved |
| 约束 REQ-C | `02_requirements/constraints/` | 9（REQ-C-001…009） | approved |
| 待办 / 被拒 | `backlog.md`（BL-001…011）/ `rejected.md`（RJ-001…004） | 2 | active |
| 历史需求 | `docs/WorkFleet-V0.0.1/00-原始需求.md`、`docs/WorkFleet-V0.0.2/00-原始需求.md` | 2 | REFERENCE |

## 3. 已确认事实
| # | 事实 | 证据 | 标签 |
|---|---|---|---|
| F-20 | 被跟踪文件 128 个，`docs/` 以外只有 `.gitignore` 与 `LICENSE` | `git ls-files` | 已确认（本次核对） |
| F-21 | 仓库无业务代码、无 `apps/`、无 `package.json`/锁文件/`Makefile`/CI 配置 | `find` 检索 docs 外 `*.ts *.tsx *.js package.json Makefile` 结果为空 | 已确认（本次核对） |
| F-22 | `df09998..f7f603c` 共 21 个提交，全部为 V0.0.3 文档与 LICENSE | `git log --oneline df09998..f7f603c` | 已确认（本次核对） |
| F-23 | 契约包规模：relay OpenAPI 68 个操作、node-local OpenAPI 22 个、错误码 28 个、领域事件 18 个、`protocol/` 下 20 个 JSON 文件 | 解析 `packages/contracts/` 各文件计数 | 已确认（本次核对；与 `03_solution/contracts/README.md` 所述 68/22/28/18 一致；README 称“19 种帧”，目录内 JSON 文件为 20 个，含 envelope schema，未逐一核对帧名） |
| F-24 | 两份 0001 迁移可在 SQLite 3.46.1 上建库成功：relay 38 张表、node 25 张表（`sqlite_master` 计数，含 FTS 影子表） | `sqlite3 /tmp/t.db < database/migrations/{relay,node}/0001_init.sql` | 已确认（本次核对，沙箱 sqlite3 3.46.1，非 better-sqlite3 内置版本） |
| F-25 | IM 指令唯一源含 `/help /list /use /@alias /clear /stop /stop all /status /history /bind Y{n}/N{n} /boss`；`/bind` 返回 6 位码到控制台确认 | `packages/contracts/commands/im-commands.json` | 已确认（文档内容） |
| F-26 | 配对码为 8 位、10 分钟有效 | `packages/contracts/api/relay.openapi.json` `/api/v1/devices/pairing-codes` summary | 已确认（契约内容，尚无实现） |
| F-27 | 输入适配器表列 13 个智能体；Copilot 与 ZCode 标 `experimental: true`；全部条目注明启动参数为规划假设、待实测 | `packages/contracts/adapters/input-adapters.v1.json` | 已确认（文档内容） |

## 4. 仅文档、未验证（设计陈述，不得当作事实引用）
| 项 | 出处 | 待验证任务 |
|---|---|---|
| 全部 REQ-F/REQ-NF 的“可验证陈述”（如回执 p95 ≤3 s、急停 ≤5 s、≥8 并发会话） | `product-requirements.md §2–3` | 各切片 E2E、TASK-210 |
| 微信 24h context_token / 约 10 条主动消息 | V0.0.2/30/03:52-53（部分确认） | TASK-041 |
| 香港中转访问 iLink 稳定 | DEC-040（证据不足） | TASK-041 |
| 各 ACP 智能体启动参数、ACP TS SDK 当前版本 | `input-adapters.v1.json` `$verify`；V0.0.3 F-07（快照日） | TASK-021/022/081/082 |
| better-sqlite3 三平台预编译可用 | ADR-009 | TASK-003/014 |
| iOS 16.4+ PWA Web Push | ADR-014（部分确认） | TASK-203/204 |
| 依赖许可（React/Fastify 等） | `00_governance/dependencies.md`（全部待核实） | TASK-001 起逐项 |
| 契约“前端/后端/数据端只凭契约可实现”的自检结论 | `03_solution/contracts/README.md §2` | TASK-002 及首批实现任务 |

## 5. 文档与代码 / 文档与文档不一致
| # | 不一致 | 位置 | 处理 |
|---|---|---|---|
| X-01 | 架构与任务描述的 `apps/relay`、`apps/node`、`apps/web`、`packages/testkit`、`Makefile`、`AGENTS.md`、`README.md`、`.github/` **均不存在** | architecture §3–4；task-index | 预期内：由 S0 任务创建（TASK-001/004/007/008/009/014） |
| X-02 | `packages/contracts/`、`database/migrations/` 已在工作区，但**未提交、无构建脚本、未在 CI 验证**；ownership-matrix 中 `packages/contracts/{src,scripts,generated,test}` 尚不存在 | 工作区；ownership-matrix | TASK-002/003 落地 |
| X-03 | ADR-011 Related 写 “`.github/workflows/ci.yml`（TASK-008）”，而 task-index 中 CI 守卫为 TASK-014、TASK-008 是 testkit | `03_solution/decisions/ADR-011-架构守卫与CI门禁.md` §8 | 以 task-index 为准；建议修订 ADR-011 Related（不在本文件范围） |
| X-04 | TASK-210（v1 验收）在 dag 中的入边不含 TASK-087（M4）、TASK-146（M7）、TASK-184（M9） | `04_planning/dag.md` | 见 `04_planning/milestones.md` 依赖关系注；建议补边 |
| X-05 | REQ-F-018 的指令清单不含 `/boss`，而指令契约含 `/boss`（总控对话） | `product-requirements.md` REQ-F-018；`im-commands.json` | 以契约为准（REQ-F-018 自述“以 im-commands.json 为准”） |
| X-06 | `input-adapters.v1.json` 中 Claude Code 包名 `@zed-industries/claude-agent-acp`，Codex docsUrl 指向 `agentclientprotocol/codex-acp` 而包名为 `@zed-industries/codex-acp`；均标待实测 | `packages/contracts/adapters/input-adapters.v1.json` | TASK-022 实测后修正（契约变更流程） |
| X-07 | V0.0.3 事实基线写“116 个被跟踪文件、无 LICENSE”（快照 df09998）；当前 f7f603c 为 128 个、已有 LICENSE | `docs/WorkFleet-V0.0.3/08_knowledge/fact-baseline.md §1` | 非矛盾：快照时点不同；以本文件为当前事实 |
| X-08 | V0.0.3 路线图把“渠道健康告警”列 v2，V0.0.4 需求基线 REQ-F-030 为 v1 MUST | V0.0.3 roadmap；PRD | 已在 `04_planning/roadmap.md` 变更记录登记 moved → v1 |
| X-09 | task-index 链接 `tasks/TASK-xxx.md` 84 个文件；读取时 `05_execution/tasks/` 仅见部分文件（落盘进行中） | `05_execution/task-index.md` | 以 `task-index.md` 与 `tasks.v1.json` 为准；`tasks.v1.json` 不含验收条目与验证命令 |

## 6. 读取失败项 / 未读项
| 项 | 情况 |
|---|---|
| `05_execution/tasks/TASK-*.md` | 编写本文件期间由其他规划任务陆续落盘（先见 7 个、后见 39 个），**内容未核对**（见 X-09） |
| `03_solution/design/DESIGN-*.md`、`03_solution/solutions/SOL-001`、`04_planning/steps/STEP-*` | 编写本文件期间由其他规划任务落盘中（DESIGN 先后见 7 个、12 个），**内容未核对**，仅 STEP-11/16 读过 |
| `docs/项目开发-多方案评审标准指令.txt` | 仅按需读取（模块十七防自证循环、4.8 负证据规则等），未全文逐节核对 |
| 外部网页（ACP 官方 Registry、各 IM 平台文档、ZCode 条款） | 本次未重新访问；相关事实沿用 V0.0.2/V0.0.3 快照并保留原证据标签 |

## 7. 未知项
以 `02_requirements/product-requirements.md §7`（U-02…U-08）为准；对应假设见 `00_governance/assumptions.md`。
