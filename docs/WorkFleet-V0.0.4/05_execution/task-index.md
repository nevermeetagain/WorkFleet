---
id: WF-TASK-INDEX
type: index
title: 任务索引（v1，84 张）
status: active
version: V0.0.4
created: 2026-10-17
---

# 任务索引

> **CR-001（ADR-015）已在开工前修订契约与迁移**：卡内因契约缺口标注的 blocked/权宜方案（如智能体下发、总控模式同步、节点主动开会话、shortCode 分配、stream 事件、历史检索参数、Webhook 防重放、备用渠道等）以 ADR-015 §4 为准；执行者按修订后契约实现。补充所有权规则见 `04_planning/ownership-matrix.md` §1.1。

> 状态口径见 `task-template.md` §状态；Done 定义见 `04_planning/current-plan.md` §完成定义。编号按切片分段：S0 001–020、S1 021–040、S2 041–060、S3 061–080、S4 081–100、S5 101–120、S6 121–140、S7 141–160、S8 161–180、S9 181–200、S10 201–220。

| 任务 | 切片 | 名称 | 来源需求 | 所有者 | 档位 | 依赖 | 规模 | 状态 |
|---|---|---|---|---|---|---|---|---|
| [TASK-001](tasks/TASK-001.md) | S0 | Monorepo 脚手架、根白名单文件、AGENTS.md、Makefile 骨架 | REQ-C-001/007 | Agent-Guard | sonnect | — | 中 | todo |
| [TASK-002](tasks/TASK-002.md) | S0 | 契约包构建：JSON Schema→TS 类型生成、ajv 校验器导出、示例校验测试、生成物漂移检查 | REQ-NF-009 | Agent-Contract | sonnect | TASK-001 | 中 | todo |
| [TASK-003](tasks/TASK-003.md) | S0 | 迁移运行器（relay/node 共用）+ 应用 0001 + 仓储基类（Kysely） | REQ-F-002 | Agent-Data | sonnect | TASK-001 | 中 | todo |
| [TASK-004](tasks/TASK-004.md) | S0 | 中转启动层：Fastify、core（config/logging/errors 映射 error-codes）、/health | REQ-F-002 | Agent-Relay | sonnect | TASK-002 | 小 | todo |
| [TASK-005](tasks/TASK-005.md) | S0 | identity+tenancy：注册/登录/登出/me、会话 Cookie+CSRF、权限拦截器（permissions.json） | REQ-F-002/003 | Agent-Relay | opus | TASK-003, TASK-004 | 大 | todo |
| [TASK-006](tasks/TASK-006.md) | S0 | devices：配对码、claim、node-gateway WSS（hello/welcome/ack/ping、outbox 续传、去重） | REQ-F-001/002 | Agent-Relay | opus | TASK-005 | 大 | todo |
| [TASK-007](tasks/TASK-007.md) | S0 | 节点启动层：单实例锁、relay-link（单中转）、`workfleet-node pair`、本地 outbox 续传 | REQ-F-001 | Agent-Node | sonnect | TASK-002, TASK-003 | 大 | todo |
| [TASK-008](tasks/TASK-008.md) | S0 | testkit：FakeAgent（ACP 录制回放）、FakeChannel、FakeRelay | REQ-NF-009 | Agent-QA | sonnect | TASK-002 | 中 | todo |
| [TASK-009](tasks/TASK-009.md) | S0 | Web 骨架：路由、登录/注册/配对/设备列表页、data-access、UX 状态组件 | REQ-F-015 | Agent-App | sonnect | TASK-002 | 大 | todo |
| [TASK-010](tasks/TASK-010.md) | S0 | 中转 Web 渠道最小闭环：conversations/messages API、/api/v1/stream、agent.prompt/agent.output 转发 | REQ-F-015 | Agent-Relay | sonnect | TASK-006 | 中 | todo |
| [TASK-011](tasks/TASK-011.md) | S0 | 节点回声执行面：接收 agent.prompt，交给 FakeAgent，回 agent.output | REQ-F-015 | Agent-Node | sonnect | TASK-007, TASK-008 | 小 | todo |
| [TASK-012](tasks/TASK-012.md) | S0 | Web 聊天页（最小）：会话列表、消息流、发送框 | REQ-F-015 | Agent-App | sonnect | TASK-009, TASK-010 | 中 | todo |
| [TASK-013](tasks/TASK-013.md) | S0 | 步行骨架 E2E：注册→配对→发消息→收到回声（Playwright + 真中转 + 真节点 + FakeAgent） | REQ-F-015 | Agent-QA | sonnect | TASK-011, TASK-012 | 中 | todo |
| [TASK-014](tasks/TASK-014.md) | S0 | CI 守卫：dependency-cruiser、根污染、命名、gitleaks、契约测试、三平台矩阵 | REQ-NF-004/006/009 | Agent-Guard | sonnect | TASK-001, TASK-002 | 中 | todo |
| [TASK-021](tasks/TASK-021.md) | S1 | 通用 ACP Host：spawn/initialize/session.new/prompt/cancel、进程树监管、权限请求→approval.request | REQ-F-007 | Agent-Node | opus | TASK-011 | 大 | todo |
| [TASK-022](tasks/TASK-022.md) | S1 | InputAdapterSpec 加载与探测；Claude Code/Codex/Cursor 夹具录制与真机冒烟 | REQ-F-007 | Agent-Node | sonnect | TASK-021 | 中 | todo |
| [TASK-023](tasks/TASK-023.md) | S1 | sessions：转录 JSONL+索引、/clear（generation）、loadSession 恢复、history.query/result | REQ-F-019 | Agent-Node | sonnect | TASK-021 | 中 | todo |
| [TASK-024](tasks/TASK-024.md) | S1 | 指令解析器（im-commands.json）与 Web 渠道指令执行 | REQ-F-018 | Agent-Relay | sonnect | TASK-010 | 中 | todo |
| [TASK-025](tasks/TASK-025.md) | S1 | 历史检索 API：FTS trigram、displayId、nativeSessionId、节点转录拉取 | REQ-F-019 | Agent-Relay | sonnect | TASK-010 | 中 | todo |
| [TASK-026](tasks/TASK-026.md) | S1 | agents-registry：agents.sync、智能体 CRUD 下发与别名唯一 | REQ-F-007 | Agent-Relay | sonnect | TASK-006 | 中 | todo |
| [TASK-027](tasks/TASK-027.md) | S1 | Web：智能体列表/表单（rjsf 按 configSchema）、聊天指令、历史页 | REQ-F-007/018/019 | Agent-App | sonnect | TASK-012, TASK-026 | 大 | todo |
| [TASK-028](tasks/TASK-028.md) | S1 | 审批与 held（中转侧）：approval.request→待审批→decision→回节点；超时拒绝；held 队列 | REQ-F-020 | Agent-Relay | opus | TASK-024, TASK-026 | 中 | todo |
| [TASK-029](tasks/TASK-029.md) | S1 | Web 审批卡与收件箱 | REQ-F-020 | Agent-App | sonnect | TASK-027, TASK-028 | 小 | todo |
| [TASK-030](tasks/TASK-030.md) | S1 | S1 E2E：多轮、/clear、/history、审批、held | REQ-F-018/019/020 | Agent-QA | sonnect | TASK-022, TASK-023, TASK-028, TASK-029 | 中 | todo |
| [TASK-041](tasks/TASK-041.md) | S2 | 微信 ClawBot 适配器：扫码登录、getupdates、sendmessage、context_token 持久化、额度预算器；真机验证 U-02/U-04 | REQ-F-009 | Agent-Channel | opus | TASK-042 | 大 | todo |
| [TASK-042](tasks/TASK-042.md) | S2 | channels 核心：ChannelAdapter 端口、注册表、capabilities、凭据加密、健康状态 | REQ-NF-008 | Agent-Relay | opus | TASK-010 | 中 | todo |
| [TASK-043](tasks/TASK-043.md) | S2 | recipients：授权、/bind 识别我的账号、未授权固定提示 | REQ-F-009/018 | Agent-Relay | sonnect | TASK-042 | 中 | todo |
| [TASK-044](tasks/TASK-044.md) | S2 | routing 内核：管理模式、/use 焦点、@别名、引用回复溯源、dry-run | REQ-F-016/017 | Agent-Relay | opus | TASK-043, TASK-024 | 大 | todo |
| [TASK-045](tasks/TASK-045.md) | S2 | delivery：outbox 工作者、令牌桶、重试表、死信、IR 渲染降级、过程消息合并（DEC-017） | REQ-NF-001/003 | Agent-Relay | opus | TASK-042 | 大 | todo |
| [TASK-046](tasks/TASK-046.md) | S2 | Web：渠道页（扫码 UI）、接收人页、绑定编辑器 + dry-run | REQ-F-009/016 | Agent-App | sonnect | TASK-027, TASK-044 | 大 | todo |
| [TASK-047](tasks/TASK-047.md) | S2 | IM 审批口令 Y{n}/N{n} 与无按钮渠道渲染 | REQ-F-020 | Agent-Relay | sonnect | TASK-028, TASK-044 | 小 | todo |
| [TASK-048](tasks/TASK-048.md) | S2 | S2 E2E：FakeChannel(微信方言) 管理模式全链路 | REQ-F-009/016/017 | Agent-QA | sonnect | TASK-041, TASK-045, TASK-046, TASK-047 | 中 | todo |
| [TASK-061](tasks/TASK-061.md) | S3 | projects：主/子项目树、深度≤3、overview 汇总 | REQ-F-004 | Agent-Relay | sonnect | TASK-005 | 中 | todo |
| [TASK-062](tasks/TASK-062.md) | S3 | 多设备：主设备、按设备路由、离线排队提示 | REQ-F-005 | Agent-Relay | sonnect | TASK-044 | 中 | todo |
| [TASK-063](tasks/TASK-063.md) | S3 | 节点多中转：relay-link 管理、命名空间隔离、各自凭据 | REQ-F-006 | Agent-Node | opus | TASK-023 | 大 | todo |
| [TASK-064](tasks/TASK-064.md) | S3 | workspace-guard：写租约、自动 git worktree、AGENT_BUSY_WRITE_LEASE | REQ-F-032 | Agent-Node | sonnect | TASK-021 | 中 | todo |
| [TASK-065](tasks/TASK-065.md) | S3 | Web：项目树、设备页、跨项目视图 | REQ-F-004/005 | Agent-App | sonnect | TASK-046, TASK-061, TASK-062 | 中 | todo |
| [TASK-066](tasks/TASK-066.md) | S3 | 本机控制台（node 构建目标）：中转连接、适配器探测、诊断页 | REQ-F-006 | Agent-App | sonnect | TASK-063 | 中 | todo |
| [TASK-067](tasks/TASK-067.md) | S3 | S3 集成/E2E：两中转隔离、两设备路由、写冲突 | REQ-F-005/006/032 | Agent-QA | sonnect | TASK-062, TASK-063, TASK-064, TASK-065, TASK-066 | 中 | todo |
| [TASK-081](tasks/TASK-081.md) | S4 | ACP 智能体组 A：Gemini CLI、Qwen Code、Kimi CLI、OpenCode（spec 实测+夹具） | REQ-F-007 | Agent-Node | sonnect | TASK-022 | 中 | todo |
| [TASK-082](tasks/TASK-082.md) | S4 | ACP 智能体组 B：Goose、Cline、Qoder CLI、GitHub Copilot CLI（spec 实测+夹具） | REQ-F-007 | Agent-Node | sonnect | TASK-022 | 中 | todo |
| [TASK-083](tasks/TASK-083.md) | S4 | OpenClaw（openclaw acp）接入与历史范围标注（G15） | REQ-F-007 | Agent-Node | sonnect | TASK-022 | 小 | todo |
| [TASK-084](tasks/TASK-084.md) | S4 | ZCode 实验适配器（zcode-acp-server / app-server 方言） | REQ-F-007 | Agent-Node | opus | TASK-022 | 中 | todo |
| [TASK-085](tasks/TASK-085.md) | S4 | Coze HTTP 适配器 | REQ-F-008 | Agent-Node | sonnect | TASK-021 | 中 | todo |
| [TASK-086](tasks/TASK-086.md) | S4 | Webhook 输入（127.0.0.1:5102，HMAC 签名） | REQ-F-008 | Agent-Node | sonnect | TASK-021 | 小 | todo |
| [TASK-087](tasks/TASK-087.md) | S4 | S4 输入冒烟矩阵与证据汇总 | REQ-F-007/008 | Agent-QA | haiku | TASK-081, TASK-082, TASK-083, TASK-084, TASK-085, TASK-086 | 小 | todo |
| [TASK-101](tasks/TASK-101.md) | S5 | 飞书/Lark 适配器：长连接、卡片、按钮、卡片更新、双域 | REQ-F-010 | Agent-Channel | sonnect | TASK-045 | 大 | todo |
| [TASK-102](tasks/TASK-102.md) | S5 | routing：通知模式（按发送人分会话）、团队模式（只到一个目标）、模式约束校验 | REQ-F-016/017 | Agent-Relay | opus | TASK-044 | 中 | todo |
| [TASK-103](tasks/TASK-103.md) | S5 | orchestration：汇总屏障（N 来源或超时、缺失标注） | REQ-F-021 | Agent-Relay | sonnect | TASK-102 | 中 | todo |
| [TASK-104](tasks/TASK-104.md) | S5 | Web：模式选择、屏障配置与状态 | REQ-F-016/021 | Agent-App | sonnect | TASK-065, TASK-103 | 中 | todo |
| [TASK-105](tasks/TASK-105.md) | S5 | S5 E2E：通知/团队/屏障（FakeChannel 飞书方言） | REQ-F-010/016/021 | Agent-QA | sonnect | TASK-008, TASK-101, TASK-103, TASK-104 | 中 | todo |
| [TASK-121](tasks/TASK-121.md) | S6 | QQ 官方机器人适配器 | REQ-F-011 | Agent-Channel | sonnect | TASK-045 | 中 | todo |
| [TASK-122](tasks/TASK-122.md) | S6 | 钉钉 Stream 适配器 | REQ-F-012 | Agent-Channel | sonnect | TASK-045 | 中 | todo |
| [TASK-123](tasks/TASK-123.md) | S6 | Telegram 适配器 | REQ-F-013 | Agent-Channel | sonnect | TASK-121 | 中 | todo |
| [TASK-124](tasks/TASK-124.md) | S6 | Discord 适配器 | REQ-F-014 | Agent-Channel | sonnect | TASK-122 | 中 | todo |
| [TASK-125](tasks/TASK-125.md) | S6 | notifications：p0–p3、渠道健康告警、备用渠道 | REQ-F-030 | Agent-Relay | sonnect | TASK-045 | 中 | todo |
| [TASK-126](tasks/TASK-126.md) | S6 | 渠道一致性测试套件（每个适配器跑同一套用例） | REQ-NF-008 | Agent-QA | sonnect | TASK-041, TASK-101, TASK-123, TASK-124, TASK-125 | 中 | todo |
| [TASK-141](tasks/TASK-141.md) | S7 | 成员、邀请、项目范围（projectScope） | REQ-F-003 | Agent-Relay | sonnect | TASK-061 | 中 | todo |
| [TASK-142](tasks/TASK-142.md) | S7 | permissions-filter：接收人×业务线×字段过滤与脱敏 | REQ-F-027 | Agent-Relay | opus | TASK-102 | 中 | todo |
| [TASK-143](tasks/TASK-143.md) | S7 | audit：出站/管理审计、投递明细、死信重放 | REQ-F-028 | Agent-Relay | sonnect | TASK-045 | 中 | todo |
| [TASK-144](tasks/TASK-144.md) | S7 | twin：采集（twin.capture）、节点存储、本机查看/修改/删除/导出 | REQ-F-029 | Agent-Node | sonnect | TASK-063 | 中 | todo |
| [TASK-145](tasks/TASK-145.md) | S7 | Web：成员、过滤规则、审计、投递；本机分身页 | REQ-F-003/027/028/029 | Agent-App | sonnect | TASK-104, TASK-141, TASK-142, TASK-143, TASK-144 | 大 | todo |
| [TASK-146](tasks/TASK-146.md) | S7 | 安全审查：越权矩阵测试、密钥扫描、提示注入标记 | REQ-NF-004 | Agent-QA | opus | TASK-145 | 中 | todo |
| [TASK-161](tasks/TASK-161.md) | S8 | models：钥匙串抽象（DPAPI/Keychain/libsecret/加密文件）、模型配置 CRUD、用量与费用 | REQ-F-026 | Agent-Node | opus | TASK-063 | 大 | todo |
| [TASK-162](tasks/TASK-162.md) | S8 | provider 薄客户端：OpenAI 兼容 + Anthropic（流式、工具、usage） | REQ-F-026 | Agent-Node | sonnect | TASK-161 | 中 | todo |
| [TASK-163](tasks/TASK-163.md) | S8 | supervisor 把关分级（规则 + LLM，超限降级）与 supervisor 路由模式 | REQ-F-022 | Agent-Node | opus | TASK-162 | 大 | todo |
| [TASK-164](tasks/TASK-164.md) | S8 | 总控随时对话（/boss）与任务分派 | REQ-F-023 | Agent-Node | opus | TASK-163 | 中 | todo |
| [TASK-165](tasks/TASK-165.md) | S8 | Web 本机：模型配置、用量看板、总控设置 | REQ-F-026 | Agent-App | sonnect | TASK-066, TASK-161 | 中 | todo |
| [TASK-166](tasks/TASK-166.md) | S8 | S8 E2E：把关四分级、超限降级、随时对话不打断 | REQ-F-022/023/026 | Agent-QA | sonnect | TASK-164, TASK-165 | 中 | todo |
| [TASK-181](tasks/TASK-181.md) | S9 | meetings 引擎：轮次、发言、纪要、决策、全员或超时 | REQ-F-024 | Agent-Node | opus | TASK-164 | 大 | todo |
| [TASK-182](tasks/TASK-182.md) | S9 | 导入任务清单（task-template 解析）与依赖顺序分派 | REQ-F-025 | Agent-Node | sonnect | TASK-164 | 中 | todo |
| [TASK-183](tasks/TASK-183.md) | S9 | Web：会议回放与任务看板 | REQ-F-024/025 | Agent-App | sonnect | TASK-165, TASK-181 | 中 | todo |
| [TASK-184](tasks/TASK-184.md) | S9 | S9 E2E：会议与导入分派 | REQ-F-024/025 | Agent-QA | sonnect | TASK-181, TASK-182, TASK-183 | 中 | todo |
| [TASK-201](tasks/TASK-201.md) | S10 | 急停（中转）：/stop all、EMERGENCY_STOPPED、恢复 | REQ-F-033 | Agent-Relay | sonnect | TASK-045 | 小 | todo |
| [TASK-202](tasks/TASK-202.md) | S10 | 急停（节点）：冻结所有会话与队列、恢复 | REQ-F-033 | Agent-Node | sonnect | TASK-201 | 小 | todo |
| [TASK-203](tasks/TASK-203.md) | S10 | Web Push 发送（VAPID）与订阅管理（中转） | REQ-F-015 | Agent-Relay | sonnect | TASK-125 | 小 | todo |
| [TASK-204](tasks/TASK-204.md) | S10 | PWA：manifest、service worker、订阅 UI | REQ-F-015 | Agent-App | sonnect | TASK-203 | 中 | todo |
| [TASK-205](tasks/TASK-205.md) | S10 | 配置导出/导入（中转，YAML，不含密钥，dry-run 差异） | REQ-F-034 | Agent-Relay | sonnect | TASK-143 | 中 | todo |
| [TASK-206](tasks/TASK-206.md) | S10 | 节点 doctor 与恢复密钥导出/导入 | REQ-F-034/035 | Agent-Node | sonnect | TASK-161 | 中 | todo |
| [TASK-207](tasks/TASK-207.md) | S10 | Bot 唯一消费者检测与告警 | REQ-F-031 | Agent-Relay | sonnect | TASK-125 | 小 | todo |
| [TASK-208](tasks/TASK-208.md) | S10 | 画像向导 P1/P2（Web） | REQ-F-031 | Agent-App | sonnect | TASK-204, TASK-207 | 中 | todo |
| [TASK-209](tasks/TASK-209.md) | S10 | 安装与部署：三平台节点安装/自启、中转 systemd + Caddy 脚本 | REQ-F-001 | Agent-Guard | sonnect | TASK-014 | 大 | todo |
| [TASK-210](tasks/TASK-210.md) | S10 | v1 验收回归与基线指标测量 | REQ-NF-001/002 | Agent-QA | opus | TASK-067, TASK-087, TASK-105, TASK-126, TASK-146, TASK-166, TASK-184, TASK-202, TASK-206, TASK-208, TASK-209 | 大 | todo |
| [TASK-211](tasks/TASK-211.md) | S10 | 文档同步：用户指南、project-map、task-index 状态 | REQ-C-007 | Agent-Docs | haiku | TASK-210 | 小 | todo |
