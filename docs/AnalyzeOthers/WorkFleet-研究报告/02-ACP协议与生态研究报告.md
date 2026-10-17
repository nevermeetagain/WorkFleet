# 02 ACP 协议与生态研究报告

> WorkFleet V0.0.2 ｜ 2026-10-17 ｜ 证据基线：agentclientprotocol.com 官方 v1 规范（实时抓取全文）+ GitHub 仓库 + zed.dev 文档

---

## 1. 协议定位与本质

**Agent Client Protocol（ACP）**是 Zed Industries 于 2025 年 8 月发起的开放协议，目标是把"代码编辑器（客户端）↔ AI coding agent（智能体）"之间的通讯标准化——业界普遍类比"AI 编程界的 LSP"【已确认】。

对 WorkFleet 的战略意义：**ACP 把"接入 N 个输入端"从 N 个私有适配问题收敛为 1 个协议客户端问题**。WorkFleet 的本质将是一个"超级 ACP 客户端"（同时充当多 IM 通道的桥）。

- 仓库：`agentclientprotocol/agent-client-protocol`（含 Rust 数据模型：wire 消息、request/response/notification、JSON-RPC envelope）【已确认】
- 官网/规范：agentclientprotocol.com（v1 Latest + v2 Draft 双轨）【已确认】
- 官方支持方：Zed Industries、JetBrains（官网页脚署名）【已确认】

## 2. v1 协议穿透（执行逻辑）

### 2.1 通信模型
- 基于 **JSON-RPC 2.0**：Methods（请求-响应对）+ Notifications（单向通知）【已确认】
- Agent 典型以 **客户端子进程**形态运行（"They typically run as subprocesses of the Client"）——v1 主传输为 **stdio**【已确认】
- 约定：JSON 对象键 camelCase；判别字段值 snake_case；文件路径必须绝对路径；行号 1-based【已确认】

### 2.2 完整消息流（官方 Overview 原文结构）

```
1) 初始化阶段
   Client → Agent : initialize        （版本与能力协商）
   Client → Agent : authenticate      （如 Agent 要求）
2) 会话建立（二选一）
   Client → Agent : session/new       （新建会话）
   Client → Agent : session/load      （恢复会话，需 loadSession 能力）
3) 提问回合（Prompt Turn）
   Client → Agent : session/prompt    （发送用户消息）
   Agent → Client : session/update *  （流式进度通知：消息块/工具调用/计划/命令更新/模式变化/通知/上下文压缩）
   Agent → Client : fs/* 或 session/request_permission   （按需读写文件、请求授权）
   Client → Agent : session/cancel    （可随时打断，无响应）
   回合结束：session/prompt 返回 result（含 stop reason）
```

### 2.3 方法全景表

| 方向 | 方法 | 类型 | 能力开关 | 对 WorkFleet 的用途 |
|-----|------|-----|---------|----------------------|
| C→A | `initialize` | 基线 | — | 探测 agent 名称/版本/能力（loadSession、promptCapabilities） |
| C→A | `authenticate` | 基线 | Agent 要求时 | 订阅凭证注入点 |
| C→A | `session/new` | 基线 | — | `/clear` 新开对话（E2）的实现 |
| C→A | `session/load` | 可选 | loadSession | 按 resume ID 恢复会话（E3 的写入口） |
| C→A | `session/prompt` | 基线 | — | 输出端 → agent 的指令主通道（F6） |
| C→A | `session/set_mode` | 可选 | — | 切换 agent 模式（plan/code 等） |
| C→A | `logout` | 可选 | auth.logout | 凭证轮换 |
| A→C | `session/request_permission` | 基线 | — | **IM 端审批按钮**（I2）的直接协议来源 |
| A→C | `fs/read_text_file` / `fs/write_text_file` | 可选 | fs 能力 | 总控模式下的跨 agent 文件协同（谨慎放权） |
| A→C | `terminal/create` / `output` / `release` / `wait_for_exit` / `kill` | 可选 | terminal 能力 | 受控终端执行（多 agent 共享一台设备时） |
| A→C | `elicitation/create` | 可选 | elicitation 能力 | agent 向用户要结构化输入 → IM 表单卡片 |
| — | `session/update`（通知） | 基线 | — | 流式转发到 IM（I4 的协议来源） |
| — | `session/cancel`（通知） | 基线 | — | IM 端"停止"按钮 |
| — | `elicitation/complete`（通知） | 可选 | — | 带外 URL 完成回调 |

