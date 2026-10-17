# 01 · WechatClawbot 深度分析（AideanFleet V0.0.1 参考项目）

> 分析对象：https://github.com/CodingHeader/WechatClawbot
> 分析版本：`main` @ `4ec3bbe8b7b35ff308715b03dfa4e93ecbaab6b5`（提交时间 2026-09-04 09:49:30 +0800，“chore: sync local state before publishing to GitHub”）
> 本地路径：`/workspace/work/refs/WechatClawbot`（`git clone --depth 1`）
> 分析日期：2026-10-16（Asia/Shanghai）
> 证据标签：`已确认`（读代码/跑命令证实）· `部分确认` · `证据不足` · `存在缺陷`

---

## 0. 一句话结论

WechatClawbot 是一个 **“微信 iLink 协议接入层 + 单 LLM 问答 + 主动通知”** 的 Python 小型服务（源码约 2,680 行），**不是 ACP 网关**：它没有任何“编码智能体/CLI 输入端”适配，也没有多 IM 输出端。它对 AideanFleet 的真正价值在于 **微信 ClawBot（iLink）通道适配器的可复用实现**（扫码登录状态机、长轮询、context_token 回发、同用户重复扫码作废逻辑），以及一个**“iLink 同一微信用户只路由到最新授权 bot”** 的关键平台事实——这恰好是用户“反复扫码绑定/解绑”痛点的根因，也证明 AideanFleet 必须在 **一个 ClawBot 绑定上复用多个输入端**。

- 需求匹配度（加权估算）：**约 15%**（见 §2 打分表）
- 复用结论：**协议层（wechat/）可直接借鉴或移植；会话/通知/调度层仅可参考思路；整体不宜作为底座。**
- 许可证：**仓库无 LICENSE 文件**（`ls LICENSE*` 无结果；GitHub API `license: null`），仅 `mcp-npm/package.json` 声明 MIT。**直接拷贝代码存在法律风险 → `证据不足`/需向作者确认授权**。

---

## 1. 仓库事实（What）

### 1.1 社区与活跃度（GitHub API，2026-10-16 查询）

| 项 | 值 | 标签 |
|---|---|---|
| Stars / Forks / Open issues | 0 / 0 / 0 | 已确认 |
| 创建时间 / 最近 push | 2026-09-04 09:40 / 2026-09-04 09:54（+08:00） | 已确认 |
| 提交历史 | 最近 5 条集中在 2026-07-31 ~ 2026-09-04；首次公开即“sync local state” | 已确认 |
| 主语言 | Python 3.10+（另含一个 Node MCP 包） | 已确认 |
| 许可证 | 根目录无 LICENSE；`mcp-npm/package.json:"license": "MIT"`，且其 `repository.url` 指向 `CodingHeader/coze-clawbot`（与本仓库名不一致） | 已确认（不一致处） |
| 描述 | “微信ClawBot拓展版” | 已确认 |

结论：**个人项目、零社区、单次发布**，维护连续性无法保证。

### 1.2 目录与规模

```
src/wechat_clawbot/
├── __main__.py      70   入口：serve | login
├── app.py          267   ClawBotApp：多账号长轮询编排
├── config.py        72   pydantic-settings（.env）
├── db.py           376   SQLite 四表
├── models.py       150   Pydantic 模型（iLink 消息结构）
├── wechat/{protocol 33, auth 158, client 78}   iLink 协议层
├── session/{router 104, store 80}              会话路由/存储/摘要
├── ai/{chat 131, coze 192}                     litellm / Coze 两种 AI 后端
├── notify/notifier.py 112                      主动通知 + APScheduler cron
├── commands/router.py 19                       /help /clear /status
├── api/routes.py   580   FastAPI + 内嵌 HTML 控制台
└── mcp/server.py   111   Python MCP（stdio）
mcp-npm/index.js    126   Node MCP（stdio，调 HTTP API）
tests/ 6 个测试文件；scripts/smoke.py；Dockerfile
```
全部文件 52 个，Python+JS 源码合计 2,680 行（`wc -l` 已确认）。

