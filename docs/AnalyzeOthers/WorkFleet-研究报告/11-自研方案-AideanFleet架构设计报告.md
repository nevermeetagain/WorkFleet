# 11 自研方案报告：AideanFleet 总体架构设计（V0.0.2 预研稿）

> 定位：多对多 ACP 路由中枢 ｜ 目标：高性能、高拓展性 ｜ 依据：报告 01 需求 + 03-10 生态结论

---

## 1. 总体架构

```
                        ┌────────────────────────────────────────────────┐
                        │              管理控制台 (Web, :3000)             │
                        │  账号/绑定 · 路由规则 · 模式 · 任务 · 会话 · 审计   │
                        └───────────────┬────────────────────────────────┘
                                        │ REST/gRPC (内网)
┌──────────────┐  事件   ┌──────────────▼─────────────────────────────────┐
│ 微信 ClawBot │◄──────►│                AideanFleet Core                  │
│ (iLink 官方)  │        │  ┌──────────┐ ┌──────────┐ ┌───────────────┐   │
├──────────────┤        │  │ Channel  │ │  Router  │ │  Session Map  │   │
│ 飞书(官方插件) │◄──────►│  │ Adapters │►│  Engine  │◄│ (IM↔ACP 会话) │   │
├──────────────┤        │  │ (:3333)  │ │ 三模式+规则│ └───────────────┘   │
│ QQ 机器人     │◄──────►│  └──────────┘ └────┬─────┘ ┌───────────────┐   │
├──────────────┤        │                      │       │  Scheduler     │   │
│ 钉钉(Stream)  │◄──────►│  ┌──────────┐ ┌─────▼─────┐│ (cron 语义)    │   │
├──────────────┤        │  │Approval/ │ │  Agent    │└───────────────┘   │
│ Discord      │◄──────►│  │Formatter │ │  Pool     │──► ACP 子进程×N     │
├──────────────┤        │  │(流式聚合) │ │(适配三模)  │   Claude Code      │
│ Telegram     │◄──────►│  └──────────┘ └─────┬─────┘   Codex/OpenCode…  │
└──────────────┘        │                      │       CLI 模(--resume)   │
                        │  ┌───────────────────▼───────────────────┐     │
                        │  │       总控 Orchestrator (可选装配)      │     │
                        │  │  会议总线 · 把关归纳 · 任务分派 · 旁路对话 │     │
                        │  └───────────────────┬───────────────────┘     │
                        └──────────────────────┼─────────────────────────┘
                                               │ REST/MCP
                                    ┌──────────▼──────────┐
                                    │  Hindsight 记忆服务   │ (:8888/:9999)
                                    │  (bank/知识页/身份loop)│
                                    └─────────────────────┘
```

分层原则：**Channel（通道）与 Agent（输入端）双适配 + 中间路由内核**；总控与记忆为"可选装配"（不装=纯路由器，装=总控形态）。

## 2. 技术选型（双向钢人论证后裁决）

| 候选 | 优势 | 反对（钢人） | 裁决 |
|------|------|------------|------|
| **Go** | 单二进制分发（WeClaw 同栈同形态）；goroutine 天然适配"多 ACP 子进程 + 多通道事件流"；生态可直借 WeClaw 工程细节；GC 延迟对本场景（毫秒级转发）无感 | 极致性能不如 Rust；泛型表达力一般 | **主选（推荐）** |
| Rust | 性能与内存上限最高；类型系统防并发错误 | 开发速度慢 2-3 倍；团队上手成本；生态中 ACP 库（官方有 Rust 实现，可复用 wire 模型）但 IM SDK 需自写更多 | 备选（若核心团队 Rust 熟练且目标是十万级并发） |
| Node/TS | OpenClaw/Paperclip 同栈，插件生态好 | 单线程网关上限；子进程管理繁琐；高性能目标下不利 | 仅控制台前端用 TS（React） |
| Python | LangBot/AstrBot/Hindsight 同栈，AI 生态最富 | 并发与分发性能弱；打包分发差 | 不做内核；Hindsight 服务本身是 Python（外挂不受限） |

**裁决**：**Go 内核 + React(TS) 控制台 + Python 侧 Hindsight 外挂**。理由链：WeClaw（Go）已验证"ACP 三模 + 微信官方通道"的关键路径 → 移植成本最低；性能满足（目标 P95<2s 转发、单机 100 并发会话远低于 Go 上限）；分发形态最优（单二进制 + SQLite 零依赖起步）【设计裁决，依据报告 03/09】。

## 3. 数据模型（SQLite 起步，可平移 PostgreSQL）