### 2.4 会话列表与删除
规范目录含 Session List / Session Delete 页面【已确认目录结构】→ "两端对话记录查看（E3）"有原生协议支撑：客户端可枚举 agent 会话再按 sessionId 拉取渲染。（各 agent 对 session/list 的实现程度需实测【待确认】）

### 2.5 扩展机制（高拓展性的协议级保证）
1. `_meta` 字段携带自定义数据；
> 〔此处原引用旧内部项目代码或其实测数据，已于 V0.0.3 按用户要求移除〕
3. initialize 时能力广播。
→ WorkFleet 的"总控模式"私有信令（如会议邀请、任务分配回执）可直接走 `_` 方法而不破坏兼容性【设计建议】。

### 2.6 v2 草案动向
官网已挂 v2Draft 目录：Overview、Migrating from v1、Initialization、Authentication、Session Setup/Delete、**Prompt Lifecycle**、Content、Tool Calls、Elicitation、Cancellation、Agent Plan、Session Config Options、Slash Commands、Extensibility、Transports、Schema【已确认存在，内容未逐页抓取——标记部分确认】。
- 影响：Prompt Lifecycle 与 Transports 是 v1→v2 最可能的变化点（Goose 仓库讨论 ACP-over-HTTP 的 RFD 印证传输层在演进）。
- 对策：WorkFleet 的 ACP 层必须做**版本协商 + 传输抽象**（stdio now, HTTP later）。

### 2.7 官方生态件
- 官方库：**Kotlin、Java、Python、Rust、TypeScript** 五语言【已确认】→ 自研选型不受语言限制。
- **Test Compatibility Kit（TCK）**：agent 实现合规自测。
- **ACP Registry**：agent/扩展注册表（独立仓库 `nikomatsakis/agent-client-protocol-registry`）【部分确认，快照证据】。
- RFDs 流程：协议演进有公开提案机制。

## 3. 输入端支持矩阵（2026-10 实证）

| 输入端 | ACP 接入方式 | 证据 | 备注 |
|-------|-------------|------|------|
| Claude Code | `@zed-industries/claude-code-acp` 适配器（基于官方 Claude Agent SDK） | zed.dev 官方页 + yarnpkg 包页【已确认】 | 支持 @ 文件提及、图片粘贴；Claude Code 原生 auth 复用 |
| Codex CLI | `agentclientprotocol/codex-acp`：启动 Codex App Server 并翻译 ACP | GitHub 仓库快照【已确认】 | OpenAI 官方实验性 |
| Gemini CLI | 原生支持（zed.dev acp agent 列表） | zed.dev【已确认】 | |
| GitHub Copilot CLI | 原生支持 | zed.dev【已确认】 | |
| OpenCode | 原生支持 | 生态检索【部分确认】 | |
| Goose | 推进 ACP-over-HTTP（项目 issue/RFD） | 仓库讨论【部分确认】 | Block 出品 |
| Crush / Aider / Warp 等 | zed.dev ACP agent 列页收录 | zed.dev【已确认存在列表】 | 逐个能力需查表 |
| Pydantic AI（框架） | 提供 ACP agent 实现 | 生态检索【部分确认】 | Python 智能体框架 |
| Cursor / Zcode / Coze | **未发现官方 ACP 支持** | 检索无果【证据不足】 | 需走 CLI 降级（如 `cursor-agent` CLI、Coze HTTP API） |

**关键结论**：用户 6 个输入端示例中 3 个（ClaudeCode、Codex、OpenClaw 生态）已有 ACP 路径，2 个（Gemini、Copilot）原生支持；Cursor/Zcode/Coze 走 CLI/HTTP 降级。**必须实现"ACP / CLI / HTTP"三模适配**——这正是 WeClaw 已验证的架构（报告 03）。