### 1.3 运行验证（命令证据）

```
$ /tmp/wcv/bin/python -m pytest -q
28 passed, 1 warning in 9.16s          ← 单测全部通过（respx mock iLink，未连真实微信）
```
自写复现脚本 `/tmp/t_media.py`（向 SessionRouter 投递一条 type=2 图片消息）：
```
ERR NameError name 'ChatRole' is not defined   ← 存在缺陷（见 §6.1）
```
真机扫码、真实 iLink 收发 **未验证**（需要真实微信账号）→ `证据不足`。

---

## 2. 需求匹配度（逐条映射）

### 2.1 核心需求

| # | 用户需求 | 结论 | 证据 / 说明 |
|---|---|---|---|
| R1 | 多对多 ACP 工具（输入=CLI/智能体，输出=IM） | **不支持** | 输入侧只有 `AIChat`（`ai/chat.py:20-131`）：litellm OpenAI 兼容 API 或 Coze Bot；**无** ACP（Agent Client Protocol）客户端、无 Claude Code/Codex/Cursor 进程适配。输出侧只有微信 iLink。 |
| R2 | 后台配置管理 | **部分** | 只有 `.env`（`config.py:12-65`）+ 内嵌 HTML 控制台（`api/routes.py:57` `_index_page_html`）做扫码/用户列表/发消息；无“输入↔输出路由”配置。 |
| R3 | 管理模式（多输入→1 输出） | **不支持** | 无“多个输入端”概念；所有消息进入同一 `AIChat`。 |
| R3' | 管理模式下输出端也能发消息 | **部分** | 微信→AI 的问答路径存在（`app.py:199-267 _poll_loop→_dispatch→SessionRouter.handle→AIChat.chat→client.send_message`），但目标是 LLM，不是编码智能体。 |
| R4 | 通知模式（1 输入→多输出，群发） | **部分** | `POST /notify`（`api/routes.py:534`）和 MCP `notify_user` 只能**单个** `(account_id, wechat_user_id)`；无群发/订阅列表；README“边界”明确“不做群发营销”。 |
| R4' | 通知模式下接收不同用户消息 | **支持（仅微信）** | 会话按 `(account_id, wechat_user_id)` 隔离（`db.py:72` sessions 主键）。 |
| R5 | 团队模式（多对多、多 IM：微信/QQ/飞书） | **不支持** | 只有微信一个通道；无通道抽象接口（`WeChatClient` 被 `app.py`、`notifier.py` 直接引用，未经接口）。 |

### 2.2 扩展需求

