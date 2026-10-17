---
id: DESIGN-005
type: design
title: 交互详细设计（IM 指令、审批、Web 对话、引用回复、离线、扫码与 /bind、空态文案）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "packages/contracts/commands/im-commands.json"
  - "packages/contracts/errors/error-codes.json"
  - "packages/contracts/ux/ux-states.json"
  - "packages/contracts/schemas/entities/approval.schema.json"
  - "packages/contracts/api/relay.openapi.json（qr-login、bind-confirm、messages）"
  - "DEC-011"
  - "DEC-012"
  - "DEC-017"
  - "DEC-023"
  - "DEC-030"
  - "DEC-046"
  - "DEC-057"
  - "REQ-F-009/015/017/018/019/020/033"
  - "REQ-C-008"
  - "V0.0.2/40-综合/08 §1.3–§1.5（微信约束与摘要）"
  - "glossary.md"
---

# DESIGN-005 交互

> 原则：所有渠道与 Web 行为一致（REQ-F-018），差异只来自渠道能力（按钮/卡片/可编辑/markdown），由渲染降级处理（DESIGN-007 §4）。文案集中在 i18n 资源（`apps/relay/src/i18n/zh-CN/im.json`；Web 在 `apps/web/src/i18n`），下文为 zh-CN 初稿，`{}` 为变量。

## 1. 输入规范化与解析顺序
1. 文本 NFKC 规范化（全角 `／`→`/`、`Ｙ１`→`Y1`、全角空格→半角），去首尾空白。
2. 识别顺序（第一条命中即止）：
   - `^[YyNn](\d{1,2})$` → 审批口令（§3）；
   - 以 `/` 开头（契约 prefixes `/`、`／`）→ 指令（§2）；
   - 以 `@<alias>` 开头（alias 后跟空格或换行）→ 定向发送（等价 `/@alias`）；
   - 其他 → 普通消息，进入路由（DESIGN-006）。
3. 未授权发送者（`recipient.authorized=false`）只允许 `/bind`；其他一切输入回固定提示（§2 `RECIPIENT_UNAUTHORIZED` 行），不进入路由（DEC-030、permissions.json forbiddenPaths）。
4. 群聊：仅当消息 @ 了 Bot 或以 `/` 开头时处理（渠道支持 @ 识别时）；否则忽略（推断：避免群内噪音触发智能体，可配置）。
5. 指令权限：每条指令的 `permission` 字段（im-commands.json）按接收人关联用户（`linked_user_id`）在本组织的角色判定。已授权但**未关联用户**的接收人（例如管理员在控制台直接授权的群）只允许普通消息（视作 `agent.prompt`）与 `/help /list /status`，其余指令回“请先 /bind 识别你的账号”（设计选择：安全优先，见 §11 I-2）。