## 4. 输出端通道生态（对偶侧）

| 输出端 | 接入方式 | 状态 |
|-------|---------|------|
| 微信（个人号） | **官方 ClawBot 插件**（2026-03 上线，iOS 微信 ≥8.0.70；OpenClaw 官方通道插件 `@tencent-weixin/openclaw-weixin`；协议为 iLink HTTP API） | 【已确认】 |
| 飞书 | `@openclaw/feishu` 官方插件：Bot 私信/群聊/流式卡片回复 + 飞书文档/wiki/云盘/多维表格工具 | 【已确认】（docs.openclaw.ai） |
| 钉钉 / QQ / 企微 / Discord / Telegram / Slack / WhatsApp / iMessage / Matrix / Signal / Teams | OpenClaw Gateway 统一通道体系 | 【已确认】（docs.openclaw.ai + 多源） |
| QQ（官方 Bot） | QQBot 官方平台 | 【部分确认】 |

**结论**：输出端不需要发明协议，全部走各平台官方 Bot API；OpenClaw 已把"通道抽象"做成开源事实标准，可复用其通道插件契约。

## 5. ACP vs MCP vs A2A（协议分工）

| 维度 | ACP | MCP | A2A |
|-----|-----|-----|-----|
| 解决 | 客户端 ↔ agent | agent ↔ 工具/上下文 | agent ↔ agent |
| 类比 | LSP | USB / 工具总线 | 组织间协作 |
| 传输 | stdio（v1），HTTP 草案中 | stdio / HTTP(SSE/Streamable) | HTTP + JSON-RPC / REST |
| 对 WorkFleet | **主协议**（输入端接入 + 总控对输入端的驱动） | 总控的 skill/工具配置（E8） | 总控模式未来的输入端互通选项（非必需） |
| 成熟度 | v1 稳定 + v2 草案 | 广泛落地 | 早期，生态待验证 |

**裁决**：不引入 A2A 依赖（避免早期锁定），总控→输入端仍用 ACP（总控即超级客户端），工具扩展用 MCP（复用现成 server 生态）。

## 6. 苏格拉底追问与钢人论证

**Q：ACP 会不会只是 Zed 的私货，两年内被弃？**
反方证据：JetBrains 联合署名官网；Anthropic（claude-code-acp）、OpenAI（codex-acp）、Google（Gemini CLI）、GitHub（Copilot CLI）、Block（Goose）全部跟进；五语言官方库 + TCK + Registry + RFD 治理。正方风险：v2 迁移成本；非 coding agent（如 Coze bot）不在此协议内。
裁决：ACP 已过"事实标准"门槛，风险主要在版本演进而非存亡【已确认多维证据】。

**Q：直接 stdio 子进程模型是否满足"总控必须本地运行"以外的远程场景？**
子进程模型天然本地（或同机容器）。若未来要"设备上的总控 + 云端 agent"，需等 ACP-over-HTTP（Goose RFD / v2 Transports）。当前设计：总控与输入端同机部署即可满足用户"运行在设备上"的表述【前提成立】。

**Q：session/update 的通知粒度对 IM 是否过细？**
过细——微信无法高频编辑消息。需要在 WorkFleet 中做**更新聚合器**（滑动窗口节流 + 终态合并），这是 WeClaw/WechatClawbot 都在做的工程决策【已确认同类项目均有此处理，如 markdown→纯文本、媒体上传合并】。

## 7. 对 WorkFleet 的架构指令（结论）

1. 核心身份 = **ACP Client（多路）** + IM Bridge（多通道）。
2. 输入端适配三模：ACP（首选，进程复用+会话保持）> CLI（`--resume` 降级）> HTTP（OpenAI 兼容 / Coze）——与 WeClaw 的实践完全一致【已确认可复用】。
3. 审批（`session/request_permission`）、打字机流（`session/update`）、会话恢复（`session/load`）是三大金矿能力，直接映射 E2/E3/I2/I4。
4. 扩展信令走 `_` 前缀方法；能力协商写进 agent 注册表。
5. 预留 v2：传输层接口化（stdio/HTTP 双实现位），协议版本白名单。
