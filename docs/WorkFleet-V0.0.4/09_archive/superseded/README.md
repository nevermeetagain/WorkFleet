---
id: WF-SUPERSEDED
type: project
title: 被取代的决策登记（V0.0.3 → V0.0.4）
status: active
version: V0.0.4
created: 2026-10-17
sources: [docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md, docs/WorkFleet-V0.0.3/06_validation/requirement-coverage.md §5, 03_solution/decisions/ADR-001…014, 02_requirements/product-requirements.md §6]
---

# 被取代的决策登记

> 规则（文档体系 §3.6、§23、§36）：历史不覆盖。**原文一律保留在原处**——`docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md`（下称 decision-log），本目录**不复制、不删除、不修改**原文，只登记“哪一部分被谁取代、哪一部分仍然有效”。
> 判断依据是取代方的原文；“仍有效部分”是规划者逐句比对的结论（推断），若与取代方冲突以取代方为准。

## 1. 登记表
| 被取代决策 | 原文要点（摘录，全文见 decision-log 对应行） | 被取代的部分 | 取代方 | 仍然有效的部分 |
|---|---|---|---|---|
| **DEC-002** | “单进程网关（控制面）+ 每个 Agent 会话一个子进程（执行面）” | “单进程网关”作为**整个系统**的形态（单机网关时期，所有 IM 连接与控制台在用户电脑） | DEC-051 → **ADR-001**（部署分两侧：本机节点 + 云中转） | 本机节点内部仍是“单进程控制面 + 每会话一个子进程”（ADR-001、architecture §3 `apps/node`） |
| **DEC-016** | 端口（只绑 127.0.0.1）：5100 控制台 + Admin API；5101 Gateway API；5102 Webhook；5103 MCP；5104 metrics；5180/5181 预留 Hindsight；5190–5200 测试 | ①“所有端口只绑 127.0.0.1”对**中转**不再成立；②5100“控制台 + Admin API”拆为本机控制台（节点，127.0.0.1:5100）与中转多角色控制台（公网 443）；③5101 从“Gateway API”改为中转内部监听（仅反代可达） | DEC-051 → **ADR-001**；architecture §3 端口段 | 端口段 5100–5200（REQ-C-003）；节点侧 5100/5102/5103/5104 仍只绑 127.0.0.1；5190–5200 测试预留；新增 5110–5119 E2E 中转实例（architecture §3） |
| **DEC-022** | “ACP v1 为输入长期契约（v2 开关）；渠道全部用长连接/长轮询，不需要公网 IP；为 Agent 提供 MCP 推送工具” | “不需要公网 IP”对**中转**不再成立（中转对外开放 443）；渠道连接的位置从用户电脑移到中转 | DEC-051 → **ADR-001**、ADR-005 | ACP 为输入长期契约（ADR-007）；IM 渠道仍全部用长连接/长轮询（在中转侧）；节点出站 WSS，无需公网 IP；MCP 端口 5103 保留 |
| **DEC-030** | “安全默认：所有端口只绑 127.0.0.1；IM 发送者默认未授权…；IM 入站文本视为不可信输入” | “所有端口只绑 127.0.0.1”——中转需公网 443，改为“只开 443 + 强制 TLS + 登录鉴权” | DEC-051 → **ADR-001**、ADR-006；REQ-NF-004 | 节点端口只绑 127.0.0.1；IM 发送者默认未授权（`/bind`）；入站文本按不可信处理（REQ-NF-004、DEC-030 标注“不可放松”的部分全部保留） |
| **DEC-025** | “MVP 输入端：Claude Code、Codex、Cursor；ZCode、Coze、OpenClaw 后置” | 整个输入端清单 | 先被 **DEC-052** 修订（加入 OpenClaw、ZCode 实验、Webhook；Coze 进 v2），再被 **DEC-055** 取代（所有主流 ACP 智能体 + Coze + Webhook 进 v1）；落地为 **ADR-007**、REQ-F-007/008 | 各智能体的接入方式（`claude-agent-acp`、`codex-acp`、Cursor `agent acp`）作为 spec 表条目沿用（`input-adapters.v1.json`） |
| **DEC-052** | “v1 输入端 = Claude Code、Codex、Cursor、OpenClaw、ZCode（实验）、Webhook/HTTP 通用输入；Coze 进 v2” | 输入端清单与“Coze 进 v2” | **DEC-055**（“取代 DEC-025/052 的输入端清单”，Coze 进 v1）→ **ADR-007** | “Webhook/HTTP 通用输入进 v1”（REQ-F-008）；“推送、监控、报表、数据分析类非智能体来源走 Webhook”的定位 |

## 2. 其他部分取代（供追溯，非本次重点）
| 决策 | 被取代部分 | 取代方 |
|---|---|---|
| DEC-020 | “主密钥存 OS 钥匙串（Windows DPAPI）”中仅 Windows 的部分 | DEC-041（三平台钥匙串：DPAPI / Keychain / libsecret / 加密文件），落地 TASK-161 |
| DEC-044 | “技能文件上传”在 v1 的部分 | DEC-045（移至 v3，v1 保留系统提示词；decision-log 原文已注“DEC-044 部分 superseded”） |
| DEC-051 | 不是被取代，而是被正式化：其内容由 ADR-001 以 ADR 形式承接 | ADR-001（Related 列 DEC-051） |

## 3. 原文位置
- 决策原文：`docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md`（DEC-002、016、020、022、025、030、044、051、052、055 各行）。
- 矛盾识别过程：`docs/WorkFleet-V0.0.3/06_validation/requirement-coverage.md §5`。
- V0.0.4 冲突处理登记：`02_requirements/product-requirements.md §6` 第 4 条。

## 4. 变更记录
| 日期 | 变更 |
|---|---|
| 2026-10-17 | 初版：登记 DEC-002/016/022/025/030/052 的取代关系；附 DEC-020/044/051 |