## 2. 指令逐条行为与回执文案
| 指令 | 参数 | 行为（中转） | 成功回执 | 失败回执（错误码） |
|---|---|---|---|---|
| `/help` | — | 列出该发送人有权使用的指令（按 permission 过滤） | `可用指令：\n/list 查看智能体\n/use <别名> 切换默认对象\n@别名 内容 发给指定智能体\n/clear [别名] 新开对话\n/stop [别名] 停止\n/status [别名] 状态\n/history [编号] [条数] 查看记录\n/bind 识别我的账号\nY<n>/N<n> 批准/拒绝第 n 号审批` | — |
| `/list` | — | 列出该接收人所有绑定中的来源智能体（Web：用户有权限的全部智能体），每行：别名、项目、设备、状态、是否焦点 | `智能体（{n}）：\n▶ z1 · 项目A · 笔记本 · 空闲\n  cc1 · 项目B · 台式机 · 运行中（排队 2）\n  cx1 · 项目B · 台式机 · 离线` （▶=当前焦点） | 空：`当前没有可用的智能体。请在控制台“绑定”中把智能体绑定到此对话。` |
| `/use <alias>` | 必填 | 校验 alias 存在且在该接收人的绑定来源中（Web 不要求绑定）→ 写 `recipient_focus` | `已切换到 [{项目}/{alias}]，之后的消息将发给它。` | 不存在：`没有名为 {alias} 的智能体，发送 /list 查看。`（NOT_FOUND）；不在绑定：`{alias} 未绑定到此对话。`（ROUTE_INVALID） |
| `@alias 文本` / `/@alias 文本` | 文本必填 | 只这一条发给该智能体，不改焦点 | 投递后回执：`已转给 [{项目}/{alias}]` + 排队时 `（排队第 {k} 位）` | 同 /use；离线：§6 |
| `/clear [alias]` | 可选 | 目标 = alias 或当前焦点；会话 generation+1，发 `agent.clear`；旧记录保留 | `[{alias}] 已开启新对话（第 {g} 代，编号 {displayId}）。旧记录可用 /history {displayId} 查看。` | 无目标：`请先 /use 选择智能体，或写 /clear <别名>。` |
| `/stop [alias]` | 可选 | 发 `agent.cancel`（ACP session/cancel） | `已请求停止 [{alias}] 当前任务。`；节点确认后（agent.status=idle）不再另发消息 | 未在运行：`[{alias}] 当前没有正在执行的任务。` |
| `/stop all` | — | 急停：tenant `emergency_stopped_at=now`；向该组织全部在线设备发 `emergency.stop`；暂停全部出站投递（p0 急停回执除外） | `⛔ 已急停：所有智能体与外发已冻结（{at}）。恢复请到控制台点击“恢复”。` | 无权限（FORBIDDEN）：`你没有急停权限。` |
| `/status [alias]` | 可选 | 无参：列出焦点智能体 + 所有运行中/待审批；有参：该智能体详情 | `[{alias}] {状态} · 排队 {q} · 待审批 {a}\n设备：{device}（{在线/离线，最后在线 {t}}）\n会话：{displayId} 第 {g} 代` | NOT_FOUND 同上 |
| `/history [displayId\|resumeId] [n]` | 可选，n 默认 10，上限 50（设计值） | 无参 = 当前焦点会话；按 displayId 或原生 resumeId 定位；从账本取最近 n 条；渠道字数上限内截断 | `【{displayId} 第 {g} 代 · 最近 {n} 条】\n{时间} 你：…\n{时间} {alias}：…\n（更多请在控制台查看）` | 找不到：`没有找到编号为 {x} 的会话。` |
| `/bind` | — | 生成 6 位码写入 recipient（TTL 10 分钟，设计值） | `你的识别码：{code}（{ttl} 分钟内有效）。请登录控制台 → 接收人 → “输入识别码”完成绑定。` | 渠道已是他人账号：照常发码；确认时以确认者为准并审计 |
| `Y{n}` / `N{n}` | — | 见 §3 | 见 §3 | 见 §3 |
| `/boss <文本>` | 必填 | 总控模式：发给该绑定的总控智能体，独立会话，不进执行队列（DEC-018、REQ-F-023） | `已转给总控。` | 无总控绑定：`此对话未启用总控模式。` |
| 未知指令 | — | — | — | `未知指令 {cmd}，发送 /help 查看。` |
| 未授权 | — | 只回固定提示，不路由 | — | `你还没有使用权限。请发送 /bind 获取识别码，并让管理员在控制台确认。`（RECIPIENT_UNAUTHORIZED） |
| 急停中发消息 | — | 不路由；不排队 | — | `⛔ 当前已急停，消息未发送。`（EMERGENCY_STOPPED） |

> 契约 DEC-011 中的 `/mirror` 未出现在 im-commands.json，以契约为准不实现（§11 I-3）。

