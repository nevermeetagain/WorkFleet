---
id: WF-DOC-INDEX
type: index
title: 文档总索引（落盘清单）
status: active
version: V0.0.4
created: 2026-10-17
---

# Document Index（236 个文件）

| 路径 | 类型 | 标题 |
|---|---|---|
| `00_governance/README.md` | governance | WorkFleet V0.0.4 文档入口 |
| `00_governance/assumptions.md` | assumption | 假设登记册 |
| `00_governance/dependencies.md` | dependency | 外部依赖登记册 |
| `00_governance/document-standard.md` | project | WorkFleet 文档规范（元数据 / Type / ID / 状态 / 命名） |
| `00_governance/glossary.md` | glossary | 术语表（一个概念一个名字） |
| `00_governance/project-map.md` | project-map | 项目地图（目标代码结构 + 文档追溯链） |
| `00_governance/risks.md` | risk | 风险登记册 |
| `00_governance/stakeholders.md` | project | 角色与责任（Stakeholders） |
| `01_product/product-goals.md` | product | 产品目标 |
| `01_product/product-scope.md` | product | 产品范围（v1 In / Out） |
| `01_product/product-vision.md` | product | 产品愿景 |
| `01_product/success-metrics.md` | product | 成功指标（用户可感） |
| `01_product/user-guide.md` | product | WorkFleet 大白话使用说明（v1 设计态） |
| `02_requirements/backlog.md` | backlog | 需求待办池（v2+） |
| `02_requirements/product-requirements.md` | requirement-baseline | 产品需求基线（v1） |
| `02_requirements/rejected.md` | index | 被拒绝/取消需求 |
| `02_requirements/constraints/REQ-C-001.md` | constraint | 技术栈 TypeScript/Node 22 LTS；前端 |
| `02_requirements/constraints/REQ-C-002.md` | constraint | 许可 Apache-2.0；AGPL/EULA 代码零拷贝； |
| `02_requirements/constraints/REQ-C-003.md` | constraint | 端口段 5100–5200；中转公网仅 443 |
| `02_requirements/constraints/REQ-C-004.md` | constraint | 一个 Bot 身份只允许一个消费者；不与 OpenClaw |
| `02_requirements/constraints/REQ-C-005.md` | constraint | 中转暂定香港，Ubuntu/Linux |
| `02_requirements/constraints/REQ-C-006.md` | constraint | 模型调用只在本机节点；中转不运行模型、不存模型 Key |
| `02_requirements/constraints/REQ-C-007.md` | constraint | 仓库治理：分支 + PR；目录与文档按三份规范；版本文档在 |
| `02_requirements/constraints/REQ-C-008.md` | constraint | 微信 iLink：个人授权、24h context_toke |
| `02_requirements/constraints/REQ-C-009.md` | constraint | ZCode 协议私有且未文档化，社区 ACP 桥有 ToS |
| `02_requirements/features/REQ-F-001-本机节点.md` | requirement | 本机节点 |
| `02_requirements/features/REQ-F-002-云中转与多租户.md` | requirement | 云中转与多租户 |
| `02_requirements/features/REQ-F-003-账号、组织与角色.md` | requirement | 账号、组织与角色 |
| `02_requirements/features/REQ-F-004-项目一级对象与主-子项目.md` | requirement | 项目一级对象与主/子项目 |
| `02_requirements/features/REQ-F-005-一个账号多台设备.md` | requirement | 一个账号多台设备 |
| `02_requirements/features/REQ-F-006-多中转连接.md` | requirement | 多中转连接 |
| `02_requirements/features/REQ-F-007-通用ACP输入.md` | requirement | 通用 ACP 输入 |
| `02_requirements/features/REQ-F-008-非ACP输入-Coze与Webhook.md` | requirement | 非 ACP 输入：Coze 与 Webhook |
| `02_requirements/features/REQ-F-009-输出端-微信ClawBot.md` | requirement | 输出端：微信 ClawBot |
| `02_requirements/features/REQ-F-010-输出端-飞书Lark.md` | requirement | 输出端：飞书/Lark |
| `02_requirements/features/REQ-F-011-输出端-QQ.md` | requirement | 输出端：QQ 官方机器人 |
| `02_requirements/features/REQ-F-012-输出端-钉钉.md` | requirement | 输出端：钉钉 |
| `02_requirements/features/REQ-F-013-输出端-Telegram.md` | requirement | 输出端：Telegram |
| `02_requirements/features/REQ-F-014-输出端-Discord.md` | requirement | 输出端：Discord |
| `02_requirements/features/REQ-F-015-Web控制台对话.md` | requirement | Web 控制台对话（默认渠道） |
| `02_requirements/features/REQ-F-016-绑定与三种模式.md` | requirement | 绑定与三种模式 |
| `02_requirements/features/REQ-F-017-回复溯源与按发送人分会话.md` | requirement | 回复溯源与按发送人分会话 |
| `02_requirements/features/REQ-F-018-IM与控制台指令.md` | requirement | IM 与控制台指令 |
| `02_requirements/features/REQ-F-019-会话与记录查询.md` | requirement | 会话与记录查询 |
| `02_requirements/features/REQ-F-020-审批与held.md` | requirement | 审批与 held |
| `02_requirements/features/REQ-F-021-汇总屏障.md` | requirement | 汇总屏障 |
| `02_requirements/features/REQ-F-022-总控-把关分级.md` | requirement | 总控：把关分级 |
| `02_requirements/features/REQ-F-023-总控-随时对话与分派.md` | requirement | 总控：随时对话与任务分派 |
| `02_requirements/features/REQ-F-024-总控-会议.md` | requirement | 总控：会议 |
| `02_requirements/features/REQ-F-025-总控-导入任务清单.md` | requirement | 总控：导入任务清单 |
| `02_requirements/features/REQ-F-026-模型配置与费用上限.md` | requirement | 模型配置与费用上限 |
| `02_requirements/features/REQ-F-027-接收人级权限与脱敏.md` | requirement | 接收人级权限与脱敏 |
| `02_requirements/features/REQ-F-028-审计.md` | requirement | 审计 |
| `02_requirements/features/REQ-F-029-分身数据采集.md` | requirement | 分身数据采集 |
| `02_requirements/features/REQ-F-030-通知分级与渠道健康.md` | requirement | 通知分级与渠道健康 |
| `02_requirements/features/REQ-F-031-Bot唯一消费者与画像向导.md` | requirement | Bot 唯一消费者与画像向导 |
| `02_requirements/features/REQ-F-032-同目录并发写保护.md` | requirement | 同目录并发写保护 |
| `02_requirements/features/REQ-F-033-急停.md` | requirement | 急停 |
| `02_requirements/features/REQ-F-034-配置导入导出与doctor.md` | requirement | 配置导入导出与 doctor |
| `02_requirements/features/REQ-F-035-恢复密钥与换机.md` | requirement | 恢复密钥与换机 |
| `02_requirements/features/REQ-F-036-异常阈值.md` | requirement | 异常阈值 |
| `02_requirements/inbox/REQ-INBOX-20261017-003-V0.0.4开工指令.md` | requirement-inbox | V0.0.4 开工指令（原话） |
| `02_requirements/non-functional/REQ-NF-001-响应时延.md` | requirement | 响应时延 |
| `02_requirements/non-functional/REQ-NF-002-并发与资源.md` | requirement | 并发与资源 |
| `02_requirements/non-functional/REQ-NF-003-可靠性.md` | requirement | 可靠性 |
| `02_requirements/non-functional/REQ-NF-004-安全.md` | requirement | 安全 |
| `02_requirements/non-functional/REQ-NF-005-隐私与数据主权.md` | requirement | 隐私与数据主权 |
| `02_requirements/non-functional/REQ-NF-006-可移植.md` | requirement | 可移植 |
| `02_requirements/non-functional/REQ-NF-007-可观测.md` | requirement | 可观测 |
| `02_requirements/non-functional/REQ-NF-008-可扩展.md` | requirement | 可扩展 |
| `02_requirements/non-functional/REQ-NF-009-可测试.md` | requirement | 可测试 |
| `02_requirements/non-functional/REQ-NF-010-成本.md` | requirement | 成本 |
| `02_requirements/non-functional/REQ-NF-011-可用性与语言.md` | requirement | 可用性与语言 |
| `03_solution/architecture.md` | architecture | WorkFleet 总体架构（v1） |
| `03_solution/constraints.md` | constraints | 技术/业务约束汇总 |
| `03_solution/technical-requirements.md` | technical-requirements | 技术需求 |
| `03_solution/contracts/README.md` | contract-index | 契约冻结包（六份） |
| `03_solution/decisions/ADR-001-部署分两侧.md` | adr | 部署分两侧：本机节点 + 云中转 |
| `03_solution/decisions/ADR-002-契约唯一源.md` | adr | 契约唯一源 = JSON Schema（2020-12），API 用 OpenAPI 3.1 引用 |
| `03_solution/decisions/ADR-003-存储.md` | adr | 存储：中转与节点均用 SQLite（WAL，单写者） |
| `03_solution/decisions/ADR-004-仓库形态.md` | adr | 仓库形态：pnpm workspaces Monorepo + Makefile 统一入口，Node 22 LTS，TypeScript 5（strict） |
| `03_solution/decisions/ADR-005-中转↔节点协议.md` | adr | 中转 ↔ 节点协议：WSS + JSON envelope + 每方向单调 seq + 累积 ack + 断线续传 |
| `03_solution/decisions/ADR-006-鉴权与权限.md` | adr | 鉴权与权限：Web 用 HttpOnly 会话 Cookie；节点用配对码换设备令牌；RBAC 三角色 + 项目范围 |
| `03_solution/decisions/ADR-007-输入端.md` | adr | 输入端：通用 ACP 适配器 + ACP Registry + 本地 InputAdapterSpec 表；非 ACP 用专用适配器 |
| `03_solution/decisions/ADR-008-前端.md` | adr | 前端：React 19 + Vite + TanStack Query + Zustand + Radix/shadcn + Tailwind 4；一份 SPA 两个构建目标；PWA |
| `03_solution/decisions/ADR-009-后端运行栈.md` | adr | 后端运行栈：Fastify 5 + ws + better-sqlite3 + Kysely + pino + ajv |
| `03_solution/decisions/ADR-010-IM适配器实现来源与许可边界.md` | adr | IM 适配器实现来源与许可边界 |
| `03_solution/decisions/ADR-011-架构守卫与CI门禁.md` | adr | 架构守卫与 CI 门禁 |
| `03_solution/decisions/ADR-012-全局命名与格式.md` | adr | 全局命名与格式 |
| `03_solution/decisions/ADR-013-总控的模型调用.md` | adr | 总控的模型调用：自写薄客户端（OpenAI 兼容 + Anthropic Messages），规则把关兜底 |
| `03_solution/decisions/ADR-014-PWA与WebPush.md` | adr | PWA 与 Web Push |
| `03_solution/decisions/ADR-015-契约修订CR-001.md` | adr | 契约修订 CR-001（规划评审闭环） |
| `03_solution/design/DESIGN-001-前端.md` | design | 前端详细设计（apps/web：一份 SPA，relay / node 两个构建目标） |
| `03_solution/design/DESIGN-002-后端-云中转.md` | design | 后端详细设计 · 云中转（apps/relay） |
| `03_solution/design/DESIGN-003-后端-本机节点.md` | design | 后端详细设计 · 本机节点（apps/node） |
| `03_solution/design/DESIGN-004-数据.md` | design | 数据详细设计（relay.db / node.db 的 0001 迁移逐表说明与迁移编排） |
| `03_solution/design/DESIGN-005-交互.md` | design | 交互详细设计（IM 指令、审批、Web 对话、引用回复、离线、扫码与 /bind、空态文案） |
| `03_solution/design/DESIGN-006-逻辑.md` | design | 逻辑详细设计（路由算法、四种模式、汇总屏障、按发送人分会话、dry-run） |
| `03_solution/design/DESIGN-007-组件.md` | design | 组件与端口详细设计（ChannelAdapter、InputAdapter/AcpDialect、Renderer、Repository、事件总线） |
| `03_solution/design/DESIGN-008-复用.md` | design | 复用详细设计（直接依赖、可移植代码、只借设计、THIRD_PARTY_NOTICES、DEC-009） |
| `03_solution/design/DESIGN-009-拓展.md` | design | 拓展详细设计（新增渠道/ACP 智能体/模式的步骤；v2–v4 路线图挂载点；插件进程外化） |
| `03_solution/design/DESIGN-010-性能.md` | design | 性能详细设计（用户可感核心操作、预算与测量、SQLite 写入、令牌桶、批量、背压、场景推演） |
| `03_solution/design/DESIGN-011-配置.md` | design | 配置详细设计（启动级配置全表、业务配置入库与 YAML 导出、doctor、.env.example） |
| `03_solution/design/DESIGN-012-知识库.md` | design | 知识库（v1 会话检索；v3 知识库/目录结构图谱/上下文记忆预留；Hindsight 可选接入） |
| `03_solution/design/DESIGN-013-响应.md` | design | 响应（≤3 秒回执、状态卡编辑合并、微信小时级摘要、推送面收敛、节点侧流式聚合、渠道降级矩阵） |
| `03_solution/design/DESIGN-014-存储.md` | design | 存储（数据目录布局、加密与钥匙串、附件、转录 JSONL、备份恢复、保留期与清理） |
| `03_solution/design/DESIGN-015-资源.md` | design | 资源（并发上限、空闲回收、子进程观测、进程树管理、文件句柄、连接数、中转主机规格） |
| `03_solution/design/DESIGN-016-通信协议.md` | design | 通信协议（中转↔节点 WSS 帧协议；ACP 使用面与帧映射；IM 侧收发模式） |
| `03_solution/design/DESIGN-017-告警与通知.md` | design | 告警与通知（p0–p3、渠道健康状态机、备用渠道、静默时段、Web Push、微信额度预算器） |
| `03_solution/design/DESIGN-018-异常与报告.md` | design | 异常与报告（三类重试表、死信与重放、熔断、急停、IR 汇报渲染、错误码规范、trace_id、运行日志与审计） |
| `03_solution/design/DESIGN-019-安全与权限.md` | design | 安全与权限（STRIDE、鉴权、RBAC+项目范围判定、越权测试、IM 发送者授权、提示注入防护、密钥扫描、明文告知） |
| `03_solution/design/DESIGN-020-总控.md` | design | 总控（把关管线、四分级准则、随时对话、任务分派、会议引擎、导入任务清单、成本控制、可观测） |
| `03_solution/design/DESIGN-021-分身数据.md` | design | 分身数据（采集点、中转 twin.capture 转发、节点存储、查看/修改/删除/导出、隐私边界、v4 学习 loop 预留） |
| `03_solution/design/DESIGN-022-模型配置与费用.md` | design | 模型配置与费用（字段、钥匙串写入流程、provider 薄客户端、usage 与费用公式、日/月上限与时区、超限动作、看板） |
| `03_solution/solutions/SOL-001-v1交付方案.md` | solution | WorkFleet v1 交付方案 |
| `04_planning/baseline-metrics.md` | plan | 基线指标（用户可感核心操作） |
| `04_planning/cost-budget.md` | plan | 档位分配与成本预算表 |
| `04_planning/current-plan.md` | plan | 当前执行计划（S0 步行骨架启动） |
| `04_planning/dag.md` | plan | 依赖 DAG 与并行判定 |
| `04_planning/milestones.md` | milestone | 里程碑（M0…M10 ↔ 切片 S0…S10） |
| `04_planning/ownership-matrix.md` | plan | 所有权矩阵 |
| `04_planning/roadmap.md` | plan | WorkFleet 产品路线图 |
| `04_planning/slices.md` | plan | 垂直切片清单 |
| `04_planning/steps/STEP-01-规划快照.md` | plan-step | 规划快照 |
| `04_planning/steps/STEP-02-事实基线.md` | plan-step | 事实基线（含文档与代码不一致清单） |
| `04_planning/steps/STEP-03-需求基线复核.md` | plan-step | 需求基线复核（复述/分级/冲突/未知/隐含） |
| `04_planning/steps/STEP-04-契约冻结包.md` | plan-step | 契约冻结包（六份） |
| `04_planning/steps/STEP-05-数据模型基线.md` | plan-step | 数据模型基线（含迁移版本号编排） |
| `04_planning/steps/STEP-06-垂直切片清单.md` | plan-step | 垂直切片清单 |
| `04_planning/steps/STEP-07-原子任务卡全集.md` | plan-step | 原子任务卡全集 |
| `04_planning/steps/STEP-08-依赖DAG.md` | plan-step | 依赖 DAG |
| `04_planning/steps/STEP-09-所有权矩阵.md` | plan-step | 所有权矩阵 |
| `04_planning/steps/STEP-10-档位分配与成本预算表.md` | plan-step | 档位分配与成本预算表 |
| `04_planning/steps/STEP-11-基线指标.md` | plan-step | 基线指标 |
| `04_planning/steps/STEP-12-风险-未决-待裁决.md` | plan-step | 风险 / 未决 / 待裁决 |
| `04_planning/steps/STEP-13-落盘清单.md` | plan-step | 落盘清单 |
| `04_planning/steps/STEP-14-自检结果.md` | plan-step | 自检结果 |
| `04_planning/steps/STEP-15-本次规划的前提与局限.md` | plan-step | 本次规划的前提与局限 |
| `04_planning/steps/STEP-16-建议的第一刀与启动顺序.md` | plan-step | 建议的第一刀与启动顺序 |
| `05_execution/task-index.md` | index | 任务索引（v1，84 张） |
| `05_execution/task-template.md` | template | 原子任务卡模板（16 项必填） |
| `05_execution/tasks.v1.json` |  |  |
| `05_execution/tasks/TASK-001.md` |  | TASK-001：Monorepo 脚手架、根白名单文件、AGENTS.md、Makefile 骨架 |
| `05_execution/tasks/TASK-002.md` |  | TASK-002：契约包构建：JSON Schema→TS 类型生成、ajv 校验器导出、示例校验测试、生成物漂移检查 |
| `05_execution/tasks/TASK-003.md` |  | TASK-003：迁移运行器（relay/node 共用）+ 应用 0001 + 仓储基类（Kysely） |
| `05_execution/tasks/TASK-004.md` |  | TASK-004：中转启动层：Fastify、core（config/logging/errors 映射 error-codes）、/health |
| `05_execution/tasks/TASK-005.md` |  | TASK-005：identity+tenancy：注册/登录/登出/me、会话 Cookie+CSRF、权限拦截器（permissions.json） |
| `05_execution/tasks/TASK-006.md` |  | TASK-006：devices：配对码、claim、node-gateway WSS（hello/welcome/ack/ping、outbox 续传、去重） |
| `05_execution/tasks/TASK-007.md` |  | TASK-007：节点启动层：单实例锁、relay-link（单中转）、`workfleet-node pair`、本地 outbox 续传 |
| `05_execution/tasks/TASK-008.md` |  | TASK-008：testkit：FakeAgent（ACP 录制回放）、FakeChannel、FakeRelay |
| `05_execution/tasks/TASK-009.md` |  | TASK-009：Web 骨架：路由、登录/注册/配对/设备列表页、data-access、UX 状态组件 |
| `05_execution/tasks/TASK-010.md` |  | TASK-010：中转 Web 渠道最小闭环：conversations/messages API、/api/v1/stream、agent.prompt/agent.output 转发 |
| `05_execution/tasks/TASK-011.md` |  | TASK-011：节点回声执行面：接收 agent.prompt，交给 FakeAgent，回 agent.output |
| `05_execution/tasks/TASK-012.md` |  | TASK-012：Web 聊天页（最小）：会话列表、消息流、发送框 |
| `05_execution/tasks/TASK-013.md` |  | TASK-013：步行骨架 E2E：注册→配对→发消息→收到回声（Playwright + 真中转 + 真节点 + FakeAgent） |
| `05_execution/tasks/TASK-014.md` |  | TASK-014：CI 守卫：dependency-cruiser、根污染、命名、gitleaks、契约测试、三平台矩阵 |
| `05_execution/tasks/TASK-021.md` |  | TASK-021：通用 ACP Host：spawn/initialize/session.new/prompt/cancel、进程树监管、权限请求→approval.request |
| `05_execution/tasks/TASK-022.md` |  | TASK-022：InputAdapterSpec 加载与探测；Claude Code/Codex/Cursor 夹具录制与真机冒烟 |
| `05_execution/tasks/TASK-023.md` |  | TASK-023：sessions：转录 JSONL+索引、/clear（generation）、loadSession 恢复、history.query/result |
| `05_execution/tasks/TASK-024.md` |  | TASK-024：指令解析器（im-commands.json）与 Web 渠道指令执行 |
| `05_execution/tasks/TASK-025.md` |  | TASK-025：历史检索 API：FTS trigram、displayId、nativeSessionId、节点转录拉取 |
| `05_execution/tasks/TASK-026.md` |  | TASK-026：agents-registry：agents.sync、智能体 CRUD 下发与别名唯一 |
| `05_execution/tasks/TASK-027.md` |  | TASK-027：Web：智能体列表/表单（rjsf 按 configSchema）、聊天指令、历史页 |
| `05_execution/tasks/TASK-028.md` |  | TASK-028：审批与 held（中转侧）：approval.request→待审批→decision→回节点；超时拒绝；held 队列 |
| `05_execution/tasks/TASK-029.md` |  | TASK-029：Web 审批卡与收件箱 |
| `05_execution/tasks/TASK-030.md` |  | TASK-030：S1 E2E：多轮、/clear、/history、审批、held |
| `05_execution/tasks/TASK-041.md` |  | TASK-041：微信 ClawBot 适配器：扫码登录、getupdates、sendmessage、context_token 持久化、额度预算器；真机验证 U-02/U-04 |
| `05_execution/tasks/TASK-042.md` |  | TASK-042：channels 核心：ChannelAdapter 端口、注册表、capabilities、凭据加密、健康状态 |
| `05_execution/tasks/TASK-043.md` |  | TASK-043：recipients：授权、/bind 识别我的账号、未授权固定提示 |
| `05_execution/tasks/TASK-044.md` |  | TASK-044：routing 内核：管理模式、/use 焦点、@别名、引用回复溯源、dry-run |
| `05_execution/tasks/TASK-045.md` |  | TASK-045：delivery：outbox 工作者、令牌桶、重试表、死信、IR 渲染降级、过程消息合并（DEC-017） |
| `05_execution/tasks/TASK-046.md` |  | TASK-046：Web：渠道页（扫码 UI）、接收人页、绑定编辑器 + dry-run |
| `05_execution/tasks/TASK-047.md` |  | TASK-047：IM 审批口令 Y{n}/N{n} 与无按钮渠道渲染 |
| `05_execution/tasks/TASK-048.md` |  | TASK-048：S2 E2E：FakeChannel(微信方言) 管理模式全链路 |
| `05_execution/tasks/TASK-061.md` |  | TASK-061：projects：主/子项目树、深度≤3、overview 汇总 |
| `05_execution/tasks/TASK-062.md` |  | TASK-062：多设备：主设备、按设备路由、离线排队提示 |
| `05_execution/tasks/TASK-063.md` |  | TASK-063：节点多中转：relay-link 管理、命名空间隔离、各自凭据 |
| `05_execution/tasks/TASK-064.md` |  | TASK-064：workspace-guard：写租约、自动 git worktree、AGENT_BUSY_WRITE_LEASE |
| `05_execution/tasks/TASK-065.md` |  | TASK-065：Web：项目树、设备页、跨项目视图 |
| `05_execution/tasks/TASK-066.md` |  | TASK-066：本机控制台（node 构建目标）：中转连接、适配器探测、诊断页 |
| `05_execution/tasks/TASK-067.md` |  | TASK-067：S3 集成/E2E：两中转隔离、两设备路由、写冲突 |
| `05_execution/tasks/TASK-081.md` |  | TASK-081：ACP 智能体组 A：Gemini CLI、Qwen Code、Kimi CLI、OpenCode（spec 实测+夹具） |
| `05_execution/tasks/TASK-082.md` |  | TASK-082：ACP 智能体组 B：Goose、Cline、Qoder CLI、GitHub Copilot CLI（spec 实测+夹具） |
| `05_execution/tasks/TASK-083.md` |  | TASK-083：OpenClaw（openclaw acp）接入与历史范围标注（G15） |
| `05_execution/tasks/TASK-084.md` |  | TASK-084：ZCode 实验适配器（zcode-acp-server / app-server 方言） |
| `05_execution/tasks/TASK-085.md` |  | TASK-085：Coze HTTP 适配器 |
| `05_execution/tasks/TASK-086.md` |  | TASK-086：Webhook 输入（127.0.0.1:5102，HMAC 签名） |
| `05_execution/tasks/TASK-087.md` |  | TASK-087：S4 输入冒烟矩阵与证据汇总 |
| `05_execution/tasks/TASK-101.md` |  | TASK-101：飞书/Lark 适配器：长连接、卡片、按钮、卡片更新、双域 |
| `05_execution/tasks/TASK-102.md` |  | TASK-102：routing：通知模式（按发送人分会话）、团队模式（只到一个目标）、模式约束校验 |
| `05_execution/tasks/TASK-103.md` |  | TASK-103：orchestration：汇总屏障（N 来源或超时、缺失标注） |
| `05_execution/tasks/TASK-104.md` |  | TASK-104：Web：模式选择、屏障配置与状态 |
| `05_execution/tasks/TASK-105.md` |  | TASK-105：S5 E2E：通知/团队/屏障（FakeChannel 飞书方言） |
| `05_execution/tasks/TASK-121.md` |  | TASK-121：QQ 官方机器人适配器 |
| `05_execution/tasks/TASK-122.md` |  | TASK-122：钉钉 Stream 适配器 |
| `05_execution/tasks/TASK-123.md` |  | TASK-123：Telegram 适配器 |
| `05_execution/tasks/TASK-124.md` |  | TASK-124：Discord 适配器 |
| `05_execution/tasks/TASK-125.md` |  | TASK-125：notifications：p0–p3、渠道健康告警、备用渠道 |
| `05_execution/tasks/TASK-126.md` |  | TASK-126：渠道一致性测试套件（每个适配器跑同一套用例） |
| `05_execution/tasks/TASK-141.md` |  | TASK-141：成员、邀请、项目范围（projectScope） |
| `05_execution/tasks/TASK-142.md` |  | TASK-142：permissions-filter：接收人×业务线×字段过滤与脱敏 |
| `05_execution/tasks/TASK-143.md` |  | TASK-143：audit：出站/管理审计、投递明细、死信重放 |
| `05_execution/tasks/TASK-144.md` |  | TASK-144：twin：采集（twin.capture）、节点存储、本机查看/修改/删除/导出 |
| `05_execution/tasks/TASK-145.md` |  | TASK-145：Web：成员、过滤规则、审计、投递；本机分身页 |
| `05_execution/tasks/TASK-146.md` |  | TASK-146：安全审查：越权矩阵测试、密钥扫描、提示注入标记 |
| `05_execution/tasks/TASK-161.md` |  | TASK-161：models：钥匙串抽象（DPAPI/Keychain/libsecret/加密文件）、模型配置 CRUD、用量与费用 |
| `05_execution/tasks/TASK-162.md` |  | TASK-162：provider 薄客户端：OpenAI 兼容 + Anthropic（流式、工具、usage） |
| `05_execution/tasks/TASK-163.md` |  | TASK-163：supervisor 把关分级（规则 + LLM，超限降级）与 supervisor 路由模式 |
| `05_execution/tasks/TASK-164.md` |  | TASK-164：总控随时对话（/boss）与任务分派 |
| `05_execution/tasks/TASK-165.md` |  | TASK-165：Web 本机：模型配置、用量看板、总控设置 |
| `05_execution/tasks/TASK-166.md` |  | TASK-166：S8 E2E：把关四分级、超限降级、随时对话不打断 |
| `05_execution/tasks/TASK-181.md` |  | TASK-181：meetings 引擎：轮次、发言、纪要、决策、全员或超时 |
| `05_execution/tasks/TASK-182.md` |  | TASK-182：导入任务清单（task-template 解析）与依赖顺序分派 |
| `05_execution/tasks/TASK-183.md` |  | TASK-183：Web：会议回放与任务看板 |
| `05_execution/tasks/TASK-184.md` |  | TASK-184：S9 E2E：会议与导入分派 |
| `05_execution/tasks/TASK-201.md` |  | TASK-201：急停（中转）：/stop all、EMERGENCY_STOPPED、恢复 |
| `05_execution/tasks/TASK-202.md` |  | TASK-202：急停（节点）：冻结所有会话与队列、恢复 |
| `05_execution/tasks/TASK-203.md` |  | TASK-203：Web Push 发送（VAPID）与订阅管理（中转） |
| `05_execution/tasks/TASK-204.md` |  | TASK-204：PWA：manifest、service worker、订阅 UI |
| `05_execution/tasks/TASK-205.md` |  | TASK-205：配置导出/导入（中转，YAML，不含密钥，dry-run 差异） |
| `05_execution/tasks/TASK-206.md` |  | TASK-206：节点 doctor 与恢复密钥导出/导入 |
| `05_execution/tasks/TASK-207.md` |  | TASK-207：Bot 唯一消费者检测与告警 |
| `05_execution/tasks/TASK-208.md` |  | TASK-208：画像向导 P1/P2（Web） |
| `05_execution/tasks/TASK-209.md` |  | TASK-209：安装与部署：三平台节点安装/自启、中转 systemd + Caddy 脚本 |
| `05_execution/tasks/TASK-210.md` |  | TASK-210：v1 验收回归与基线指标测量 |
| `05_execution/tasks/TASK-211.md` |  | TASK-211：文档同步：用户指南、project-map、task-index 状态 |
| `06_validation/self-check.md` | validation | 规划自检（用户规划指令 §12）与前提局限、待裁决 |
| `06_validation/validation-plan.md` | validation | 验证计划 |
| `06_validation/acceptance/README.md` | validation | 验收记录（VAL）目录规则与模板 |
| `06_validation/evidence/README.md` | evidence | 证据（EVD）目录规则 |
| `07_release/changelog.md` | release | 文档版本变更日志 |
| `08_knowledge/fact-baseline.md` | knowledge | WorkFleet V0.0.4 规划快照与事实基线 |
| `08_knowledge/lessons-learned.md` | knowledge | 经验教训 |
| `08_knowledge/meetings/qa-log.md` | meeting | 关键问答记录 |
| `09_archive/superseded/README.md` | project | 被取代的决策登记（V0.0.3 → V0.0.4） |
| `00_governance/document-index.md` | index | 本文件 |

## 仓库根（规划指令 §11 允许路径）
| 路径 | 用途 |
|---|---|
| `packages/contracts/**` | 契约唯一源（67 个 schema、2 份 OpenAPI、错误码、权限、帧、事件、资源、UX 状态、适配器表、指令表） |
| `database/migrations/relay/0001_init.sql`、`0002_contract_revision_cr001.sql` | 中转数据模型基线 |
| `database/migrations/node/0001_init.sql`、`0002_contract_revision_cr001.sql` | 节点数据模型基线 |
