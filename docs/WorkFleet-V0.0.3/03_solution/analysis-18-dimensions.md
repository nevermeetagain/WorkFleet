---
id: WF-V0.0.3-ANALYSIS
type: analysis
title: 十八维全景分析（基于六个参考项目重新推演 WorkFleet）
status: active
version: V0.0.3
created: 2026-10-17
---

# 02 · 十八维全景分析

> 缩写：WCB=WechatClawbot，PC=Paperclip，PA=PentAGI，OR=Orca，HS=Hindsight，BF=BettaFish。
> 证据出处：`V0.0.2/10-参考项目/11–16`（下文写作 `11 §5` 等）与 `V0.0.2/40-综合/02`。参考项目结论均为静态代码阅读；只有 WCB（28 测试）与 BF（45 测试 + 论坛仿真）实际跑过。
> 每维结构：①WorkFleet 的需求要点 ②六个项目怎么做 ③WorkFleet 的取舍（→ 关联决策 DEC / 待定 Q / 增补 G）。

---

## 0. 一句话重新定位
六个项目没有一个是“多个编码 Agent ↔ 多个 IM 的路由器”：WCB 是微信接入层，PC 是任务中心的 AI 公司 OS，PA 是单主控 LLM 流水线，OR 是并行 Agent IDE，HS 是记忆服务，BF 是单任务多 Agent 舆情流水线（`40-综合/02 §0`）。外部“个人 Agent 网关”（OpenClaw、OpenHarness/ohmo、DeepSeek Harness）是“一个大脑 ↔ 多个 IM”。
**WorkFleet 的独有价值 = 统一消息账本 + 确定性路由 + 先汇总再分发的编排 + 接收人级权限 + 总控把关**，这五块必须自研；其余尽量借鉴或直接依赖。

---

## 1. 需求
- 要点：四模式（管理/通知/团队/总控）、四场景、拓展（定时、/clear、按 session/resume 查记录、分身 loop、知识库）。
- 六项目：WCB 只覆盖“微信接入”；PC 输入侧最全但通道写死且 1 endpoint=1 agent（`12 §12`）；PA 覆盖总控状态机；OR 覆盖多输入与编排；HS 覆盖分身与知识库；BF 覆盖会议与日报流水线。
- 取舍：需求按“路由内核（自研）+ 输入族（依赖 ACP 官方包）+ 输出族（借鉴/依赖渠道插件）+ 总控（组合 PA/OR/BF 设计）+ 记忆（外置 HS）”五块切分 → DEC-001。新增场景推演发现的缺口 → G1–G12（`02_requirements/inbox/REQ-INBOX-20261017-002-需求增补.md`）。

## 2. 前端
- 要点：后台配置管理（输入、输出、绑定、模式、调度、审批、历史检索）。
- 六项目：PC React 19 + Vite + Tailwind 4 + Radix/shadcn + TanStack Query，适配器 `getConfigSchema()` 驱动表单（`12 §7`）；OR React 19 + zustand + xterm；HS Next.js 16 控制台；PA React 19 + Apollo；WCB f-string 内嵌 HTML；BF 5.4MB 单页（反例）。
- 取舍：**Schema 驱动表单**（每个输入/输出适配器声明 JSON Schema，前端自动渲染）——这是最大复用点，新增渠道不写前端代码 → DEC-010。框架随主栈（Q-01）。首屏只做三页：输入、输出、绑定（含 dry-run 路由预览）。

## 3. 后端
- 要点：设备端常驻、零外部依赖、多输入并发、不阻塞。
- 六项目：PC/HS/OR 均为“单进程事件循环 + 持久化队列”，且都在走向“控制面 / 执行面分离”（PC Runner、OR orcad、HS worker，`40-综合/02 §6`）；WCB 账号内串行 await、PA 子任务串行、BF 多进程 + 文件总线（均为反例）。
- 取舍：单进程网关（控制面）+ 每个 Agent 一个子进程（执行面）+ 单实例锁（OR orcad 语义）→ DEC-002、DEC-003。

## 4. 数据
- 要点：消息可追溯、会话可续接、/clear 新开、按 session/resume ID 查。
- 六项目：PC `session_display_id` + `session_generation` + 幂等键 `chat:{endpoint}:{thread}:{generation}`（`12 §4`）；OR 编排 schema（runs/tasks/dispatch/messages/deliveries/decision_gates）+ 会话表 `resume_command` + FTS5（`14 §3`），并且吃过“会话身份迁移 v2→v43”的亏；WCB 游标 `get_updates_buf`；PA flow→task→subtask→msgchain 四级；HS bank 隔离 + document_id。
- 取舍：**统一事件账本 `event`（append-only）+ outbox + 稳定会话主键 + generation + display_id + 原生 resume_id** 从第一天建 → DEC-004。消息→来源 Agent→会话的反向索引（G2）。