## 3. 审批交互（REQ-F-020、DEC-011）
### 3.1 呈现
- 审批到达（`approval.requested`）→ 发给：该会话的发起接收人；若 `risk=high` 且发起人非设备所有者/admin，同时发给设备所有者（Web 收件箱必有）。
- 内容：`【审批 #{shortCode}】[{项目}/{alias}] {summary}\n风险：{低/中/高} · {expiresIn} 分钟后自动拒绝`。
| 渠道能力 | 呈现 | 依据 |
|---|---|---|
| `buttons=true`（飞书/钉钉/QQ/Telegram/Discord/Web） | 卡片或消息 + 按钮，按钮来自 `options[].label`（allow_once / allow_always / reject…）；按钮回调载荷 = `{approvalId, optionId}` | channel-kinds.v1 |
| `buttons=false`（微信 ClawBot） | 纯文本尾部：`回复 Y{n} 允许一次，N{n} 拒绝` ；若存在 allow_always 选项，附 `回复 Y{n}A 始终允许`（口令扩展，见 §11 I-4） | REQ-C-008（无按钮） |
### 3.2 决策
```text
Y{n} / 按钮“允许”：optionId = options 中 kind=allow_once 的第一个
N{n} / 按钮“拒绝”：optionId = options 中 kind=reject 的第一个
校验：approval 存在于本 tenant 且 status=pending（ux_approvals_code）→ 否则 APPROVAL_EXPIRED / APPROVAL_ALREADY_DECIDED
权限：risk=high → approval.decide_high 或 principal==device.owner；其余 approval.decide_low（契约 permissions.json）
写入 decided_by（usr_ 或 rcp_）、decided_option → 发 approval.decision 帧 → 释放 held
```
| 结果 | 回执（无按钮渠道发文本；可编辑渠道编辑原卡片） |
|---|---|
| 批准 | `✅ #{n} 已批准（{label}），[{alias}] 继续执行。` |
| 拒绝 | `❌ #{n} 已拒绝。` |
| 已过期 | `⌛ #{n} 已超时自动拒绝。`（APPROVAL_EXPIRED，卡片置灰） |
| 重复 | `#{n} 已由 {who} 处理：{结果}。`（APPROVAL_ALREADY_DECIDED） |
| 无权限 | `#{n} 为高风险操作，只有管理员或设备所有者可以批准。`（FORBIDDEN） |
### 3.3 超时
- 默认 15 分钟自动拒绝（设计值，DESIGN-011 `WF_APPROVAL_TIMEOUT_SEC`；契约只规定“超时默认拒绝”）。剩余 3 分钟时对 p0 接收人发一次提醒（可编辑渠道改卡片倒计时，不额外发）。
### 3.4 held（DEC-012）
- 目标智能体有 pending 审批时，新消息进入 held，回执：`[{alias}] 正在等待审批 #{n}，你的消息已暂存，审批后按顺序发送。`
- 审批结束（批准/拒绝/过期）→ 按 `held_at` 顺序释放，每条重新走路由第 9 步（设备选择）；不再重复回执。

## 4. Web 对话交互（REQ-F-015、DEC-056）
| 区域 | 行为 |
|---|---|
| 会话列表 | 按项目树分组；每项：别名、displayId、最后一条摘要、未读数、状态点；顶部“新对话”= `POST /conversations` 选择智能体 |
| 消息流 | 用户消息右侧、智能体左侧；IR 块完整渲染（标题/列表/代码高亮/表格/callout/kpi/附件）；`status_card` 原位更新（同一轮只显示一张）；generation 分隔线“第 {g} 代 · /clear 于 {t}” |
| Composer | 输入 `/` 弹出指令补全（来自 im-commands.json，按 /me.permissions 过滤）；`@` 弹出别名补全；Enter 发送；附件拖拽上传（resources.json，≤25 MiB） |
| 审批卡 | 内嵌按钮（options）；倒计时；决策后卡片显示结果；同时出现在 `/approvals` |
| 引用 | 悬停消息 →“引用回复”，发送时带 `replyToId`（契约 messages POST） |
| 停止 | 运行中显示“停止”按钮 = `POST /conversations/{id}/cancel` |
| 离线 | 设备离线时 Composer 上方黄色条：`{设备} 离线（最后在线 {t}），消息将排队，上线后自动发送。排队 {q} 条。`（ux offline 态） |
| 急停 | 全局红色横幅：`已急停（{at}）`，有权限者显示“恢复”按钮（EMERGENCY_STOPPED） |

## 5. 引用回复（REQ-F-017、G2）
- IM 中用户引用一条消息回复：
  - 被引用的是**我方出站**（某智能体的输出）→ 通过 `deliveries.platform_message_id` 找到 message → conversation → 发给该会话的智能体（忽略焦点）。回执：`↩ 已回复给 [{项目}/{alias}]（{displayId}）`。
  - 被引用的是**用户自己的入站** → 找到该入站所属会话，同上。
  - 找不到（过旧、跨渠道、平台不提供引用 id）→ 按普通消息走焦点，并提示：`未能识别引用的消息，已按当前对象 [{alias}] 发送。`
- 渠道 `quoteReply=false` 时无溯源，退化为焦点；Web 永远支持。
- 平台是否在入站事件中提供“被引用消息 id”：飞书/Telegram/Discord 有回复关联字段（推断，待各渠道 TASK 实测）；微信 ClawBot **证据不足**（TASK-041）。

