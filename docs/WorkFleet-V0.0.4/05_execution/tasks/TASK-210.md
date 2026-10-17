# TASK-210：v1 验收回归与基线指标测量

```yaml
id: TASK-210
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-QA
tier: opus
size: 大
title: "v1 验收回归与基线指标测量"
dependsOn: ["067", "087", "105", "126", "146", "166", "184", "202", "206", "208", "209"]
blocks: ["211"]
reqs: "REQ-NF-001/002"
allowedPaths: ["tests/e2e/regression/**", "docs/WorkFleet-V0.0.4/06_validation/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-NF-001 / REQ-NF-002（本卡同时承担 REQ-F-001…033 全部 MUST 项与 REQ-NF-001…011 的 v1 回归验收）
- 来源方案：REQ-NF-001/002（基线指标）；v1 全部 MUST 回归；document-standard §5.3（PASS/FAIL/UNKNOWN）

## 2. 目标
对 v1 全部 MUST 功能需求（REQ-F-001…033）与全部非功能需求（REQ-NF-001…011）执行回归验收，逐条给出 PASS/FAIL/UNKNOWN 与证据；首次测量并记录基线指标（时延、并发与内存、可靠性、首屏），作为后续版本的对比基准。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（§2 MUST 列、§3 非功能）
  - docs/WorkFleet-V0.0.4/02_requirements/non-functional/REQ-NF-001…011
  - docs/WorkFleet-V0.0.4/04_planning/slices.md（各切片演示脚本）
  - docs/WorkFleet-V0.0.4/00_governance/document-standard.md §5.3
  - docs/WorkFleet-V0.0.4/04_planning/baseline-metrics.md（**不存在**，见下方附表说明）
- 契约：
  - packages/contracts/（全部契约作为被测对象）api/relay.openapi.json、api/node-local.openapi.json、identity/permissions.json、commands/im-commands.json、errors/error-codes.json、ux/ux-states.json、protocol/envelope.schema.json
  - packages/contracts/errors/error-codes.json：`EMERGENCY_STOPPED`（REQ-F-033 计时）；protocol/frames/emergency.stop/ack（生效判定）
- 前置任务：TASK-202, TASK-206, TASK-208, TASK-209
- 前置状态：TASK-202、206、208、209 已合并，且 S0–S9 各 E2E 任务（013/030/048/067/087/105/126/146/166/184）证据齐全；中转已按 TASK-209 部署到一台可测主机。

## 4. 输出
- tests/e2e/regression/（汇总运行器 + 回归专用用例：tenancy、web-only、commands-matrix、webhook、filters、audit、twin、health-alert、onboarding、emergency、privacy、observability、perf-latency、perf-resource、reliability）
- docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-210.md（逐需求结论表）
- docs/WorkFleet-V0.0.4/06_validation/test-results/v1-regression-report.md
- docs/WorkFleet-V0.0.4/06_validation/test-results/baseline-metrics-v1.md（首次基线）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/`（见 §8）

## 5. Execution Steps
1. [ ] 建清单：以本卡附表“v1 MUST 回归验收清单”为准（33 条 MUST + 11 条 NF），为每条标明自动用例或手动/真机证据来源。
2. [ ] 复跑全部切片 E2E 与集成套件（s1/s2/s3/s5/s8/s9、channels、security）于同一提交，收集报告。
3. [ ] 补写回归专用用例（tests/e2e/regression/），覆盖附表中标注 `regression/*.spec.ts` 的条目，尤其 REQ-F-033 计时：从 `POST /api/v1/emergency/stop-all` 到全部节点 ack 与外发归零 ≤5 s。
4. [ ] 按附表“测量方法”执行 NF 测量：时延 p50/p95/p99（≥200 样本）、8 并发会话与 RSS 采样、断线/重启可靠性、端口扫描、首屏 4G 节流 5 次中位、i18n 字面量扫描；记录环境（机器规格、网络、提交号）。
5. [ ] 真机/手动项：三平台安装（EVD-209）、微信真机（EVD-041）、各 IM 真机冒烟、iOS 推送（EVD-204）、跨境时延——复核其证据；缺失则结论 UNKNOWN 并写阻塞原因。
6. [ ] 写 `baseline-metrics-v1.md`：每个指标的值、样本量、方法、环境、证据标签；声明“尚无基线，首次测量在本任务产生”。
7. [ ] 写 VAL-210 与回归报告：逐条 PASS/FAIL/UNKNOWN（PARTIAL 记 FAIL 附已通过条目，BLOCKED 记 UNKNOWN 附原因，document-standard §5.3）；FAIL 项为责任任务开缺陷，不在本卡修代码。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] VAL-210 覆盖附表全部 33 条 MUST 与 11 条 NF，每条有结论与证据链接，无空项。
- [ ] 所有自动化回归用例在同一提交上连续 2 次运行结果一致（排除偶发）。
- [ ] REQ-F-033 急停端到端实测耗时记录（p95 与最大值）且 ≤5 s 判 PASS。
- [ ] baseline-metrics-v1.md 含 REQ-NF-001/002/003/011 的实测值、样本量、环境与方法。
- [ ] FAIL/UNKNOWN 项均有对应缺陷任务或阻塞说明。