## 5. 交互
- 要点：IM 端命令（/clear、/use、@别名、/history、/stop）、审批、汇报阅读体验。
- 六项目：PC 状态消息可编辑合并；OR 待答权限时 held；WCB 扫码状态机 + 三种二维码兜底；PA ask 屏障；BF 主持四段式纪要。外部：cc-connect IM 内审批 + 卡片按钮；dsh-channels `/stop /new /bind /mirror /model`。
- 取舍：命令集 = `/clear /use /@别名 /history /stop /status /bind /mirror`；审批优先卡片按钮，无按钮渠道用 `Y1/N1` 口令 → DEC-011。held 投递 → DEC-012。

## 6. 逻辑
- 要点：多对多路由、先汇总再分发、总控每次把关、会议。
- 六项目：PA Plan-Execute-Replan + Waiting 语义 + 三道护栏；OR coordinator tick（消息→上报→派工，并发 4，熔断，gate）；BF HostPolicy（轮次完成/每 N 条/冲突）+ 纪要注入下一轮；PC run coordinator 固定顺序。外部：OpenClaw 确定性路由“模型不选渠道”。
- 取舍：路由由绑定表确定（不让 LLM 选渠道）→ DEC-005；团队模式绝不默认广播 → DEC-006；总控模式下每条输出必经把关（原文要求）→ DEC-018；会议用结构化事件、不用日志抓取 → DEC-019；汇总屏障（G1）。

## 7. 组件
- 要点：输入适配器、输出适配器、路由器、调度器、总控、记忆桥。
- 六项目：PC `ServerAdapterModule`（execute/sessionCodec/listModels/listSkills/getConfigSchema）；OR `AcpLaunchSpec` 一行 + `AcpDialect`；PA 工具接口两方法 `Handle/IsAvailable`；dsh-channels `defineChannelAdapter({capabilities, start, stop, send})`。
- 取舍：`InputAdapterSpec`（表驱动，取 OR 字段语义）+ `ChannelAdapter`（capabilities 协商，核心不做渠道特判）→ DEC-007、DEC-008。

## 8. 复用
- 六项目许可决定深度（F-06）：PC/OR 可移植代码（保留版权声明）；HS 作为外部服务直接用；PA/BF/WCB 只借设计（clean-room）。
- 取舍：可直接依赖 = ACP 官方 SDK、`claude-agent-acp`、`codex-acp`、Cursor `agent acp`、HS v1.0.0；可移植 = OR M1–M4（ACP peer、session setup、launch spec、编排 schema）、PC 会话模型与能力矩阵；只借设计 = PA/BF/WCB → DEC-009。第三方声明统一放 `THIRD_PARTY_NOTICES`。

## 9. 拓展
- 六项目：PC 进程外插件 + manifest + 能力门控（好）但聊天通道写死常量 + DB CHECK（坏）；HS `module:Class` + webhook；PA 新 provider 改 9 处 + DB enum（坏）；BF 新 Agent 改 6 处（坏）。
- 取舍：新增输入 = 一条 spec；新增渠道 = 一个包；**不把渠道/输入类型写成 DB 枚举或 CHECK** → DEC-008。第一版插件进程内加载，接口按进程外可迁移设计（Q-11 可延后）。

## 10. 性能
- 要点：S1 6 工具并发；S4 1 万订阅者 9:00 推送。
- 六项目：OR SQLite 邮箱 durable enqueue + 批 ≤50 + ack 前重放 + in-flight 去重；HS `FOR UPDATE SKIP LOCKED`，轮询 500ms，worker 槽位预留；PC endpoint `burst/queue/debounce/drop/concurrent`。
- 取舍：SQLite WAL 单写者 + 表即队列 + 内存唤醒信号；每渠道令牌桶（飞书 5 QPS/用户、群）；S4 按渠道分批 → DEC-013。V0.0.2 推演：Telegram 1 万人约 6.2 分钟（`40-综合/08`，部分确认）。