## 6. 离线提示（DEC-037、REQ-F-005）
| 场景 | IM 回执 | Web |
|---|---|---|
| 目标设备离线 | `[{alias}] 所在设备“{device}”离线（最后在线 {t}），消息已排队，上线后自动发送。`（DEVICE_OFFLINE） | §4 离线条 |
| 设备上线、排队消息发出 | 不额外发消息（避免刷屏）；若排队超过 30 分钟，发一条 `[{alias}] 设备已上线，正在处理你排队的 {q} 条消息。` | 离线条消失 |
| 设备被吊销 | `[{alias}] 所在设备已被移除，无法发送。请联系管理员。`（DEVICE_REVOKED） | 错误态 |
| 智能体不可用 | `[{alias}] 无法启动（{原因摘要}），请在本机控制台“诊断”查看。`（AGENT_UNAVAILABLE） | 会话内提示 + 诊断链接 |

## 7. 微信专属：额度与续期（REQ-F-009、DEC-023）
- 每个 (渠道, 接收人) 维护 `sent_since_refresh`；剩余 ≤3 时，在下一条出站尾部追加：`⚠ 本时段还可发 {k} 条，回复任意字可续期。`
- 剩余 0 或 context_token 超 24 h：p0 改走备用渠道（DESIGN-002 §7.4），其余排队到下次入站；控制台渠道卡显示“额度用尽”。
- 合并摘要（p3）格式（V0.0.2 §1.5，部分确认）：
```text
【WorkFleet 摘要 10:00–11:00】完成 4 · 失败 1 · 待审批 0
1. [项目A/cc1] 完成：重构登录模块
2. [项目B/cx1] 失败：单测 3 项未过
回复 /history 编号 查看详情
```

## 8. 扫码与 /bind 时序
### 8.1 微信扫码绑定渠道（S2，一次扫码）
```text
用户(Web)            中转 channels                 wechat-clawbot 适配器            iLink
  │ 新建渠道 kind=wechat_clawbot ─▶ POST /channels (201, health=disabled)
  │ 点“扫码”  ─────────────────────▶ POST /channels/{id}/qr-login
  │                                   │── beginQrLogin() ────────────▶│── get_bot_qrcode ────▶│
  │◀── 201 {qrImageDataUrl, loginId, expiresAt} ◀───────────────────│◀──────────────────────│
  │ 每 2 s 轮询 GET /qr-login/{loginId}（设计值）
  │                                   │── pollQrLogin() ─────────────▶│── get_qrcode_status ─▶│
  │◀── {state: waiting|scanned} ───────│
  │      (手机扫码并确认)
  │◀── {state: confirmed} ─────────────│ 适配器取得凭据 → credential_enc；计算 bot_identity_hash
  │                                   │   唯一冲突 → state=failed + BOT_IDENTITY_CONFLICT（向导阻断）
  │                                   │   成功 → health=healthy → start() 开始 getupdates 长轮询
  │ 页面：成功态 Toast“微信已连接”；提示“请在微信里给 ClawBot 发一条消息，然后发送 /bind”
  过期：state=expired → 页面显示“二维码已过期”+ 重新获取按钮
```
> iLink 接口名取自 V0.0.2/10-参考项目/11（WCB 静态阅读，已确认存在于该项目代码）；其返回的状态值与超时以 TASK-041 真机为准（证据不足）。契约 `state` 枚举（waiting/scanned/confirmed/expired/failed）为中转对前端的稳定接口，适配器负责映射。

### 8.2 /bind（识别我的账号）
```text
IM 用户                         中转                                      Web（已登录用户）
  │ 发送 /bind ──────────────▶ recipients.resolveOrCreate（authorized=0）
  │                            生成 6 位码（tenant 内未过期唯一）、TTL 10 分钟
  │◀── “你的识别码：482913…” ──│
  │                                                                       │ 接收人页 → 输入识别码
  │                            ◀── POST /recipients/bind-confirm {code} ──│（需 recipient.authorize）
  │                            校验：码存在、未过期、recipient.tenant == principal.tenant
  │                            置 linked_user_id=principal.userId, authorized=1, 清空 bind_code；审计 recipient.authorized
  │◀── “✅ 已识别为 {displayName}，现在可以直接对话。发送 /list 查看智能体。”
  │                                                                       │◀── 200 recipient；成功 Toast
  失败：码错误/过期 → 404 NOT_FOUND，Web 字段下显示“识别码无效或已过期，请在 IM 重新发送 /bind”
```

