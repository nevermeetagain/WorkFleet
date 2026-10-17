# 03 · AionUi + AionCore 深度分析

| 项 | 值 |
|---|---|
| 前端仓库 | https://github.com/iOfficeAI/AionUi · `c140550d04e44f3d6f8a9830b40ae56e4689a977`（2026-10-14 12:18 CST）· 33,572★ · Apache-2.0 · TS/Electron |
| 后端仓库 | https://github.com/iOfficeAI/AionCore · `503a87199eb978790ca77675b39c84b241535bf3`（2026-10-15 01:26 CST）· 122★ · Apache-2.0 · Rust |
| 本地路径 | `/workspace/work/refs/AionUi`（codeload 源码包，SHA 在 `.COMMIT_SHA`）、`/workspace/work/refs/AionCore`（git clone） |
| 关键发现 | AionUi 仓库只包含 Electron 前端与壳；**渠道、ACP、cron、Team 等业务逻辑全部在 AionCore**（`packages/desktop/src/process/backend/binaryResolver.ts:2,14` 解析 `aioncore` 二进制；`readme.md:713` 写明前后端分两个仓库）。只看 AionUi 仓库会误判 |

---

## 1. 5W1H

- **What**：桌面端（同时提供 WebUI 和 web-cli 包）的多 Agent 协作工作台。AionCore 用 Axum + Tokio + SQLite 提供 REST 和 WebSocket（`ARCHITECTURE.zh-CN.md`）。
- **Why**：作者的定位是"Cowork 式本地 AI 办公"。IM 渠道是"远程连接"附属功能（`docs/prds/remote/channels/README.md`）。
- **Where/When**：用户本机运行，属于设备端，**与"总控必须运行在设备上"的要求吻合**。
- **Who**：输入端是 ACP 后端，README 列出 Claude Code、Codex、Gemini、Hermes、Snow CLI、Aion CLI，并写明"other ACP backends with mcpCapabilities.stdio are auto-supported"（`readme.md:186-196`）。输出端插件位于 `crates/aionui-channel/src/plugins/{telegram,lark,dingtalk,weixin,slack,discord}`。
- **How**：ChannelPlugin trait → orchestrator → session（per user/chat）→ agent（ACP 或 aionrs）→ stream_relay 回推。
- **What if**：如果把 Team 模式与 Channel 打通（即 IM 消息先进入 Leader），就基本等于"总控模式"。但当前渠道只能选单个 Agent，这条链路**没有打通**（见 §2）。

## 2. 代码证据

| 模块 | 证据 | 说明 |
|---|---|---|
| ACP 依赖 | `crates/aionui-ai-agent/Cargo.toml:46` `agent-client-protocol = "2.0.0"`（启用 unstable_session_fork） | 官方 Rust ACP SDK |
| 渠道插件契约 | `crates/aionui-channel/src/plugin.rs:35-80` `ChannelPlugin{initialize,start,stop,send_message,edit_message,…}` | 编辑消息不支持时降级为发新消息（注释中以微信为例） |
| 平台枚举 | `crates/aionui-channel/src/types.rs:16-25` Telegram/Lark/Dingtalk/Weixin/Slack/Discord（Slack、Discord 注释为 "Reserved"，但 `plugins/discord/*.rs`、`plugins/slack/*.rs` 已有实现文件，`manager.rs:636-637` 也有默认名称） | **没有 QQ**；Discord 和 Slack 的实际可用性 `部分确认` |
| 插件运行时 | `crates/aionui-channel/src/manager.rs:32` `DashMap<ChannelRuntimeKey{owner_user_id, plugin_id}, Box<dyn ChannelPlugin>>` | 多用户、多插件实例 |
| 渠道 → Agent | `crates/aionui-channel/src/channel_settings.rs:95-168` `get_agent_config(user_id, platform)`，从 `client_preferences` 读取 `{"agent_type":"acp","backend":"claude"}` | **一个平台类型只对应一个 Agent** → 多对多受限 |
| 新会话 | `crates/aionui-channel/src/action.rs:263-272` `"session.new"` → `reset_session` | 等价于 /clear |
| 会话 | `crates/aionui-channel/src/session.rs:32` get_or_create、`:77` reset、`:177` bind_conversation | 渠道会话与桌面会话可以绑定，可在桌面查看历史 |
| 配对授权 | `crates/aionui-channel/src/pairing.rs`；PRD F-WEBUI-20 | 安全 |
| Cron | `crates/aionui-cron/src/types.rs:19-33` `CronSchedule{At, Every, Cron{expr,tz}}`；`executor.rs:611` `channel_chat_id: None` | 结果写入会话，**默认不推送 IM**（`部分确认`） |
| Team（总控雏形） | `crates/aionui-team/src/types.rs:13-17` `TeammateRole{Lead, Teammate}`；`mailbox.rs:14-204`（异步邮箱：write/read_unread/mark_read）；`task_board.rs:15-141`（create/update/list task）；`mcp/tools.rs:29` `authorize_tool(role, tool)` 按角色授权工具：team_spawn_agent / team_send_message / team_task_* / team_interrupt_agent（仅 Lead）/ team_clear_agent_context…；`scheduler/{wake,crash_recovery,agent_lifecycle}.rs` | **Leader 分派、并行 Teammate、邮箱、任务板、崩溃恢复**都有实现，最接近需求中的"职业经理人" |
| 数据库 | `Cargo.toml:108-109` sqlx(sqlite) + rusqlite；`crates/aionui-db` | 单机 SQLite |
| 认证 | `ARCHITECTURE.zh-CN.md`：JWT + CSRF 双提交 Cookie | WebUI 远程访问安全 |
| 前端 | `packages/desktop/src/renderer/pages/{cron,conversation/platforms/acp}`、`components/settings/.../channels`；`mobile/` | 渠道配置页、cron 页面完整 |