### 附：v1 MUST 回归验收清单（REQ-F-034/035 为 SHOULD、REQ-F-036 为 COULD，不在 MUST 清单；034/035 仍随 TASK-206/205 证据复核）

| 需求 | 回归要点 | 用例/证据来源 | 方式 | 结论 |
|---|---|---|---|---|
| REQ-F-001 | 本机节点：三平台安装、开机自启、单实例、控制台显示在线 | TASK-209 安装脚本 + 手动三平台真机（Win11 / macOS 14 / Ubuntu 24.04） | 手动 + 脚本 | PASS/FAIL/UNKNOWN |
| REQ-F-002 | 多租户隔离：跨组织 403/404 | tests/integration/security（TASK-146）+ tests/e2e/regression/tenancy.spec.ts | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-003 | 三角色权限矩阵逐格 | tests/integration/security/permission-matrix（TASK-146） | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-004 | 主/子项目（深度≤3）与跨项目视图 | tests/e2e/s3（TASK-067） | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-005 | 多设备按设备路由、离线排队提示 | tests/e2e/s3（TASK-067） | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-006 | 一节点多中转隔离 | tests/integration/s3（TASK-067） | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-007 | 通用 ACP 输入：夹具回放 + 真机冒烟记录 | FakeAgent 夹具回放 + EVD-022/087 冒烟记录复核 | 自动 + 证据复核 | PASS/FAIL/UNKNOWN |
| REQ-F-008 | Coze 与 Webhook（签名校验）输入 | TASK-085/086 测试 + regression/webhook.spec.ts | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-009 | 微信 ClawBot：扫码、失效 p0、额度预算器 | tests/e2e/s2（FakeChannel 微信方言）+ EVD-041 真机记录 | 自动 + 真机 | PASS/FAIL/UNKNOWN |
| REQ-F-010 | 飞书/Lark 双域、长连接、卡片审批与流式更新 | tests/e2e/s5 + tests/integration/channels（FakeChannel 飞书方言） | 自动（真机冒烟手动） | PASS/FAIL/UNKNOWN |
| REQ-F-011 | QQ 单聊/群聊、配额降级 | tests/integration/channels（TASK-126） | 自动（真机冒烟手动） | PASS/FAIL/UNKNOWN |
| REQ-F-012 | 钉钉 Stream、互动卡片审批 | tests/integration/channels | 自动（真机冒烟手动） | PASS/FAIL/UNKNOWN |
| REQ-F-013 | Telegram 长轮询、内联按钮、频道群发 | tests/integration/channels | 自动（真机冒烟手动） | PASS/FAIL/UNKNOWN |
| REQ-F-014 | Discord Gateway、按钮组件 | tests/integration/channels | 自动（真机冒烟手动） | PASS/FAIL/UNKNOWN |
| REQ-F-015 | Web 全流程（注册→配对→对话→审批→历史）+ PWA 推送 | tests/e2e/s1 + regression/web-only.spec.ts + TASK-204 推送证据 | 自动 + 真机（iOS） | PASS/FAIL/UNKNOWN |
| REQ-F-016 | 三种绑定模式 + dry-run | tests/e2e/s2、s5 | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-017 | 引用回复溯源、按发送人分会话 | tests/e2e/s2、s5 | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-018 | 指令在所有渠道与 Web 一致 | regression/commands-matrix.spec.ts（im-commands.json × 渠道方言） | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-019 | /clear generation、按 displayId/resumeId 查两端记录 | tests/e2e/s1 | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-020 | 审批与 held、超时拒绝 | tests/e2e/s1、s2 | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-021 | 汇总屏障与超时缺失标注 | tests/e2e/s5 | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-022 | 总控把关四分级、不可关 | tests/e2e/s8（TASK-166） | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-023 | /boss 不打断、分派 1..N | tests/e2e/s8 | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-024 | 会议四类事件可回放 | tests/e2e/s9（TASK-184） | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-025 | 导入任务清单直接分派 | tests/e2e/s9 | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-026 | 模型配置、Key 不出节点、超限降级 | tests/e2e/s8/key-isolation + budget-degrade | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-027 | 接收人级过滤与脱敏 | TASK-142 单测 + regression/filters.spec.ts | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-028 | 出站与管理审计 | TASK-143 测试 + regression/audit.spec.ts | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-029 | 分身数据采集与查看/修改/删除/导出 | TASK-144 测试 + regression/twin.spec.ts | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-030 | p0–p3、60 秒内 p0 告警走备用渠道 | tests/integration/channels（TASK-126）+ regression/health-alert.spec.ts | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-031 | 画像向导 P1/P2、Bot 唯一消费者告警 | TASK-207/208 测试 + regression/onboarding.spec.ts | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-032 | 同目录写租约 / worktree | tests/integration/s3 | 自动 | PASS/FAIL/UNKNOWN |
| REQ-F-033 | /stop all 5 秒内生效、可恢复 | regression/emergency.spec.ts（计时断言） | 自动 | PASS/FAIL/UNKNOWN |