## 9. 空态文案（ux empty 态：说明 + 一个主按钮）
| screen | 说明 | 主按钮 |
|---|---|---|
| device_list | 还没有连接任何电脑。WorkFleet 需要在你的电脑上运行“本机节点”来驱动智能体。 | 生成配对码 |
| device_pairing | 在电脑上安装本机节点后，运行 `workfleet-node pair` 并输入下方配对码（10 分钟内有效）。 | 生成配对码 |
| project_tree | 还没有项目。项目用来归类智能体、会话和绑定。 | 新建项目 |
| agent_list | 还没有智能体。先连接一台电脑，再添加 Claude Code、Codex 等工具。 | 添加智能体 |
| agent_form | 未检测到可用的智能体程序。请先在电脑上安装对应工具并登录。 | 查看本机诊断 |
| channel_list | 还没有接入通讯软件。不接也能在网页里直接对话；接入后可以在微信、飞书等收发消息。 | 接入渠道 |
| channel_bind_wechat_qr | 点击获取二维码，用要接收消息的微信扫码。 | 获取二维码 |
| channel_form | 选择一种渠道类型开始配置。 | 选择渠道类型 |
| recipient_list | 还没有接收人。在 IM 里给机器人发一条消息后，这里会出现对应的接收人。 | 输入识别码 |
| route_list | 还没有绑定。绑定决定智能体的消息发给谁、谁能给智能体发消息。 | 新建绑定 |
| route_editor_dry_run | 输入一条样例消息，预览它会被发给哪个智能体、各接收人能看到什么。 | 运行预览 |
| chat | 选择左侧的会话，或新开一个对话。 | 新对话 |
| conversation_history | 输入关键词、会话编号（如 WF-12）或原生会话 ID 查找记录。 | 搜索 |
| approval_inbox | 没有待处理的审批。智能体请求权限时会出现在这里。 | 返回对话 |
| audit_log | 所选时间范围内没有审计记录。 | 清除筛选 |
| members | 只有你一个成员。邀请同事加入并分配角色。 | 邀请成员 |
| filter_rules | 还没有过滤规则。规则可以按接收人和业务线隐藏或脱敏字段。 | 新建规则 |
| notifications_settings | 尚未开启浏览器通知。开启后，审批和完成提醒会推送到这台设备。 | 开启通知 |
| emergency_banner | （未急停时不显示横幅） | — |
| node_local_models | 还没有模型配置。总控需要一个模型配置才能做智能把关；不配置时使用规则把关。 | 添加模型配置 |
| node_local_agents | 未检测到已安装的智能体程序。 | 重新检测 |
| node_local_twin | 还没有分身数据。你发出的指令和任务时间线会记录在这里，只保存在本机。 | 返回首页 |
| node_local_doctor | 点击运行自检。 | 运行自检 |

## 10. 通知文案约定（p0–p3）
- 标签前缀：`[项目/别名]`（message-body `tags`）。p0：`🔴`；p1：`🟠`；p2 无前缀；p3 只进摘要。
- Web Push 标题 ≤ 40 字，正文 ≤ 120 字；点击进入对应会话或审批。

## 11. 与契约的差异 / 待办
| # | 发现 | 处理 |
|---|---|---|
| I-1 | 审批超时时长、/bind 码 TTL、/history 上限契约未定义 | 本文设计值：15 分钟、10 分钟、50 条；DESIGN-011 可配 |
| I-2 | 未关联用户的已授权接收人（如管理员授权的整个群）对应何种角色，契约未定义 | 本文限定其只能普通对话与只读指令（§1 第 5 条）；建议契约补规则 |
| I-3 | DEC-011 含 `/mirror`，契约 im-commands.json 无 | 以契约为准，不实现 |
| I-4 | 无按钮渠道表达 allow_always 的口令契约未定义（只有 `Y{n}/N{n}`） | 设计扩展 `Y{n}A`；需契约补登记后方可实现，否则微信仅支持允许一次/拒绝 |
| I-5 | `/` 开头文本在微信 ClawBot 能否送达（V0.0.2 §1.3 部分确认） | TASK-041 实测；若不行，需契约增加中文别名（如“清空”“切换 z1”） |
| I-6 | qr-login 状态接口无错误原因字段（`failed` 时前端无法区分身份冲突与其他失败） | 前端统一提示并引导看渠道健康；建议契约在状态响应加 `errorCode` |