## 11. 配置
- 六项目：PC 三层 env > 文件 > 默认 + 业务配置入库可 UI 编辑 + 插件只存 `secret_ref`；HS 全局 → tenant → bank + 模板；PA 按角色配模型 + 提示词可编辑并渲染校验；BF 4 份配置源（反例）；外部 OpenClaw JSON5 + doctor 校验。
- 取舍：启动级配置（端口、数据目录、密钥源）走文件 + env；业务配置（输入/输出/绑定/调度/总控）入库、UI 编辑、可导出为 YAML 做版本管理；提供 `doctor` 自检 → DEC-014。

## 12. 知识库
- 六项目：HS 四路 recall + consolidation → MM + directives；PA pgvector + Graphiti；BF GraphRAG 合入后撤销（复杂度教训）；OR 仅会话检索。
- 取舍：第一阶段只做“会话检索”（FTS，中文 trigram）；知识库与分身外置 HS，HS 不可用时降级、绝不阻断路由 → DEC-015。是否在 MVP 启用 HS → Q-09。

## 13. 响应
- 要点：IM 端尽快有回音；长任务不刷屏。
- 六项目：cc-connect `instant_reply` + `stream_preview`；飞书卡片流式更新（F-09）；BF SSE + Last-Event-ID；PC fast responses（3 秒回执）。
- 取舍：入站即回执（≤3 秒，飞书硬约束）；过程消息合并为可编辑的状态卡（支持编辑的渠道）或小时级摘要（微信，受额度限制）；只推完成/失败/审批/阻塞 → DEC-017。

## 14. 存储
- 六项目：WCB token 明文、context_token 只在内存（反例）；PC 嵌入式 PG；OR `node:sqlite` WAL；HS PG；BF 文件。
- 取舍：SQLite 单库（WAL），凭据/游标/context_token 全部持久化并加密（主密钥在 OS 钥匙串，Windows 用 DPAPI），附件放数据目录、库里只存引用；提供“导出恢复密钥”以便换机 → DEC-004、DEC-020。

## 15. 资源
- 六项目：OR 终端进程数与内存上限、每 tick 最多新建 1 终端、managedRuntime 回收旧版本；HS worker 槽位预留；cc-connect 空闲 Agent 进程回收。
- 取舍：每个输入端会话一个子进程，空闲超时回收；全局并发上限与每 Agent 并发上限；Windows 用 Job Object 管进程树 → DEC-021。

## 16. 通信
- 要点：输入侧 ACP（stdio JSON-RPC），输出侧各 IM 长连接/长轮询，管理侧 HTTP。
- 六项目：OR ACP JSON-RPC peer（NDJSON、上限、超时、写队列）；WCB 长轮询 35 秒、只出站；PC WS + REST；HS REST + MCP；PA GraphQL 订阅；BF Socket.IO/SSE。
- 取舍：ACP v1 为输入长期契约（v2 开关）；全部渠道走长连接/长轮询，**不需要公网 IP**（F-09/`30/03:24`）；管理 API 只绑 127.0.0.1；对 Agent 额外提供 MCP 推送工具（借鉴 WCB 6 个 MCP 工具）→ DEC-022。

## 17. 警告 / 通知
- 六项目：WCB 401/403 → expired、重复扫码作废提示；PC 能力矩阵 `proactiveDirectMessages`；HS webhook（consolidation.completed 等）；OR 桌面/手机通知、escalation 优先级。
- 取舍：通知分 p0–p3 四级；渠道健康告警（凭据过期、额度将尽、长连接断开）独立于业务消息，走“备用渠道”；微信额度预算器，超额降级到备用渠道或合并摘要 → DEC-023。备用渠道选哪个 → Q-05。

## 18. 异常 / 报告
- 六项目：PA reflector/mentor 护栏、密钥脱敏；BF IR + 校验修复 + 救援 LLM 链；PC 插件有界退避重启；OR 熔断 + supervise（6 次/15 分钟放弃）。
- 取舍：三类重试策略表（适配器/模型/IM 发送，交互类首次延迟 ≤2 秒）；失败进死信并在控制台可重放；外发前脱敏（PA 模式）；日报/周报用小而稳的 IR 子集（heading/paragraph/list/table/callout/kpi）按渠道渲染 → DEC-024；一键急停 `/stop all`（G9）。

---

## 19. 横向结论
1. 五块必须自研：消息账本、确定性路由、汇总编排、接收人权限、总控把关。
2. 三块直接依赖：ACP 官方包、渠道官方 SDK/插件（许可核实后）、Hindsight（可选）。
3. 六个反模式全部规避：串行 await、日志当总线、渠道写死枚举、凭据明文、Docker+root、无并发上限。
4. 新仓下主栈不再有“复用”理由，选型取决于用户熟悉度与生态（Q-01）。
