# 04 · AstrBot 深度分析

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/AstrBotDevs/AstrBot |
| 分析版本 | `9441402872f65fffc35685b0ead5bd3337033cb2`（2026-10-16 00:01 CST） |
| 本地路径 | `/workspace/work/refs/AstrBot` |
| Stars / 语言 / 许可证 | 41,970 / Python（Dashboard 为 Vue，见 `dashboard/src/App.vue`）/ **AGPL-3.0**（`LICENSE:10`） |

---

## 1. 5W1H

- **What**：多平台 LLM 聊天机器人框架，包含消息管线（pipeline stages）、插件（star）、知识库、cron、人格（persona）、子 Agent 编排和 Web Dashboard。
- **Why**：作者的定位是"一站式聊天机器人"。它的**输出端（IM）覆盖与国内生态适配是所有候选中最好的**，但输入端是 LLM 和 API 型 Agent，而不是本地 Coding CLI。
- **Where/When**：服务端或桌面均可（有 `Dockerfile`、`k8s/`、`desktop_runtime.py`）。
- **Who**：平台适配器 `astrbot/core/platform/sources/`：aiocqhttp（OneBot QQ）、qqofficial、qqofficial_webhook、**weixin_oc（微信 iLink ClawBot）**、weixin_official_account、wecom、wecom_ai_bot、lark、dingtalk、discord、telegram、slack、kook、line、mattermost、misskey、satori、webchat。Agent Runner：coze、dify、dashscope、deerflow，以及自带的 tool-loop。
- **How**：平台事件 → EventBus → Pipeline（whitelist → rate_limit → content_safety → preprocess → process → result_decorate → respond，见 `astrbot/core/pipeline/`）→ Provider 或 AgentRunner。
- **What if**：如果新写一个 "AcpAgentRunner"（继承 `BaseAgentRunner`，`astrbot/core/agent/runners/base.py:22`），把 Claude Code 等 ACP Agent 当成 Runner，AstrBot 就能变成"输出端最全 + 知识库 + 主动消息"的网关。代价是 Python 性能，以及 AGPL 的传染性。

## 2. 代码证据

| 模块 | 证据 | 说明 |
|---|---|---|
| 微信 iLink | `astrbot/core/platform/sources/weixin_oc/weixin_oc_adapter.py:130`、`login_registration.py:6` `https://ilinkai.weixin.qq.com` | 已确认支持 ClawBot 协议 |
| 平台管理 | `astrbot/core/platform/manager.py:23` PlatformManager、`:119` load_platform、`:66` _run_platform | 每个平台实例各起一个 asyncio task，可以同时运行多个实例 |
| 主动消息（广播基础） | `astrbot/core/star/context.py:650-665` `send_message(session/umo, message_chain)` | 按 UMO（platform:type:session）主动推送，**可以循环遍历订阅者实现 1→N** |
| UMO 配置路由 | `astrbot/core/umop_config_router.py:6-60`：umop 模式（fnmatch 通配）→ 配置文件 ID | 不同会话或平台使用不同的配置（Provider、人格、插件），属于"多对多"的配置级路由 |
| 会话 | `astrbot/core/conversation_mgr.py:92` new_conversation、`:126` switch、`:139` delete、`:216` get_conversations | 支持 /new、切换、历史 |
| Cron | `astrbot/core/cron/manager.py:9-11` APScheduler（Cron / Date Trigger）；`:148` add_basic_job、`:175` add_active_job（唤醒主 Agent）；`:258-283` run_once 或 crontab+时区；`:34` 星期归一化 | 一次性 + 周期，没有节假日 |
| 知识库 | `astrbot/core/knowledge_base/`：parsers（pdf/epub/markitdown/url/text）、chunking、`kb_db_sqlite.py`、`retrieval/sparse_retriever.py`（BM25）、`retrieval/rank_fusion.py:26` RankFusion；`requirements.txt:15` faiss-cpu、`:49` rank-bm25 | **稠密 + 稀疏混合检索 + 融合排序** |
| 子 Agent | `astrbot/core/subagent_orchestrator.py:15` SubAgentOrchestrator（从配置加载子 Agent 并注册 handoff 工具） | 总控雏形，但对象是 LLM 子 Agent |
| Agent Runner | `astrbot/core/agent/runners/coze/coze_agent_runner.py:28` 等 | **Coze 输入已有现成实现** |
| ACP / Coding CLI | 在 `astrbot/core` 中 grep "acp / claude_code / Agent Client Protocol" **无命中** | 输入端缺失，`已确认` |
| 存储 | `astrbot/core/db`（SQLite）、`platform_message_history_mgr.py` | 有平台消息历史 |
| Dashboard | `dashboard/src`（Vue） | 平台、Provider、插件、KB、cron 都能在后台管理 |

