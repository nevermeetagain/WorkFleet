---
id: WF-RISKS
type: risk
title: 风险登记册
status: active
version: V0.0.4
created: 2026-10-17
owner: 规划 Agent
sources: [03_solution/architecture.md §9, 02_requirements/product-requirements.md §6–7, docs/WorkFleet-V0.0.3/08_knowledge/fact-baseline.md, docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md, ADR-001…014, 04_planning/cost-budget.md]
---

# 风险登记册

> - 风险 = 可能发生的问题（文档体系 §42）；与之对应的“暂时当真的前提”在 `assumptions.md`，“依赖谁/什么”在 `dependencies.md`。
> - R-01…R-06 与 `03_solution/architecture.md §9` 同号。
> - 概率/影响为规划者评估（高/中/低），**不是测量值**；证据标签指风险所依据事实的可信度。
> - 负责人写角色（见 `stakeholders.md`）。关联任务以 `05_execution/task-index.md` 为准。

## 1. 总表
| ID | 风险描述 | 证据标签 | 概率 | 影响 | 缓解 | 触发信号 | 负责人 | 关联任务 / 需求 |
|---|---|---|---|---|---|---|---|---|
| R-01 | **微信 ClawBot 主动消息限额**：context_token 24h 失效、每次入站后约 10 条主动消息；用户 24h 未发言时夜间任务完成通知可能发不出 | 部分确认（Tencent/openclaw-weixin issue #202 与社区项目；未真机，`V0.0.2/30-协议与端点/03:52-53`） | 高 | 中 | 额度预算器 + 剩余 ≤3 条提示续期（REQ-F-009）；过程消息合并（DEC-017）；超额排队到下次入站，或经备用渠道 / Web Push 送达（REQ-F-030、ADR-014）；`capabilities.proactiveQuota` 作为分叉点（PRD §7 U-02） | TASK-041 真机：第 11 条主动消息失败；`sendmessage` 返回非 0 `ret`；投递死信中微信占比上升 | Agent-Channel；真机：用户本人 | TASK-041、TASK-048、TASK-125；REQ-F-009/030；A-01 |
| R-02 | **ZCode 无官方 ACP**：只能走私有未文档化的 `zcode app-server --stdio` 或社区 `zcode-acp-server`（自述非官方），协议随版本变化或违反 ZCode 条款（ToS 未核） | 已确认（存在性）/ 证据不足（ToS、稳定性、多实例并发）（V0.0.3 F-19；DEC-038） | 中 | 中 | 标“实验”，失败不阻塞 S4 验收（REQ-F-007 允许标注失败原因）；`dialect` 钩子隔离（ADR-007）；在用户指南中明示；上线前人工核 ZCode 条款 | ZCode 升级后夹具回放失败；社区桥停更或许可变更；ZCode 条款出现禁止第三方驱动的表述 | Agent-Node；条款核查：用户本人 | TASK-084、TASK-087；REQ-C-009；A-05 |
| R-03 | **v1 范围大**：6 个 IM + 13 个 ACP 智能体 + Coze/Webhook + 总控（把关+会议）+ 多用户权限审计 + PWA；84 张任务，关键路径 19.5 理想人日（仅排序口径），工期与人力未裁定 | 已确认（范围来自 DEC-043/047/054/055/056/057；规模见 `04_planning/dag.md`） | 高 | 高 | 垂直切片，每刀可演示（`slices.md`）；先主路径 S0→S1→S2；S4∥S5∥S6 并行（≤3 写入 Agent）；熔断规则（`cost-budget.md §4`）；里程碑逐个退出（`milestones.md`） | 任一切片连续两次验收 FAIL；关键路径任务 blocked > 1 个波次；券超额申请频繁 | 规划 Agent；裁定：用户本人 | 全部；U-08；A-07 |
| R-04 | **香港中转访问微信 iLink 的连通性与稳定性**未验证；跨境链路断线、乱序、重复 | 证据不足（DEC-040 已注明） | 中 | 高（微信是用户第一痛点） | ADR-005：WSS 心跳 20 s、60 s 判断线、seq/ack 续传、幂等键去重；TASK-041 记录 RTT 与失败率；不可用时可把中转部署到大陆主机（需新 ADR） | TASK-041 实测失败率异常；`getupdates` 频繁超时；节点重连次数突增 | Agent-Channel；部署：用户本人 | TASK-041、TASK-006/007；REQ-NF-003；A-03 |
| R-05 | **GitHub Copilot CLI 的 ACP 支持为官方 public preview**，接口可能变化 | 已确认（GitHub 2026-01-28 changelog，见 `packages/contracts/adapters/input-adapters.v1.json` 的 docsUrl；`experimental: true`） | 中 | 低 | 在 spec 表标 experimental；夹具回放 + 真机冒烟；失败不阻塞 | Copilot CLI 版本升级后握手失败 | Agent-Node | TASK-082、TASK-087；REQ-F-007 |
| R-06 | **QQ 官方机器人主动消息配额文档冲突**：新版“1000 条/用户/天”与早期“每月 4 条”并存，且用户可关闭主动消息 | 部分确认（官方文档自相矛盾，`V0.0.2/30-协议与端点/03:16,180,198`） | 中 | 低 | 按能力降级为“仅被动回复”渠道（capabilities 协商，DEC-008）；QQ 不承担群发（DEC-054） | TASK-121 实测主动消息被拒；平台返回配额错误码 | Agent-Channel | TASK-121、TASK-126；REQ-F-011 |
| R-07 | **中转可见 IM 明文**：IM 平台推送即明文，共用中转的人能看到彼此消息内容（运维层面）；中转被攻破即泄露 IM 历史 | 已确认（平台机制；DEC-047/048；ADR-001 Negative） | 中 | 高 | 控制台明示（REQ-NF-005）；公司场景用公司自建中转（DEC-048）；TLS、最小权限、审计（REQ-F-028）；IM 凭据加密存储；代码与模型 Key 不上中转（DEC-037/044） | 共用中转的一方提出合规要求（DEC-039 反转条件）；中转主机异常登录 | 中转运维者（用户本人 / 公司管理员） | TASK-005、TASK-042、TASK-143、TASK-146；REQ-NF-004/005 |
| R-08 | **SQLite 单实例**：中转单进程单库，无水平扩展与热备；单写者在高写入下排队 | 推断（中转规模“≤ 数百用户量级”为 ADR-003 推断） | 低 | 中 | 单实例锁（DEC-003）；WAL；长查询放 worker_threads（ADR-009）；Kysely 方言保留迁移 PostgreSQL 路径；触发条件见 ADR-003（需多实例 / 写入 p95 > 50 ms 持续 1 天 / 单库 > 20 GB） | 触发 ADR-003 任一条件；备份恢复演练失败 | Agent-Data；规划 Agent | TASK-003、TASK-210；BL-010；A-10 |
| R-09 | **三平台钥匙串差异**：Windows DPAPI / macOS Keychain / Linux libsecret 行为不一，无桌面会话的 Linux 可能没有 libsecret；换机后加密数据不可读 | 部分确认（DEC-041 列出方案；未实测） | 中 | 中 | 钥匙串抽象 + 无钥匙串时加密文件回退（TASK-161）；恢复密钥导出/导入（REQ-F-035）；CI 三平台矩阵（ADR-011） | 某平台单测仅在 CI 失败；用户反馈重装后 Key 丢失；`doctor` 报钥匙串不可用 | Agent-Node | TASK-161、TASK-206、TASK-014；REQ-F-026/035、REQ-NF-006 |
| R-10 | **ACP SDK 与各智能体适配器版本漂移**：TS SDK 包名/版本未实测（V0.0.3 快照 TS SDK 1.9.0）；各智能体启动参数为规划假设；`loadSession` 支持不一 | 部分确认（V0.0.3 F-07 为快照日事实；`input-adapters.v1.json` 各条 `$verify` 注明待实测） | 高 | 中 | TASK-021 实测锁定 SDK 版本并写入 spec；每个智能体录制夹具（REQ-F-007）；`supportsLoadSession=false` 时只查记录不续接；依赖锁文件 | 智能体升级后握手/夹具失败；SDK 主版本号变化 | Agent-Node | TASK-021、TASK-022、TASK-081、TASK-082；A-04 |
| R-11 | **Bot 身份被其他程序争抢**：同一微信授权“最新扫码者生效”，同一飞书应用多连接随机分发；用户未关闭 ZCode/OpenClaw 自带 Bot 时消息丢失或被顶掉 | 部分确认（V0.0.3 F-13 代码注释、F-15 飞书官方、F-17 推论） | 中 | 中 | 一个 Bot 身份一个消费者（REQ-C-004）；向导提示关闭 ZCode 自带微信 Bot（DEC-038）；唯一消费者检测与告警（REQ-F-031） | 入站消息间断缺失；微信授权无故失效；飞书事件计数与平台侧不符 | Agent-Relay；用户本人（配置） | TASK-207、TASK-208、TASK-041；REQ-F-031；A-08 |
| R-12 | **iOS Web Push 限制**：需添加到主屏幕且 iOS 16.4+；不接 IM 的用户在 iPhone 上可能收不到审批提醒 | 部分确认（ADR-014） | 中 | 中 | TASK-203/204 实测；失败回退到用户配置的 IM（邮件 v2） | 真机订阅失败或推送不到达 | Agent-Relay / Agent-App | TASK-203、TASK-204；REQ-F-015；A-06 |
| R-13 | **第三方代码与依赖许可不兼容**：Apache-2.0 仓库；AGPL（AstrBot）、EULA（PentAGI）、GPL-2.0+禁商用（BettaFish）、无 LICENSE（WechatClawbot）不可拷贝；OpenClaw 渠道插件许可逐个待核 | 已确认（V0.0.3 F-06/F-11；DEC-009/033；ADR-010） | 低 | 高 | clean-room 边界（ADR-010）；THIRD_PARTY_NOTICES；依赖许可在 `dependencies.md` 逐项核实后才可合并 | 引入新依赖未登记许可；代码相似度审查命中 | Agent-Guard；各实现 Agent | TASK-001、TASK-014、各适配器任务；REQ-C-002 |
| R-14 | **IM 入站提示注入**：任何能给 Bot 发消息的人都可能诱导智能体执行危险操作 | 推断（G8；DEC-030） | 中 | 高 | 发送者默认未授权，需 `/bind`（DEC-030、TASK-043）；入站文本带来源标记、按不可信处理；高危工具调用必须审批（REQ-F-020）；急停（REQ-F-033） | 未授权发送者触发路由；审批被异常高频触发 | Agent-Relay；Agent-QA（TASK-146） | TASK-043、TASK-028、TASK-146、TASK-201；REQ-NF-004 |
| R-15 | **执行档位券超额**：S2、S8 各有 1 张 opus 卡超出每切片 ≤3 券 | 已确认（`cost-budget.md §3`） | 高 | 低 | 默认替代方案（TASK-045、TASK-164 改 sonnect 执行 + opus review）；用户批准后可恢复 | 进入 S2/S8 时未获批准 | 规划 Agent；批准：用户本人 | TASK-045、TASK-164 |
| R-16 | **飞书卡片回调是否可走长连接未确认**；同用户/同群 5 QPS；卡片回调 3 秒时限 | 部分确认（`V0.0.2/30-协议与端点/03:198`；V0.0.3 F-09） | 中 | 中 | 令牌桶限速（DEC-013）；≤3 秒回执（DEC-017）；回调不可走长连接时改用按钮→文本口令降级（DEC-011 `Y{n}/N{n}`） | TASK-101 实测卡片按钮事件收不到 | Agent-Channel | TASK-101、TASK-105；REQ-F-010；A-12 |

## 2. 风险热区（按概率 × 影响）
- 高×高：R-03
- 高×中：R-01、R-10
- 中×高：R-04、R-07、R-14
- 其余：中/低

## 3. 更新规则
- 每个切片退出评审时复核本表；触发信号出现 → 在对应任务卡记录并升级（`cost-budget.md §4` 熔断）。
- 风险关闭写“closed + 日期 + 依据（VAL/EVD）”，不删行。

## 4. 变更记录
| 日期 | 变更 |
|---|---|
| 2026-10-17 | 初版：R-01…R-06 承接 architecture §9，新增 R-07…R-16 |