| # | 需求 | 结论 | 证据 |
|---|---|---|---|
| E1 | 定时任务（一次/工作日/休息日/每日/每周/每月） | **部分** | `NotifyScheduler`（`notify/notifier.py:68-112`）用 APScheduler `CronTrigger.from_crontab` → 支持每日/每周/每月/工作日(`1-5`)；**不支持“只运行一次”**、**不支持中国法定节假日/调休**；任务来自 `.env NOTIFY_JOBS` 静态 JSON（`app.py:88-100`），**无 CRUD、不持久化、重启后 `delivered_count` 归零**；内容只能是固定文本，不能触发智能体生成内容。 |
| E2 | `/clear` 新开对话 | **部分** | `commands/router.py:12-14` 清空**本地** LLM 历史（`db.clear_session` 置 `history_json='[]'`）。对 ClaudeCode 等的 session 重置**不存在**（无此输入端）。Coze 路径：`ai/coze.py chat()` 未传 `conversation_id`（`ai/chat.py:_coze_complete` 只传 user_id/system_prompt），推断每次都是新 Coze 会话 → `/clear` 对 Coze 无意义（`部分确认`，未连真实 Coze）。 |
| E3 | 两端对话记录查看（按 session/resume ID） | **部分** | `GET /sessions/{account_id}/{user_id}`（`api/routes.py:541`）、`GET /users`（L564）。历史是 JSON 数组整存（`history_json`），**超过 `MAX_HISTORY` 会被摘要并截断**（`session/store.py:58-80`），原文丢失；无 session/resume ID 维度；默认 30 天自动清除（`db.py purge_expired_data`）。 |
| E4 | 身份数据采集优化/分身自动更新 loop | **不支持** | 仅有历史溢出摘要（`SUMMARY_PROMPT`，`ai/chat.py:17`），非画像/人格更新。 |
| E5 | 知识库（项目设计、目录图谱、上下文记忆） | **不支持** | 无向量库/文档存储；仅会话摘要字段 `summary`。 |
| E6 | 总控模式（设备上的“职业经理人”，开会、分派、把关、汇报） | **不支持** | 无多智能体编排、无审批/升级逻辑。 |
| E7 | 总控自定义模型、skill 配置 | **部分（仅模型）** | `runtime_config` 可按会话覆盖 `model`/`system_prompt`（`ai/chat.py:104-106`），但**没有任何写入入口**（无 API/指令调用 `update_runtime_config`，grep 仅定义处 `session/store.py:50`）→ 实际不可用。无 skill。 |
| E8 | 与总控随时对话、不影响任务执行 | **不支持** | `_poll_loop` 对每条消息 `await self._dispatch(...)`（`app.py:228-229`）**串行**处理：AI 调用期间该账号停止拉取新消息（单账号内阻塞）。 |

### 2.3 四个场景

| 场景 | 结论 | 说明 |
|---|---|---|
| S1 三项目 6 个开发工具 → 微信 ClawBot 统一接收 | **部分（仅出口一半）** | 开发工具可通过 **MCP `notify_user`**（`mcp-npm/index.js` / `mcp/server.py:51`）主动推送到微信；但**微信回复无法路由回某个具体工具/项目**，没有“来源工具”标签与反向通道。 |
| S2 飞书：3 个分析输入 → 数据部门 + 老板两个输出 | **不支持** | 无飞书；无多输出扇出。 |
| S3 主项目+子项目、总控模式统一开发 | **不支持** | 无编排。 |
| S4 大量用户订阅，每天 9 点推送 AI 资讯 | **部分** | cron 可以 `0 9 * * *`，但每个 job 只发给**一个用户**、文本固定；无订阅表、无批量限速、无“生成当日内容”的智能体调用；iLink 主动消息是否需要 `context_token`/有频控 → `证据不足`（代码在主动通知时 `send_message` 不传 context_token，`notifier.py:49`）。 |

### 2.4 加权匹配估算

| 维度（权重） | 得分 | 加权 |
|---|---|---|
| 多输入端（编码智能体/ACP）接入 25% | 0 | 0 |
| 多输出端 IM 接入 20% | 20（仅微信，且实现质量较好） | 4 |
| 三种路由模式 20% | 10 | 2 |
| 后台配置 10% | 30 | 3 |
| 定时任务 5% | 50 | 2.5 |
| /clear 与会话记录 5% | 40 | 2 |
| 总控模式 10% | 0 | 0 |
| 知识库/画像 loop 5% | 5 | 0.25 |
| **合计** | | **≈ 14%（取整约 15%）** |

> 权重为本报告分析者对需求文本的主观拆分，非用户给定 → 结论性质为**估算**。

---

## 3. 全维度分析

### 3.1 前端
- 无独立前端工程。`api/routes.py:57-285` 用 Python f-string 内嵌一张 HTML（扫码、账号/用户列表、聊天历史、发送框），`loadAccounts()/loadUsers()` 原生 JS（L283-284）。
- **安全问题**：`/` 在中间件白名单（`api/routes.py:331` `if path in ("/", "/health")`），页面把 `AUTH_TOKEN` 明文写入 HTML（L131 `<pre>{token}</pre>`、L135 `const AUTH_TOKEN = ...`）。仅当 `HOST=127.0.0.1`（默认）时可接受；若改为 `0.0.0.0`/Docker `EXPOSE 8088` 对外，**任何人打开首页即拿到管理令牌** → `存在缺陷`。
- 复用价值：低；AideanFleet 需正式管理后台。