### 附：非功能需求与基线指标测量方法

> `04_planning/baseline-metrics.md` 在本卡编写时不存在（已扫描 04_planning/ 目录，仅有 STEP-11 索引指向它）。**尚无基线，首次测量在本任务产生**；结果写入 `06_validation/test-results/baseline-metrics-v1.md`（本卡允许路径内），由 TASK-211 或规划 Agent 决定是否回填 04_planning。

| 需求 | 目标值（REQ-NF 原文） | 测量方法 | 首次测量值 |
|---|---|---|---|
| REQ-NF-001 | 入站到回执 p95 ≤ 3 s；Web→节点 p95 ≤ 1 s（同城）/ ≤ 2 s（跨境） | regression/perf-latency.spec.ts：在 E2E 环境发送 ≥200 条消息，按 trace_id 取中转入站时间戳与回执发送时间戳、Web 请求发出与节点收到 agent.prompt 时间戳（同一主机时钟），计算 p50/p95/p99；跨境数值需在香港中转 + 本地节点的真实部署上手动测一次（证据标签“部分确认”） | 待测（本任务产生） |
| REQ-NF-002 | 单节点 ≥8 并发会话；空闲 15 分钟回收；控制面常驻 ≤200 MB | regression/perf-resource.spec.ts：启动 8 个 FakeAgent 会话并发执行 10 分钟，每 5 s 采样节点控制面 `process.memoryUsage().rss`（不含子进程，取 /metrics 或本机 /local/v1/status）记录峰值与稳态；空闲回收用节点测试时钟或真实 15 分钟等待验证会话被回收 | 待测（本任务产生） |
| REQ-NF-003 | 至少一次 + 幂等；中转重启/断线 10 分钟内恢复不丢不重 | regression/reliability.spec.ts：持续发送消息期间 kill -9 中转并在 1/5/10 分钟后重启、切断节点网络 10 分钟后恢复；以 idempotencyKey 统计 FakeChannel 收到的外发：丢失数=0、重复数=0 | 待测（本任务产生） |
| REQ-NF-004 | 只开 443；节点只绑 127.0.0.1；未授权默认；入站不可信；Key 不出节点；gitleaks | 部署主机 `ss -ltnp` 与外部 `nmap -Pn -p- <relay>` 只见 443（及运维 SSH，单列说明）；节点 `ss -ltnp`/`netstat -ano` 5100–5104 仅 127.0.0.1；复跑 tests/integration/security 与 gitleaks | 待测（本任务产生） |
| REQ-NF-005 | 控制台明示中转可见明文；分身只在节点；可导出删除 | regression/privacy.spec.ts：断言控制台固定文案存在；relay.db grep 分身测试文本 0 命中；导出/删除用例 | 待测（本任务产生） |
| REQ-NF-006 | 三平台矩阵；GBK、CRLF、长路径 >260 覆盖 | 复核 CI 三平台矩阵最近一次全绿；Windows job 中专项用例（GBK 输出解码、CRLF 转录、>260 字符工作目录）结果 | 待测（本任务产生） |
| REQ-NF-007 | trace_id 贯穿 web→relay→node→agent；/metrics；死信查看重放 | regression/observability.spec.ts：一条消息的 traceId 在 Web 请求头、中转日志、节点日志、FakeAgent 记录中均可 grep 到；抓取 127.0.0.1:5104/metrics 校验 Prometheus 文本格式；死信重放用例 | 待测（本任务产生） |
| REQ-NF-008 | 新增 IM / ACP 智能体零核心改动 | 统计法：以 TASK-121–124 与 TASK-081–084 的合并提交 `git diff --stat` 证明改动只落在适配器目录 + 注册一行（记录文件清单） | 待测（本任务产生） |
| REQ-NF-009 | CI 不依赖真实 IM/智能体；契约测试由 schema 生成 | 在禁止外网的 CI job 中运行全部单测/集成/E2E 通过；`pnpm contracts:gen && git diff --exit-code` 无漂移 | 待测（本任务产生） |
| REQ-NF-010 | 总控日/月硬上限可配，超限默认降级 | 复跑 tests/e2e/s8/budget-degrade；核对默认 onExceed=degrade_to_rules | 待测（本任务产生） |
| REQ-NF-011 | 中转控制台首屏 4G 可交互 ≤3 s；zh-CN；文案集中 i18n | Playwright + Chrome DevTools 网络节流（4G 预设参数写入报告）或 Lighthouse CI 测 TTI/INP 指标 5 次取中位；i18n：脚本扫描 apps/web/src 中 JSX 文本字面量（非 i18n 调用）数量=0 | 待测（本任务产生） |

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/
pnpm exec playwright test tests/e2e --reporter=list,html,json | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/e2e-all.txt
pnpm exec vitest run tests/integration --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/integration.txt
pnpm exec playwright test tests/e2e/regression --grep @perf --workers=1 --reporter=list | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/perf.txt
make ci | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/ci.txt
cp -r playwright-report docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/playwright-report
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/
- `e2e-all.txt`、`integration.txt`、`perf.txt`、`ci.txt`、`playwright-report/`
- `env.md`（机器、OS、网络节流参数、提交号、中转部署位置）
- `manual/`（真机与手动项的复核记录与链接）

