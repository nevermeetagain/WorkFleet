---
id: WF-PRODUCT-SCOPE
type: product
title: 产品范围（v1 In / Out）
status: active
version: V0.0.4
created: 2026-10-17
sources: [04_planning/roadmap.md, 02_requirements/product-requirements.md §2/§5, 02_requirements/backlog.md, 02_requirements/rejected.md, DEC-043…057]
---

# 产品范围

> 范围以 `04_planning/roadmap.md`（各产品版本）与 `02_requirements/product-requirements.md`（v1 基线）为准；本页只做 In/Out 的对照视图。

## 1. 系统边界
- **本机节点**（用户电脑，Windows/macOS/Linux）：拉起并驱动智能体；总控、模型配置与 Key、分身数据、写保护都在这里（DEC-037/041/044/049）。
- **云中转**（Ubuntu/Linux，暂定香港，对外只开 443）：IM 连接、账号/组织/角色、设备、项目、路由、审批、审计、Web 控制台与 PWA 推送（DEC-040/051、ADR-001）。
- **人**：通过 Web 控制台（默认）或 6 个 IM 之一操作（DEC-054/057）。

## 2. v1 In Scope
| 能力域 | 包含 | 需求 | 切片 |
|---|---|---|---|
| 部署形态 | 本机节点三平台、云中转多租户、配对码认领设备 | REQ-F-001/002 | S0、S10 |
| 默认渠道 | Web 控制台对话（控制台即 ACP 客户端）、PWA + Web Push | REQ-F-015 | S0、S1、S10 |
| 输入端 | 通用 ACP 适配器 + 官方 Registry；实测清单：Claude Code、Codex、Cursor、Gemini CLI、GitHub Copilot CLI（preview）、Qwen Code、Kimi CLI、OpenCode、Goose、Cline、Qoder CLI、OpenClaw、ZCode（实验）；非 ACP：Coze、Webhook | REQ-F-007/008 | S1、S4 |
| 输出端 | 微信 ClawBot、飞书/Lark、QQ、钉钉、Telegram、Discord | REQ-F-009…014 | S2、S5、S6 |
| 模式 | 管理（多对一）、通知（一对多，按发送人分会话）、团队（多对多，只到一个目标）、总控 | REQ-F-016/017/022 | S2、S5、S8 |
| 交互 | 指令 `/clear /list /use /@别名 /stop /stop all /status /history /bind /help /boss`、审批（按钮或 `Y{n}/N{n}`）、held、回复溯源 | REQ-F-017/018/020 | S1、S2 |
| 记录 | 会话 generation、按 displayId / 原生 resume id 查两端记录 | REQ-F-019 | S1 |
| 组织 | 项目一级对象 + 主/子项目（≤3 层）、一个账号多台设备、一个节点连多个中转 | REQ-F-004/005/006 | S3 |
| 协作安全 | 同目录写租约 / 自动 worktree | REQ-F-032 | S3 |
| 汇总 | 汇总屏障（N 来源或超时、标注缺失） | REQ-F-021 | S5 |
| 公司场景 | 三角色 RBAC、接收人 × 业务线 × 字段过滤与脱敏、审计 | REQ-F-003/027/028 | S7 |
| 分身数据 | 采集全部用户指令 + 时间线（只采不学），本机查看/修改/删除/导出 | REQ-F-029 | S7 |
| 总控 | 把关分级（不可关）、随时对话（`/boss`）、任务分派、会议、导入任务清单 | REQ-F-022…025 | S8、S9 |
| 模型与费用 | 用户自管模型配置、日/月费用上限与超限动作、系统提示词 | REQ-F-026 | S8 |
| 通知与健康 | p0–p3、渠道健康告警与备用渠道、Bot 唯一消费者检测 | REQ-F-030/031 | S6、S10 |
| 运维体验 | 急停、配置导入导出、doctor、恢复密钥与换机、画像向导 P1/P2、安装包 | REQ-F-031/033/034/035 | S10 |

## 3. v1 Out of Scope
| 不做 | 去向 | 依据 |
|---|---|---|
| 定时任务（一次/每日/工作日/休息日/每周/每月，含调休） | v2（BL-001） | roadmap；DEC-026 |
| 推送团队、订阅/退订；场景 4 每日 9:00 资讯推送 | v2（BL-002/003） | DEC-046 |
| 异常阈值（REQ-F-036，COULD） | v2（BL-004） | G6 |
| 第三方登录 OAuth、英文界面 | v2（BL-009/011） | ADR-006、REQ-NF-011 |
| 总控 AGENTS.md 与 Skills 配置/上传 | v3（BL-005） | QA-17、DEC-045 |
| 知识库（项目设计、目录结构图谱、上下文记忆） | v3（BL-006） | 原始说明书拓展项 |
| 分身学习 loop | v4+（BL-007） | DEC-049 |
| 多级汇总、飞书多维表格输入 | v4+（BL-008） | G4/G5 |
| 中转 PostgreSQL / 多实例 | 触发条件见 ADR-003（BL-010） | ADR-003 |
| 智能体在服务器运行 | 拒绝（RJ-001） | DEC-044/056 |
| 团队模式默认广播 | 拒绝（RJ-002） | DEC-006 |
| 可关闭的总控把关 | 拒绝（RJ-003） | DEC-018 |
| 用微信 ClawBot 向他人群发 | 拒绝（RJ-004） | DEC-046 |
| 中转运行模型或保存模型 Key；代码/工作目录上传中转 | MUST NOT | PRD §5 |

## 4. 范围内的已知限制（不是缺陷，是平台或设计约束）
- 同一个微信授权不能同时给 WorkFleet 和别的程序用（REQ-C-004）。
- 电脑关机时该电脑上的智能体无法工作，消息排队（DEC-037）。
- 中转能看到 IM 明文（R-07）；公司请用自建中转（DEC-048）。
- 微信主动消息受 24h / 约 10 条限制（R-01，待真机）。
- ZCode 为实验接入（R-02）；不能跨进程恢复会话的工具只能查记录不能续接（V0.0.3 requirement-coverage §3）。

## 5. 变更规则
范围变化先进 `02_requirements/inbox/`，经影响分析后同步 roadmap、本页、PRD 与 changelog（文档体系 §28–29）。