### 3.2 后端
- 技术栈：FastAPI + uvicorn + httpx(async) + pydantic v2 + APScheduler + litellm（`pyproject.toml`）。
- 入口调用链（已确认）：
  `__main__.main()` → `_serve()`（`__main__.py:14-38`）→ 校验 `AUTH_TOKEN ≥16`（`config.is_auth_token_weak`）→ `ClawBotApp.start()`（`app.py:48`）→ `db.init_db` → 为每个 `active` 账号 `start_account_loop`（`app.py:121`，每账号一个 `asyncio.Task` + 一个 `httpx.AsyncClient`）→ `NotifyScheduler.start()` → `_purge_loop`（每 24h）→ `uvicorn.Server.serve()`。
- 入站消息链：`_poll_loop`（`app.py:199`）→ `WeChatClient.get_updates`（`wechat/client.py:36`，POST `ilink/bot/getupdates`，长轮询 35s，ReadTimeout 视为空）→ 持久化游标 `get_updates_buf`（`app.py:220-223`）→ `_dispatch`（L237）→ `WeChatMessage.model_validate` → `SessionRouter.handle`（`session/router.py:72`：过滤非 USER、`messages` 表去重、缓存 context_token、媒体分支、指令分支、`AIChat.chat`）→ `client.send_message(..., context_token)`（`app.py:260`）。
- 出站主动链：`POST /notify` → `Notifier.notify`（`notify/notifier.py:34`）→ 写 `notifications` pending → 复用在线 client（`app.py:40 _provide_client`）→ 最多 3 次、`2^(n-1)` 秒退避 → 更新状态。
- 错误处理：401/403 → 账号 `expired` 并停止循环（`app.py:207-211`）；网络错误 ≤5 次 2s、>5 次 30s 退避（L231-235）。
- 同用户重复扫码：`_supersede_same_user_accounts`（`app.py:131-161`）把同 `ilink_user_id` 的旧账号置 `expired`。注释写明 iLink 语义：“每次扫码生成全新 bot 实例，用户消息只路由到最新授权的 bot”。→ **对 AideanFleet 是关键约束**（`部分确认`：来自作者注释与提交 `ed80fb53`，未用真机复现）。

### 3.3 数据（SQLite，`db.py:37-87`）

| 表 | 主键 | 字段要点 | 问题 |
|---|---|---|---|
| accounts | id(=ilink_bot_id) | bot_token **明文**、baseurl、status、get_updates_buf、ilink_user_id | token 未加密 |
| messages | id(=message_id) | account_id、from_user_id、msg_type | 仅作去重；**不存消息内容**；`message_id` 跨账号全局唯一假设 |
| sessions | (account_id, wechat_user_id) | history_json(整段 JSON)、summary、runtime_config_json | 每次追加都整行重写，O(n) 写放大；无 session_id 维度 |
| notifications | id(uuid) | text、status、attempts、last_error | 无批次/订阅概念 |

- 模型层（`models.py`）完整映射 iLink 消息：`MessageType{USER=1,BOT=2}`、`MessageState{NEW,GENERATING,FINISH}`、`MessageItemType{TEXT,IMAGE,VOICE,FILE,VIDEO}`、`WeChatMessage.context_token/session_id` 等——**这份枚举映射可直接复用**。
- 每次 DB 调用 `_connect()` 新建连接（`db.py:28-34`），并且在 async 事件循环里同步执行 → 阻塞事件循环（见 §3.8）。