```sql
-- 通道与账号
channels(id, type[wechat_clawbot|feishu|qq|dingtalk|discord|telegram],
         name, credential_enc, status, quota_json)
bindings(id, channel_id, external_user_id, display_name,        -- 扫码绑定结果
         persona_json, tags[], created_at, last_seen_at)
-- 输入端
agents(id, name, mode[acp|cli|http], command, args, env_json,
       capabilities_json, cwd_default, health_status)
-- 路由与模式
routes(id, mode[management|notify|team|master], priority,
       matcher_json,   -- {sender, channel, project, tag, time, keyword...}
       targets_json,   -- agent_ids[] 或 bindings[]/groups[]
       opts_json)      -- {dedup, throttle, summarize...}
-- 会话映射（E2/E3/I1 的核心表）
sessions(id, agent_id, acp_session_id, acp_resume_token,        -- session/load 依据
         channel_id, im_chat_id, project_key, title,
         status[active|paused|archived], created_at, updated_at)
messages(id, session_id, direction[in|out], role, content, media_ref,
         token_usage, created_at)                                -- 会话记录查询
-- 定时任务（E1）
tasks(id, name, cron_expr, calendar[once|daily|weekly|monthly|workday|holiday],
      next_fire_at, catchup_policy[skip|queue|run_once],        -- Paperclip 追赶语义
      payload_json, targets_json, enabled, last_result)
-- 总控（E6-E9）
meetings(id, topic, status[collect|synthesize|assign|execute|report], turns_json)
assignments(id, meeting_id, agent_id, task_desc, status, artifacts_json)
identities(id, scope[agent|project|user], bank_id, seven_dim_json, -- 分身数据-loop
           version, updated_at)
-- 治理
approvals(id, session_id, acp_request_ref, question, options_json,
          decided_by, decision, decided_at)
audit_log(id, actor, action, detail_json, created_at)
```

## 4. 三模式路由引擎（核心执行逻辑）

```text
onMessage(ch, user, text):
  cmd = parseCommand(text)               # /clear /new /status /history /ask ...
  if cmd: dispatchCommand(cmd); return
  routes = matchRoutes(mode, ch, user, text)      # priority 排序
  for r in routes:
    case r.mode:
      management:                       # N:1 汇聚
        sess = getOrCreateSession(agent_of(r), user)   # 复用 ACP 子进程
        acpPrompt(sess, text)            # 流式 session/update → 聚合器 → IM
      notify:                            # 1:N 扇出
        fanout(r.targets, render(text))  # 每通道独立限流队列
      team:                              # M:N 分组
        group = resolveGroup(r, ch, user) # 产品线 → agent 集合 × 通道集合
        for a in group.agents: acpPrompt(getOrCreateSession(a, group.key), text)
        aggregateReplies(group, window)  # 多 agent 回复合并/分栏下发
      master:                            # 总控模式（报告 12）
        orchestrator.handle(text, ctx)
```

关键机制：
- **会话粘性**：`(agent_id, im_chat_id, project_key)` → 唯一 ACP 会话；`/new` 重新 `session/new`；崩溃恢复用 `acp_resume_token` 走 `session/load`【依据 ACP 规范，报告 02】。
- **流式聚合器**：`session/update` 通知按 300-800ms 滑动窗口合并（IM 消息编辑 API 有限：微信 iLink 不支持编辑 → 改为"节流追加"策略；飞书卡片支持流式更新，可对齐 OpenClaw 飞书插件的流式卡片）【依据报告 03/09】。
- **审批桥**：`session/request_permission` → 生成 approvals 记录 → IM 按钮消息（飞书/Telegram/Discord 原生支持；微信降级为回复"同意/拒绝"文本）→ 回写 ACP 响应【依据 ACP 规范 + Omnara 形态】。

## 5. 定时任务语义（E1）

| 日历语义 | 触发逻辑 | 数据 |
|---------|---------|------|
| once | 指定时刻单次 | next_fire_at |
| daily/weekly/monthly | 标准 cron | cron_expr |
| workday（工作日） | cron ∧ 非节假日 | 节假日表（中国法定+调休，需年度更新） |
| holiday（休息日） | cron ∧ 节假日 | 同上 |
| catchup | 错过触发（停机/限流）后 | skip / queue / run_once（Paperclip Routines 语义） |

## 6. 性能设计（"高性能"目标落地）

1. **进程模型**：每 agent 1 个 ACP 子进程常驻（复用会话，WeClaw 验证的模式）；池上限 + LRU 淘汰（空闲 >30min 的会话进程优雅退出，保留 resume token）。
2. **消息面**：有界 channel + 背压丢弃策略（保序不保活时告警）；每通道令牌桶（对齐各 IM 平台频控：飞书/钉钉 QPS、微信 iLink 未知配额【待确认：压测】）。
3. **扇出**：通知模式 1:N 用 goroutine 池 + 每目标独立重试（指数退避 ×3）+ 死信落库。
4. **零依赖起步**：SQLite（WAL）+ 内嵌静态资源单二进制；上量后平移 PG + Redis Stream（接口已抽象）。
5. **流式**：ACP update → 聚合器 → 通道异步发送全链路无阻塞 IO；首块目标 <300ms。

## 7. 拓展设计（"高拓展性"目标落地）