## 9. 允许修改
- `tests/e2e/regression/**`
- `docs/WorkFleet-V0.0.4/06_validation/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-210/` 除外，见 ownership-matrix §4）
- apps/**、packages/**（只测不改；缺陷开新任务）
- docs/WorkFleet-V0.0.4/04_planning/**（baseline 结果写在 06_validation，回填由规划/文档任务决定）

## 11. 依赖与阻塞
- Depends on：TASK-067, TASK-087, TASK-105, TASK-126, TASK-146, TASK-166, TASK-184, TASK-202, TASK-206, TASK-208, TASK-209
- Blocks：TASK-211
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `04_planning/baseline-metrics.md` 不存在且不在本卡允许路径：基线写入 06_validation/test-results/，回填 04_planning 需主 Agent 决定。
  - 跨境时延（REQ-NF-001 ≤2 s）需要香港中转 + 本地节点的真实部署：无部署时该项 UNKNOWN。
  - 前置切片证据缺失（例如真机冒烟未做）：对应需求记 UNKNOWN，不得以 FakeChannel 结果冒充真机结论。

## 12. 建议执行档位
opus　理由：v1 发布门的总判定，需要独立判断证据充分性（PASS/FAIL/UNKNOWN），属高风险 review。

## 13. 升级条件
- 回归发现需求本身不可验证或相互冲突 → fable（需求终裁）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
大　是否小于 2 小时：否　全量回归 + 基线测量，约 2 天（不含等待真机）。

## 15. 风险与假设
- 假设：测量在单台 CI 主机上进行，同城时延结论只代表本地回环条件（标“部分确认”）。
- 风险：15 分钟空闲回收与 10 分钟断线用例耗时长 → 放夜间 job。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-210/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-210.md`）