### 3.4 交互
- 微信侧：文本问答、`/help /clear /status` 三个指令（`commands/router.py`，精确匹配，`/clear ` 带空格或 `/Clear` 不识别）。
- 媒体消息：设计为“记录 + 回复暂不支持”，但因缺陷**实际抛 NameError、静默不回复**（`app.py:252-253` 捕获异常仅 log）。
- 管理侧：HTML 控制台 + REST + MCP（6 个工具：health/list_accounts/notify_user/get_session/start_wechat_login/check_login_status）。

### 3.5 逻辑
- 路由逻辑硬编码：“任何微信消息 → 同一个 AI 后端”。没有“消息属于哪个输入端/项目”的判定。
- 摘要逻辑：历史 > `MAX_HISTORY`(20) 时保留最近 `max(max_history//2,2)` 轮，其余交给 LLM 摘要（`session/store.py:58-80`）。
- context_token：LRU 128 条内存缓存（`session/router.py:41-48`），**重启即丢失**，进程重启后的首条回复将不带 context_token（影响 → `证据不足`，取决于 iLink 是否强制）。

### 3.6 组件
| 组件 | 文件 | 可复用性 |
|---|---|---|
| iLink 协议头/随机 UIN | `wechat/protocol.py` | 高（逻辑极小，可重写） |
| 扫码登录状态机（wait/scaned/expired/confirmed，自动刷新二维码） | `wechat/auth.py`、`api/routes.py:363-509` | 高 |
| 长轮询客户端 + 游标持久化 | `wechat/client.py`、`app.py:199-229` | 高 |
| 同用户重复扫码作废 | `app.py:131-161` | 高（业务规则） |
| 通知重试 | `notify/notifier.py:34-65` | 中 |
| 会话摘要 | `session/store.py:58-80` | 中（思路） |
| Coze 适配 | `ai/coze.py` | 中（可作为“Coze 输入端”的参考，但它是 Bot 调用而非 ACP） |
| MCP 传输层 | `mcp-npm/index.js` | 中（“智能体通过 MCP 主动推消息给 IM”模式值得借鉴） |

### 3.7 复用
- **可复用（需确认授权后移植/重写）**：iLink 五接口封装、扫码状态机、二维码渲染（data:image / URL / 文本三种兜底，`wechat/auth.py:72-102`）、错误退避策略、supersede 规则、iLink 枚举模型。
- **仅借鉴思路**：MCP 推送工具、通知重试、PIPL 留存清理（`purge_expired_data`）。
- **不复用**：AIChat、SessionStore 整行 JSON、内嵌 HTML、`.env` 定时任务。

### 3.8 性能
- 每账号 1 个协程 + 1 个 httpx 客户端，账号数线性扩展，轻量（`已确认` 结构；未压测 → 吞吐 `证据不足`）。
- 瓶颈：① 同步 sqlite3 在 async 中调用，每次新建连接；② 单账号消息**串行**处理，一条慢 LLM 调用（Coze 默认 60s 超时）会卡住该账号的所有后续消息；③ sessions 整行 JSON 重写。
- 对 AideanFleet：编码智能体一次任务可能数分钟到数小时，**必须改为“入队 + 异步回发”**，不能沿用串行 await。

### 3.9 配置
- 全部来自 `.env`（`config.py`，pydantic-settings alias），`lru_cache` 单例，**无热更新、无 UI 编辑**。
- 关键项：BASE_URL、BOT_TYPE=3、LONG_POLL_TIMEOUT_MS、DB_PATH、AI_*、COZE_*、HOST/PORT(127.0.0.1:8088)、AUTH_TOKEN、RATE_LIMIT_PER_MINUTE、SESSION_RETENTION_DAYS、LOGIN_MAX_REFRESH、NOTIFY_JOBS。
- 注意：README 写 `BOT_TYPE` 默认 `weixin`，代码默认 `"3"`（`config.py:18`）——**文档与代码不一致**（以代码为准）。

### 3.10 知识库
- 无。仅 `sessions.summary`。