1. **Channel Adapter 接口**（Go interface）：`Connect/OnEvent/Send/SendCard/RequestApproval`；新通道=新插件（进程内编译 or 进程外 sidecar，兼容 OpenClaw 插件契约的字段子集，便于直接抄官方飞书/钉钉插件参数）【依据报告 09】。
2. **Agent Adapter 接口**：`ACP | CLI | HTTP` 三实现（对齐 WeClaw）；`capabilities_json` 存能力协商结果。
3. **规则插件**：matcher 支持内置 DSL（JSON）+ 外挂表达式（可选 expr-lang）。
4. **配置热加载**：路由/任务/账号变更经控制台 → 事件总线 → 内核热生效（不重启）。
5. **MCP 服务**：内核自带 MCP server（会话查询/发送/路由控制），供 Claude/Cursor 等反控（WechatClawbot 的 MCP 方向 + Hindsight 的 MCP 形态）【依据报告 03/07】。

## 8. 端口与部署约定（回应分析模板中的端口问题）

| 端口 | 用途 | 说明 |
|-----|------|------|
| **3000** | 管理控制台 + 管理 API | **建议值**：沿用团队既有约定（Aidean=3000）；全部可配置，冲突时自动+1 并告警 |
| **3333** | 通道回调/Bot 服务（Webhook/Stream） | **建议值**：沿用既有约定（AideanBot=3333）；同上 |
| 8888/9999 | Hindsight API/UI | 上游默认，不改 |

> 说明：本报告为预研，不涉及对任何现有服务的端口改造；上述为**新系统默认值建议**，是否沿用 3000/3333 由用户拍板【待确认 Q5】。

## 9. 安全设计

- 凭证加密存储（age/AES-GCM，主密钥来自环境或 keychain）；控制台默认仅监听 127.0.0.1，远程需 token + TLS；
- 白名单：bindings 表 + per-route 允许名单；未绑定用户触发入会引导而非忽略；
- 审批默认开启（ACP request_permission 不允许自动全通过；WeClaw 的 `--dangerously-skip-permissions` 仅作为显式 opt-in）；
- 审计：audit_log 全量路由/审批/任务留痕。

## 10. 里程碑路线图

| 阶段 | 周期 | 交付 | 验收（对齐报告 01 §3.5） |
|-----|------|------|----------------------|
| M0 PoC | 1-2 周 | WeClaw 直用 + 飞书/Telegram 双通道原型；验证 ACP 三 agent 并发 | 用户痛点（扫码打架）消失 |
| M1 MVP | 4-6 周 | Go 内核：管理/通知模式 + 会话映射 + /clear + 控制台 | 验收 1/2/5/6 |
| M2 团队模式 | +3 周 | M:N 分组、聚合下发、多账号多设备 | 验收 1（三模式全量） |
| M3 拓展功能 | +3 周 | E1 全语义定时、E3 会话查询 UI、E4/E5 Hindsight 接入 | 验收 3 |
| M4 总控模式 | +4-6 周 | 会议总线 + 把关归纳 + 旁路对话 + skill 配置 | 报告 12 验收 |
| M5 加固 | 持续 | 背压/限流/死信/审计/多节点 | 验收 4 |

## 11. 风险表

| 风险 | 概率 | 影响 | 缓解 |
|-----|-----|------|-----|
| ACP v2 破坏性变更 | 中 | 中 | 版本协商 + 适配层；关注 RFD |
| 微信 iLink 配额/政策收紧 | 中 | 高 | 企微/飞书备份通道；配额压测前置（M0） |
| WeClaw/OpenClaw 插件许可不明 | 中 | 中 | M0 前核验 license；仅借鉴协议参数则风险低 |
| 总控 token 成本失控 | 高 | 中 | 预算硬停（Paperclip 语义）+ 小模型规划（pentagi 经验） |
| 多 agent 回复风暴（团队模式） | 中 | 中 | 窗口聚合 + 单 agent 限速 + 静默期 |
| 单人维护断档 | 高 | 高 | 生态拼装最小化自研面；文档与测试资产化 |

## 12. 苏格拉底追问与钢人论证（方案级）

**Q：为什么不直接 fork WeClaw 加通道？**
支持：省 M1 一半工作量。
反对：WeClaw 的微信实现与全局耦合（账号模型、命令路由、媒体管道），加"多通道路由内核"等于重写其消息主干；且 license 未确认【待确认】。裁决：**参照移植（拷贝工程模式与 iLink 细节），不做 fork**——保留升级自由。
**Q：SQLite 撑得住吗？**
消息吞吐量级（个人/小团队：<100 msg/s）远低于 SQLite WAL 上限；触发瓶颈的信号明确（写锁等待）再平移 PG，接口已预留。
**Q：总控为什么不做进内核？**
可选装配（独立模块 + 事件总线接入）保证"纯路由"形态的轻量与稳定；总控的 LLM 依赖（模型/成本/不确定性）不污染核心路由的确定性【架构裁决】。
