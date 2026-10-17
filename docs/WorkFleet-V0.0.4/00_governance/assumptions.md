---
id: WF-ASSUMPTIONS
type: assumption
title: 假设登记册
status: active
version: V0.0.4
created: 2026-10-17
owner: 规划 Agent
sources: [02_requirements/product-requirements.md §7–8, docs/WorkFleet-V0.0.3/08_knowledge/fact-baseline.md §5, packages/contracts/adapters/input-adapters.v1.json, ADR-003/007/014]
---

# 假设登记册

> 假设 = 当前暂时当作成立、但尚未验证的前提（文档体系 §42）。每条假设写清：对应的未知项 U-xx（`product-requirements.md §7`）、假设内容、若不成立怎么办、由哪个任务验证、验证产物落在哪个 EVD。
> V0.0.3 的 U-01（微信额度“每入站重置”还是“累加”）在 V0.0.4 并入 U-02。

## 1. 与未知登记册对应的假设
| ID | 对应未知 | 假设（当前按此设计） | 级别 | 若不成立 | 验证任务 / 方式 | 证据位置 | 状态 |
|---|---|---|---|---|---|---|---|
| A-01 | U-02 | 微信 ClawBot 主动消息**有**限制：需 24h 内入站带来的 context_token，每次入站后约 10 条（默认实现“额度预算器 + 续期提示”） | BLOCKING（仅 REQ-F-009 提醒策略） | 若无限制：关闭预算器，适配器与路由不变（分叉点 `capabilities.proactiveQuota`） | TASK-041 真机：连续发送计数、24h 静默后主动发送 | EVD-041 | open |
| A-02 | U-03 | 飞书机器人**不能**主动触达租户外用户；外部订阅者走 Telegram | NON_BLOCKING（v2 场景 4） | 若能：v2 推送团队可直接用飞书外部用户 | v2 规划时按官方文档核实（v1 无任务） | — | open |
| A-03 | U-04 | 香港中转访问微信 iLink **可用**且稳定到能支撑管理模式 | NON_BLOCKING | 若不稳定：中转迁大陆主机或微信渠道单独部署（需新 ADR） | TASK-041 记录 RTT 与失败率 | EVD-041 | open |
| A-04 | U-05 | ACP TS SDK 包名/版本、各智能体启动参数以官方文档为准，与 `input-adapters.v1.json` 一致 | NON_BLOCKING | 不一致：更新 spec 表（契约变更走新任务 + ADR） | TASK-021（SDK）、TASK-022（Claude Code/Codex/Cursor）、TASK-081/082（其余 8 个）、TASK-083（OpenClaw） | EVD-021/022/081/082/083 | open |
| A-05 | U-06 | ZCode `app-server` / `zcode-acp-server` 在一个版本周期内足够稳定，可作“实验”输入端 | NON_BLOCKING | 不稳定：保持实验标注，S4 验收允许“失败 + 原因” | TASK-084 | EVD-084 | open |
| A-06 | U-07 | iOS 16.4+ 添加到主屏幕的 PWA 可收到 Web Push | NON_BLOCKING | 不可用：iPhone 用户回退到 IM 通知 | TASK-203（发送/订阅）、TASK-204（PWA 真机） | EVD-203/204 | open |
| A-07 | U-08 | 规划只给切片顺序，不承诺日期；人力按“同时 ≤3 个写入 Agent”估计 | BLOCKING（排期，不影响设计） | 用户给出工期/人力后重排 `current-plan.md` 与 `milestones.md` | 用户裁定（问题见 `08_knowledge/meetings/qa-log.md` 待问） | qa-log | open（待用户） |

## 2. 其他前提假设（无独立 U 号）
| ID | 假设 | 依据 | 若不成立 | 验证任务 | 状态 |
|---|---|---|---|---|---|
| A-08 | 同一微信 `ilink_user_id` 再次扫码会使旧 bot 实例失效（“最新授权者生效”），因此 WorkFleet 必须是唯一消费者 | V0.0.3 F-13（代码注释，部分确认）、F-17 | 若可多实例共存：唯一消费者告警降级为提示 | TASK-041（真机）、TASK-207 | open |
| A-09 | 每个外部智能体已由用户在本机安装并登录（WorkFleet 不代为登录其账号） | PRD §8 隐含要求 | — （这是使用前置，写入用户指南与 doctor 检查） | TASK-206（doctor 检查可执行文件） | 作为前置条件保留 |
| A-10 | 中转规模在“两人共用 + 公司自建、≤数百用户量级”内，SQLite 单实例足够 | ADR-003（推断） | 触发 ADR-003 迁移条件 → PostgreSQL（BL-010） | TASK-210 基线测量 | open |
| A-11 | 微信 ClawBot 需用户先在微信内启用 ClawBot 能力后才能扫码授权 | PRD §8（部分确认） | 若无需：用户指南删除此步 | TASK-041 真机 | open |
| A-12 | 飞书卡片按钮回调可经长连接接收 | V0.0.2/30/03:198 未确认 | 不可：审批降级为文本口令 `Y{n}/N{n}` | TASK-101 | open |
| A-13 | `better-sqlite3` 在三平台 Node 22 LTS 有可用预编译包，安装不需本地编译工具链 | ADR-009（规划者陈述，未实测） | 需编译：安装说明增加构建工具，或评估 `node:sqlite`（ADR-009 记为实验，证据不足） | TASK-003、TASK-014（三平台矩阵）、TASK-209 | open |

## 3. 更新规则
- 验证后把状态改为 `confirmed` / `refuted`，写明 VAL/EVD 编号；refuted 必须同步检查 `risks.md` 与受影响需求/ADR，并在 `07_release/changelog.md` 记录。
- 不删除行。

## 4. 变更记录
| 日期 | 变更 |
|---|---|
| 2026-10-17 | 初版：A-01…A-07 对应 U-02…U-08；补 A-08…A-13 |