### 3.11 响应
- 微信问答响应时间 = LLM 时延；无“正在输入”调用（`send_typing` 定义了但**未被调用**，grep 仅定义处 `wechat/client.py:64`）；无流式/分段（iLink `MessageState.GENERATING` 未使用）。
- 长任务无“已收到/处理中”回执。

### 3.12 存储
- 单文件 SQLite（WAL），Docker `VOLUME /app/data`。适合单机小规模；多实例/高并发写不适合。
- 消息原文不落库（只存去重 ID），历史摘要后原文丢失 → **不满足“按 session 查完整记录”**。

### 3.13 资源
- 依赖少（10 个运行时依赖），镜像基于 `python:3.11-slim`；内存/CPU 占用低（未实测 → `证据不足`）。litellm 依赖体积较大但可替换。

### 3.14 安全
| 项 | 现状 | 标签 |
|---|---|---|
| API 认证 | 单一 Bearer 静态令牌，长度 ≥16 才允许启动 | 已确认 |
| 令牌泄露 | `/` 公开且页面含令牌 | 存在缺陷 |
| 二维码/状态接口 | 公开（`_PUBLIC_PATH`），login_id 为 uuid4 hex，猜测难度高 | 已确认 |
| bot_token 存储 | SQLite 明文 | 存在缺陷（需加密） |
| 限流 | 内存令牌桶，按 IP，仅写方法；超 10000 key 清空 | 已确认 |
| 审计 | `wechat_clawbot.audit` logger | 已确认 |
| 数据留存 | 30 天清理（PIPL 数据最小化） | 已确认 |
| 多租户/RBAC | 无 | 已确认 |

### 3.15 许可证
- 根目录无 LICENSE → 默认“保留所有权利”。`mcp-npm` 子包声明 MIT。**移植代码前须获得作者书面授权，或仅参考协议行为自行重写**（iLink 协议本身由腾讯 `@tencent-weixin/openclaw-weixin-cli` 提供，见 `设计文档.md` §2）。

### 3.16 社区活跃度
- 0 star / 0 fork / 单日发布。风险：无人维护、iLink 协议变更时无上游修复。

---

## 4. 5W1H 拆解（第一轮）

- **What**：一个把微信 ClawBot（iLink）接到单个 LLM 的多账号服务；已实现扫码、长轮询、问答、通知、cron、MCP。缺：编码智能体输入、多 IM、路由模式、总控、知识库。已被证明：28 个单测通过；媒体消息分支崩溃。未证明：真机收发、主动消息频控。
- **Why**：作者目标是“游戏业务系统（奖励一颗麻籽）向用户发微信通知 + AI 问答”（README“与根项目的关系”），因此只做了 `POST /notify`，与 AideanFleet 的“开发者多工具统一入口”目标不同 → 匹配度低是**定位差异**而非实现差。
- **Where/When**：价值集中在 `src/wechat_clawbot/wechat/*` 与 `app.py` 轮询/作废逻辑；应在 AideanFleet“输出端适配器”阶段（通道层）引用，早于路由/总控开发。
- **Who**：作者 CodingHeader（个人）；协议提供方腾讯 iLink；AideanFleet 的“微信通道适配器”负责人应负责移植与真机验收。
- **How**：将 iLink 客户端抽象为 AideanFleet `ChannelAdapter` 接口（`connect/login`、`poll|webhook`、`send(text|card|file)`、`typing`、`capabilities`），把串行 `_dispatch` 改为消息总线入队；`context_token` 持久化；token 加密。
- **What if**：
  - iLink 接口字段变化 → `WeChatMessage` 有 `extra=allow`（`models.py MediaItem/MessageItem`），解析不至于崩，但 `WeChatMessage` 本身未设 extra（会忽略多余字段，pydantic 默认 ignore），风险可控。
  - iLink 关停或改为收费/白名单 → 微信通道整体不可用，AideanFleet 需有企业微信/公众号备选（`证据不足`）。
  - 端口：本项目默认 8088；用户约束 Aidean=3000、AideanBot=3333，若复用需改 `PORT`，否则端口冲突不会发生但不符合约束。
  - 配置缺失：`AUTH_TOKEN` 缺失直接拒绝启动（`__main__.py:22-26`）；AI_KEY 缺失 → 每条消息返回“AI 暂时不可用”。