## 3. 需求匹配

| 需求 | 匹配 | 得分 | 说明 |
|---|---|---|---|
| IN（15） | ○ | 4 | 只有 Coze、Dify 等 API Agent；Claude Code、Codex、Cursor、OpenClaw 都没有。**硬门槛不通过** |
| OUT（15） | ● | 15 | 6 个全覆盖，QQ 有两种方式 |
| M1（10） | ◐ | 4 | 多平台 → 同一 LLM，可行；但"多输入"不存在 |
| M2（10） | ● | 6 | `send_message(umo)` + cron active job，可以拼出订阅推送；没有现成的订阅者管理 |
| M3（10） | ◐ | 6 | UMO 配置路由 |
| UI（10） | ● | 9 | 成熟的 Dashboard |
| CR（5） | ● | 4 | |
| NS（5） | ● | 5 | |
| HI（5） | ◐ | 3 | 会话或平台历史；没有 resume ID 概念 |
| KB（5） | ● | 5 | 混合检索 |
| M4（5） | ◐ | 2 | SubAgentOrchestrator |
| LP（5） | ◐ | 1 | 人格管理；没有自动更新 loop（`证据不足`） |
| **合计** | | **≈64（原始分）；因输入端硬门槛不过，实际可用度明显更低** | |

### 3.1 场景

| 场景 | 结论 |
|---|---|
| 1 | ○ 没有 Coding CLI |
| 2 | ◐ 如果 3 个"分析工具"是 Coze 或 Dify 工作流，可以做到 |
| 3 | ○ |
| 4 | ● 最接近：cron active job + 遍历订阅者调用 `send_message`（需要写插件） |

## 4. 全维度

| 维度 | 评估 |
|---|---|
| 前端 | Vue Dashboard，功能全面 |
| 后端 | Python asyncio，管线阶段清晰 |
| 数据 | SQLite：会话、消息历史、cron、KB |
| 交互 | 指令系统、白名单、唤醒词 |
| 逻辑 | Pipeline 有序阶段（`stage_order.py`），每个阶段都可以插件化 |
| 组件 | Platform / Provider / AgentRunner / Star 插件 |
| 复用 | **KB 模块设计、Coze Runner、weixin_oc 与 qqofficial 适配器的协议细节**值得借鉴（AGPL 下宜"参考实现、重写代码"，不宜直接拷贝） |
| 拓展 | 插件市场（star） |
| 性能 | Python 单进程 asyncio；大规模扇出需要外部队列和限流 |
| 配置 | Dashboard + JSON 配置 + 多配置文件路由 |
| 知识库 | 有，见上 |
| 响应 | 支持流式；不同平台能力不同 |
| 存储 | SQLite + FAISS 索引文件 |
| 资源 | 中等 |
| 安全 | 白名单、内容安全阶段、`local_file_security.py` |
| 许可证 | **AGPL-3.0**：如果以网络服务方式提供修改版，必须开源。作为闭源产品底座风险高 |

## 5. 双向钢人

**判断："AstrBot 不适合做底座，但适合作为输出端、知识库、广播的参考"**
- 支持：输入端缺失是结构性问题（Runner 接口面向 API 型 Agent，没有进程和权限审批模型）；AGPL 对商业化不利。
- 反对：BaseAgentRunner 可扩展，写一个 ACP Runner 的工作量可控；输出端、KB、Dashboard 全都现成，算总账可能比在 cc-connect 上补 KB 和广播更省。
- 仍然成立的反对：如果用户产品**完全开源**且接受 Python，"AstrBot + 自写 AcpAgentRunner"是一条可行的第二路线。`待确认`（取决于用户的许可证策略）。
- 判断：在用户确认开源策略前，定位为参考来源。

## 6. 缺口与补齐

| 缺口 | 补齐 |
|---|---|
| Coding CLI / ACP 输入 | 新写 AcpAgentRunner，参考 acpx `src/acp/client.ts` 与 cc-connect `agent/acp/session.go` |
| 权限审批在 IM 内完成 | 参考 cc-connect `RespondPermission` 与卡片按钮 |
| 订阅者管理 | 插件：订阅表 + 退订指令 + 每平台限流 |
| 总控 | 参考 AionCore Team |
| resume ID 历史 | 在会话中记录 ACP sessionId |

## 7. 最终判断

- 原始分约 64，**输入端硬门槛不过**，所以不推荐作为底座。它是**场景 4（订阅推送）+ 知识库 + 国内 IM 适配**的最佳参考。
- 局限：没有运行；只做了源码静态阅读。
- 进入下一阶段：作为参考来源进入。