## 3. 需求匹配

| 需求 | 匹配 | 得分 | 说明 |
|---|---|---|---|
| IN（15） | ● | 13 | ACP 后端最开放；Cursor、OpenClaw 可作为 ACP 后端接入（理论上可行，`部分确认`）；Zcode `证据不足`；Coze 没有 |
| OUT（15） | ◐ | 11 | 飞书、钉钉、微信、Telegram 已确认，Discord `部分确认`，**没有 QQ** |
| M1（10） | ◐ | 4 | 每个平台一个 Agent；多工具汇聚只能经由 Team Leader |
| M2（10） | ○ | 2 | 没有广播 |
| M3（10） | ○ | 3 | 没有路由表 |
| UI（10） | ● | 9 | 桌面 + WebUI，配置体验最好 |
| CR（5） | ● | 4 | At / Every / Cron+tz，有可视化构建器（`docs/prds/cron/custom-schedule-builder.png`），没有节假日，不推送 IM |
| NS（5） | ● | 5 | session.new |
| HI（5） | ● | 4 | 桌面端会话历史 |
| KB（5） | ○ | 1 | 有 skills 和 assistants，**没有发现**向量知识库（`证据不足`） |
| M4（5） | ● | 4 | Team Leader 体系（缺"IM 入口 → Leader"和"重大事项上报闸门"） |
| LP（5） | ○ | 0.5 | |
| **合计** | | **≈60.5 → 计 58%** | |

### 3.1 场景

| 场景 | 结论 |
|---|---|
| 1 | ◐ 可以让 Leader 管理 6 个 Teammate，再把 Leader 绑定到微信渠道（需改造 channel → team 的绑定） |
| 2 | ○ 不能把一个渠道分发到两个群和部门 |
| 3 | ● 最匹配：Team 模式本身就是"主项目 + 子任务，由 Leader 分派"；但要求共享同一个 workspace（`readme.md:192`） |
| 4 | ○ |

## 4. 全维度

| 维度 | 评估 |
|---|---|
| 前端 | Electron + React（UnoCSS），带移动端；可复用度高，但与 AionCore API 强耦合 |
| 后端 | Rust 多 crate 分层，依赖严格向下（`ARCHITECTURE.zh-CN.md`），代码质量和可维护性好 |
| 数据 | SQLite：会话、消息、渠道设置、team 的 mailbox 和 task |
| 交互 | 卡片动作（`ActionButton`、`UnifiedAction`，见 `types.rs:402-474`）、配对码 |
| 逻辑 | Team 调度包含 wake、dedup、crash_recovery |
| 组件 | ChannelPlugin trait、Team MCP Server（以 MCP 工具形式向各 Agent 暴露团队能力，这个设计很巧妙） |
| 复用 | **Team MCP Server + Mailbox + TaskBoard 的设计可直接借鉴来实现总控**；渠道插件（Rust）可复用到 Rust 版网关 |
| 拓展 | 扩展系统（`examples/ext-feishu`、`ext-wecom-bot`、`acp-adapter-extension`） |
| 性能 | Rust + Tokio，性能好；Agent 进程为主要开销 |
| 配置 | GUI 配置存入 DB（client_preferences），没有声明式配置文件 → 不便于 GitOps |
| 知识库 | 无（证据不足） |
| 响应 | stream_relay 流式回推 |
| 存储 | SQLite 单机 |
| 资源 | Electron 桌面常驻，资源占用偏高；web-cli 可以无头运行（`packages/web-cli`） |
| 安全 | JWT + CSRF、配对授权、每个 Agent 独立的权限确认 |
| 许可证 | Apache-2.0（两个仓库都是），对商用友好 |

## 5. 双向钢人

**判断："AionCore Team 可作为总控模式的参考实现"**
- 支持：Lead / Teammate 角色、仅 Lead 可调用的工具权限（`mcp/tools.rs:29`、测试 `:158-159`）、异步 mailbox（满足"随时对话不打断任务"的必要条件）、任务板、崩溃恢复，全部已实现，且基于 ACP。
- 反对：(1) Team 目前在桌面会话中使用，没有接到 IM；(2) 所有 Agent 共享同一个 workspace，不适合"多项目"；(3) 没有"非必要直接回复、重大事项上报"的分级策略；(4) AionCore 只有 122★，社区小，接口可能频繁变化。
- 判断：**借鉴设计，不依赖其代码**。如果 WorkFleet 选 Rust 技术栈，可以考虑直接复用 crate（Apache-2.0）。

## 6. 缺口与补齐

| 缺口 | 补齐 |
|---|---|
| QQ | 移植 cc-connect `platform/qqbot` 或 AstrBot `qqofficial` |
| 渠道多 Agent / 路由 | 自建路由层（参考 OpenClaw bindings） |
| 广播 | 自建订阅扇出 |
| cron → IM | 在 executor 中填写 channel_chat_id 并调用 ChannelManager.send_message |
| KB | AstrBot KB / hindsight |
| 上报闸门 | 在 Leader 的 system prompt 里加一个 `escalate_to_human` 工具，由该工具调用渠道推送 |

## 7. 最终判断

- 加权约 **58%**。**总控（M4）方向的最佳参考**，路由和广播很弱。
- 局限：没有运行 AionUi / AionCore；Discord 实际可用性 `部分确认`；KB `证据不足`。
- 下一步：精读 `crates/aionui-team/src/scheduler/*` 与 `work_coordinator/*`，提炼总控状态机。
- 进入下一阶段：允许，以"总控设计参考"的身份进入。