## 5. 苏格拉底追问 + 双向钢人论证（第二、三轮）

**结论 A：“WechatClawbot 不能作为 AideanFleet 底座。”**
- 凭什么：输入端只有 LLM API（`ai/chat.py`），无 ACP/CLI 适配；输出只有微信；无路由层。证据来自当前最新提交代码。
- 支持论证：全仓 grep 无 `acp`/`claude`/`codex`/`cursor` 进程调用（MCP 包是“被智能体调用”的方向，不是“调用智能体”）；`app.py` 将 router 写死为单个 `SessionRouter`。
- 反对论证：可以把 Claude Code 等通过 MCP 接入，实现“工具→微信”推送，再把 `AIChat` 换成“ACP 客户端”就成了网关——改造量看似不大。
- 裁决：反对意见**部分成立**（MCP 推送确实可用作 S1 的出站半程），但“换掉 AIChat”实际需要新增：多输入注册、路由表、长任务异步、会话映射、多通道抽象——等于重写 80% 以上非协议代码。结论 A **成立**（已确认）。

**结论 B：“微信协议层值得复用。”**
- 凭什么：它是少数用 Python 完整实现 iLink 登录+轮询+回发+作废的代码，且有 28 个单测。
- 反对论证：无许可证；未真机验证；协议本可从腾讯官方 CLI 插件直接学习；代码量很小（协议层 269 行），自写成本也低。
- 裁决：**“借鉴行为与规则 > 拷贝代码”**。复用以“协议知识 + 测试用例思路 + supersede 规则”为主；代码层面在获得授权前按自研重写。结论 B **部分确认**。

**结论 C：“iLink 同一用户仅路由到最新 bot。”**
- 证据：`app.py:131-139` 注释 + 提交 `ed80fb53 feat(core): auto-supersede old bot on same WeChat user re-scan`。
- 反对：可能是作者对某次现象的误读；也可能多 bot 都能收到但顺序不同。
- 裁决：`部分确认`，**需在 AideanFleet 立项早期用真机验证**；若成立，则“一个微信 = 一个 ClawBot 绑定 = 多输入端复用”是架构硬约束（用户的痛点正源于此）。

## 6. 缺陷清单

| # | 缺陷 | 位置 | 证据 | 标签 |
|---|---|---|---|---|
| 6.1 | 媒体消息分支引用未导入的 `ChatRole` → NameError，用户收不到任何回复 | `session/router.py:91`（import 行 L12 缺 ChatRole） | `/tmp/t_media.py` 输出 `NameError` | 存在缺陷 |
| 6.2 | `/` 公开且泄露 AUTH_TOKEN | `api/routes.py:331,131,135` | 代码阅读 | 存在缺陷 |
| 6.3 | bot_token 明文存储 | `db.py:46` | 代码阅读 | 存在缺陷 |
| 6.4 | 单账号串行处理，长 AI 调用阻塞轮询 | `app.py:228-229` | 代码阅读 | 存在缺陷（对长任务） |
| 6.5 | context_token 仅内存 LRU，重启丢失 | `session/router.py:25,58-65` | 代码阅读 | 部分确认（影响待真机） |
| 6.6 | `runtime_config` 无写入入口 | grep `update_runtime_config` 仅定义 | 命令证据 | 已确认 |
| 6.7 | `send_typing` 未使用、GENERATING 状态未使用 | `wechat/client.py:64` | grep | 已确认 |
| 6.8 | README `BOT_TYPE=weixin` 与代码 `"3"` 不一致 | README vs `config.py:18` | 对比 | 已确认 |
| 6.9 | 定时任务 `delivered_count` 内存态、重启归零；不支持一次性任务 | `notifier.py:78` | 代码阅读 | 已确认 |

## 7. 差距 → 补齐方案

| 差距 | 补齐方案 | 来源 |
|---|---|---|
| 编码智能体输入（Claude Code / Codex / Cursor / OpenClaw…） | 采用 ACP 客户端（`@agentclientprotocol/claude-agent-acp`、`codex-acp`、`acpx`）+ 进程/HTTP 适配器 | 借鉴 **Paperclip** `packages/adapters/*`、`packages/adapter-utils/src/acpx-engine/`（见 02 报告） |
| 多 IM 通道抽象 | 定义 `ChannelAdapter` + 能力矩阵（threads/DM/streaming/edit/files/cards/proactiveDM…） | 借鉴 **Paperclip** `server/src/services/chat-channels/provider-catalog.ts` 的 capabilities 设计；Telegram/Discord/Slack 可用 Vercel `chat` SDK；**微信用本项目 iLink 实现**；飞书/钉钉/QQ 需自研或选其他开源 SDK（`证据不足`，未在本次范围内调研） |
| 三种路由模式 | 自研“路由表”：`route(source_input_id → [channel_endpoint_id...], mode, filter, tag)`，统一消息总线 | 自研；Paperclip `chat_agent_routes` 可作 hop 限制参考 |
| 长任务异步 | 入队（Redis/SQLite queue）+ 回执 + 完成后回发 | 自研，参考 Paperclip durable delivery queues |
| /clear 对 ClaudeCode 新开对话 | 映射为 ACP `session/new`；保存旧 sessionId 以便回看 | Paperclip `sessionGeneration` + `agent_task_sessions` |
| 会话记录按 session/resume ID 查询 | 消息原文全量落库（append-only 表），索引 `(input_id, session_id)` | 自研；Paperclip `heartbeat_runs.session_id_before/after` |
| 定时任务（含一次性、节假日） | 持久化调度表 + 中国节假日日历（如 `chinese_calendar` 库，`证据不足`待评估） | 自研；Paperclip routines（cron+timezone+catchUp） |
| 群发（通知模式/S4） | 订阅表 + 批次投递 + 限速 + 失败重试 | 自研，`Notifier` 重试思路可沿用 |
| 总控模式 | 设备端 manager agent（可配模型/skill）、会议协议、升级规则 | 借鉴 Paperclip org chart（`agents.reports_to`）与 issue 委派；自研“必经总控把关”过滤器 |
| 知识库/画像 loop | 待其他参考项目（Hindsight 等）报告 | `待其他员工完成` |
| 安全 | token 加密（KMS/age）、管理端独立登录、移除首页令牌 | 自研 |

## 8. 最终判断（第四轮重构）

1. **明确结论**：WechatClawbot **不适合作为 AideanFleet 底座**；其 **微信 iLink 通道实现**可作为 AideanFleet 微信输出端的首要参考。
2. **依据**：§2 映射表、§3.2 调用链、§6 缺陷。
3. **代码证据**：`app.py:121-267`、`wechat/client.py`、`wechat/auth.py`、`session/router.py:12,91`、`api/routes.py:331`。
4. **命令证据**：`pytest -q → 28 passed`；`/tmp/t_media.py → NameError`；GitHub API（stars 0、license null）。
5. **成立前提**：分析基于 `4ec3bbe8`；iLink 协议行为以作者注释为准。
6. **局限**：未真机扫码；未验证 iLink 主动消息限制、频控、context_token 必要性；未评估 iLink 服务条款。
7. **未验证**：§5 结论 C；Coze 会话行为。
8. **风险**：无许可证；作者停更；iLink 协议/政策变化。
9. **下一步**：① 向作者确认授权或决定重写；② 真机验证“同用户多 bot”与主动推送限制；③ 在 AideanFleet 架构里定义 ChannelAdapter 接口后移植 iLink 适配器。
10. **是否进入下一阶段**：**允许**以“微信通道参考实现”身份进入架构设计阶段；**不允许**作为整体底座进入开发。
