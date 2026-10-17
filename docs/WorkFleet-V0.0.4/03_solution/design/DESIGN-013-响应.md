---
id: DESIGN-013
type: design
title: 响应（≤3 秒回执、状态卡编辑合并、微信小时级摘要、推送面收敛、节点侧流式聚合、渠道降级矩阵）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-008/013/017/023/024/037
  - REQ-NF-001、REQ-F-009/010/015、REQ-C-008
  - packages/contracts/adapters/channel-capabilities.schema.json、channel-kinds.v1.json
  - packages/contracts/schemas/entities/message-body.schema.json（status_card）
  - packages/contracts/protocol/frames/agent.output|agent.status.schema.json
  - V0.0.2/30-协议与端点/01 §5（session/update 变体）、03（各渠道限制）、04 §2.1/§6（映射与渲染）
---

# DESIGN-013：响应

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。

## 1. 原则（DEC-017）
1. **入站即回执**：渠道支持时，入站到“用户可感知回执” p95 ≤ 3 s（REQ-NF-001）。
2. **过程不刷屏**：过程信息只进入**可编辑状态卡**（支持 `editMessage` 的渠道）或**小时级摘要**（不支持编辑且有额度的渠道，如微信）。
3. **只推四类**：完成（final）、失败（error）、审批（approval）、阻塞（blocked）。其余（思考、工具调用、计划、用量）不单独外发。
4. **聚合在节点**：ACP 流式更新在节点侧聚合，中转只收聚合后的 `agent.output` / `agent.status`（architecture §6.1 步骤 6）。

## 2. 回执（≤3 秒）

### 2.1 时间预算（中转内部，推断，待实测）
| 阶段 | 预算 | 说明 |
|---|---|---|
| 平台事件到达 → 入站持久化（幂等键 `channelId+platformMessageId`） | ≤ 200 ms | domain-events `message.received` |
| 平台 ACK（飞书长连接事件须 3 s 内处理完，否则重推，已确认 V0.0.2/03 §2） | 持久化后立即 | 先 ACK 后处理 |
| 授权判定 + 指令解析 + 选路 | ≤ 100 ms | 纯内存 + 单行查询 |
| 回执投递入队（p0 通道，绕过普通队列排序） | ≤ 100 ms | DESIGN-018 重试表“交互类” |
| 渠道发送 RTT（香港出站） | ≤ 1.5 s | 证据不足（U-04），TASK-041 实测 |
| **合计 p95** | **≤ 3 s** | REQ-NF-001 |

回执**不等待节点**：节点 RTT（跨境 ≤2 s，REQ-NF-001 部分确认）不计入回执预算。

### 2.2 回执形式（按能力，不写渠道特判：由 `capabilities` 决定，DEC-008）
```text
receiptMode(cap, ctx):
  if ctx.isCommand:                       → 直接回指令结果（/list /status 等同步命令，本身即回执）
  if ctx.deviceOffline:                   → 文本 "设备离线，已排队（第 N 条）"（DEVICE_OFFLINE 的 ui 文案）
  if ctx.held:                            → 文本 "z1 有待审批（#3），本条已暂存"（held，DEC-012）
  if cap.editMessage:                     → 发送 status_card(state=queued, title=…) ；记下 platformMessageId，后续编辑
  elif typingIndicator 可用（适配器私有能力）: → 输入中状态（不消耗消息额度）
  elif cap.proactiveQuota != null:        → 无回执（额度只留给结果，见 §5）；队列位次 >1 时例外发文本
  else:                                   → 文本 "已收到，处理中"
```
- “输入中”指示：微信 `sendtyping`（需 `getconfig` 取 `typing_ticket`，已确认 V0.0.2/03 §1.2）、Telegram `sendChatAction`、Discord typing。它们不在 `channel-capabilities` 契约中（差异 #1），v1 作为适配器内部可选方法 `sendTyping?()`，核心只调用、不判断渠道。微信 typing 是否消耗主动额度：**证据不足**，TASK-041 实测；若消耗则关闭。
- QQ 被动回复：单聊消息 60 分钟内有效、每条最多回复 4 次；群 5 分钟、5 次（已确认 V0.0.2/03 §3）→ 回执若用文本会占 1 次，所以 QQ 走“无回执，结果用被动回复”。由适配器在 capabilities 外的 `passiveReplyBudget` 内部计数（差异 #2）。

## 3. 状态卡（可编辑渠道）

### 3.1 状态机（与 IR `status_card.state` 枚举一致）
```text
queued ──开始执行──▶ running ──request_permission──▶ waiting ──决定──▶ running
   │                    │  └─ plan/tool 进度 → progress 更新（不改 state）
   │                    ├─ stopReason=end_turn ───────────────▶ done
   │                    ├─ error / refusal / max_tokens ──────▶ failed
   └─ cancel ───────────┴─ stopReason=cancelled ─────────────▶ failed（title 前缀“已取消”）
```
- 一个**轮次（turn）**对应一张卡；同一会话新轮次新开一张卡。
- `done` 时：卡片标题改为“完成”，最终正文作为**新消息**发送（final），而不是塞进卡片 → 保证用户收到通知（编辑通常不触发提醒，推断，按渠道待实测）。例外：Web 渠道直接在卡片下方渲染 final。

### 3.2 编辑合并（节流）
每张卡维护 `{latestState, latestProgress, latestTitle, lastEditAt, pending}`；规则：
```text
onStatus(update):
  pending = merge(pending, update)                 # 只保留最新值
  if state 变化（queued→running、→waiting、→done/failed）: 立即 flush（不受节流）
  elif now - lastEditAt >= minEditIntervalMs(channel) 且 |progress-已发progress| >= 10: flush
  else: 定时器在 lastEditAt+minEditInterval 时 flush 最新 pending
```
| 渠道 kind | minEditIntervalMs | 依据 |
|---|---|---|
| web | 250 | 内部 WSS，推断 |
| feishu | 1000 | 同用户/同群 5 QPS（已确认），留余量 |
| dingtalk | 1000 | AI 卡片流式更新存在（已确认），频率限制证据不足 |
| telegram | 2000 | 单聊建议 ≤1 条/秒（已确认）；编辑是否同额度证据不足 |
| discord | 2000 | 全局 50 req/s，按路由头动态（已确认）；推断 |
| qq / wechat_clawbot | —（editMessage=false） | channel-kinds.v1.json |
- 卡片编辑失败（平台返回“消息不可编辑/超期”，飞书发送后 14 天内可更新，已确认）→ 放弃编辑，改为在 done/failed 时发新消息；不重试编辑。
- 中转实现：状态更新到达 → 不新建 delivery，而是对“该卡片首次 delivery”执行 `adapter.update(platformMessageId, rendered)`；编辑本身不入 `deliveries`，只在 `messages` 账本 append 一条 `kind=status` 的记录（账本 append-only）。如何把后续 status 关联到首条卡片，契约缺字段（差异 #3）；v1 约定：`agent.output(kind=status)` 的 `replyToId` 填**该轮首条 status 消息的 messageId**，中转据此找到首条 delivery 的 `platformMessageId`。

## 4. 推送面：只推四类
| 事件（节点产生） | 外发形式 | 优先级默认 | 说明 |
|---|---|---|---|
| 轮次完成（stopReason=end_turn） | `agent.output kind=final` | p2 | 完成 |
| 失败（进程崩溃、AGENT_UNAVAILABLE、refusal、max_tokens、max_turn_requests） | `kind=error` | p1 | 失败 |
| 权限请求 | `approval.request` → IR `approval` 块 | p1（risk=high 为 p0） | 审批（DESIGN-017 §2） |
| 阻塞：held 超 10 min、写租约冲突 `AGENT_BUSY_WRITE_LEASE`、设备离线且有排队、总控上报 | `kind=status` 或 `error` | p1 | 阻塞 |
| 思考、工具调用、计划、usage、available_commands | 不外发；只更新状态卡/摘要/本机转录 | — | DEC-017 |
- 路由 `priorityFloor`（route.schema.json）：低于下限的消息 delivery 标 `suppressed`（仍入账本），不发送。
- 总控模式：以上四类先经总控把关（DESIGN-020），`supervisorVerdict` 决定是否外发。

## 5. 微信（无编辑 + 有额度）：小时级摘要
- 触发条件：渠道 `editMessage=false` 且 `proactiveQuota != null`（不硬编码 wechat，DEC-008）。
- 每个 `(channelId, recipientId)` 维护一个摘要桶；进入桶的内容：状态变化（某会话 running/waiting/done）、p3 消息、被额度预算器“降级合并”的 p2 消息（DESIGN-017 §6）。
- 发出时机（先到者）：
  1. 整点窗口：桶首条进入后满 60 分钟；
  2. 用户下一次入站（额度刷新后，先发摘要 1 条，再处理该入站）；
  3. 桶内条目 ≥ 20 条（推断）。
- 摘要格式（IR，kind=digest）：`heading "近 1 小时（14:00–15:00）"` + `list`：`[项目A/z1] 完成：修复登录 bug（3 轮）`；超过 maxMessageChars 截断并附“详情见控制台”。
- 剩余额度 ≤ 2 时摘要不发（DESIGN-017 §6.2：剩 2 只放行 p0/p1/final，剩 1 只放行 p0），等下一次入站。
- 完成/失败/审批 **不进摘要**，立即发送（仍受额度预算器约束）。

## 6. 节点侧流式聚合（agents 模块 `TurnAggregator`）
每个正在执行的轮次一个聚合器：
```ts
interface TurnAggregator {
  onUpdate(u: AcpSessionUpdate): void;      // session/update 通知
  onPermission(req): void;                   // 转 approval.request（立即，不节流）
  onStop(stopReason: 'end_turn'|'max_tokens'|'max_turn_requests'|'refusal'|'cancelled'): void;
}
```
| ACP `sessionUpdate`（V0.0.2/01 §5，已确认） | 聚合动作 |
|---|---|
| `agent_message_chunk` | 追加到 `finalText` 缓冲（上限 4 MiB，超出转附件，§6.2） |
| `agent_thought_chunk` | 只写转录（role=thought），不外发 |
| `tool_call` / `tool_call_update` | 更新 `currentTool = title/kind/status`；状态卡 title = `执行中：{tool.title}`（截 60 字） |
| `plan` | `progress = round(100 * completed / total)` |
| `usage_update` | 只写本机（外部工具用量，不进费用统计；DEC-044：外部工具用其自有模型） |
| `available_commands_update` / `current_mode_update` / `config_option_update` / `session_info_update` | 更新会话元数据（`nativeSessionId`、标题） |
| `notice` | 视为 status（若为错误类则 p1） |
| `user_message_chunk`（load 回放时） | 只写转录 |
- 外发节流：`agent.status`（状态枚举变化）立即发；`agent.output kind=status` 每轮次最多每 **2 s** 一帧，且仅在 state/title/progress 变化时发（推断；中转再按 §3.2 节流）。
- 轮次结束：发一帧 `agent.output kind=final`（或 error），`body.blocks` 由 Markdown→IR 转换（`paragraph/heading/list/code/table`），`nativeSessionId` 随帧回传。
- **长任务心跳**：running 超过 60 s 且期间无任何外发 → 发一次 status（与 V0.0.2/04 §6 “超过 60 s 发一次进行中”一致），之后每 10 min 一次（推断）。微信经 §5 进入摘要而非即时。

### 6.2 大输出
- 帧上限 1 MiB（ADR-005）。`finalText` 序列化后 > 900 KiB（留 envelope 余量）→ 节点先把全文作为 `text/markdown` 附件经 `POST /api/v1/attachments`（设备令牌，≤25 MiB，resources.json）上传，帧内只放前 4,000 字 + `attachment` 块。> 25 MiB → 截断并提示“完整结果见本机控制台”。
- 注意：附件上传即“内容上中转”，仅限智能体输出文本（已作为回复外发的内容），不含工作目录文件（resources.json `nodeFiles.rule`）。

## 7. 渠道降级矩阵（v1，按 channel-kinds.v1.json 规划值；平台限额以真机为准）
| 能力 \ 渠道 | web | feishu | dingtalk | telegram | discord | qq | wechat_clawbot |
|---|---|---|---|---|---|---|---|
| 回执 | 状态卡 | 状态卡 | 状态卡 | typing + 状态消息 | typing + 状态消息 | 无（保留被动回复） | typing（待实测）/无 |
| 过程 | 实时卡片 | 编辑卡片 1 s | 编辑卡片 1 s | 编辑消息 2 s | 编辑消息 2 s | 无 | 小时摘要 |
| 完成 | 消息 | 新消息 | 新消息 | 新消息（Markdown） | 新消息（≤2000 字分段） | 被动回复/主动（配额） | 消息（扣额度） |
| 审批 | 按钮 | 卡片按钮（回调 3 s 内 ACK） | 互动卡片按钮 | Inline 按钮 | 按钮组件 | 按钮（权限待核）/口令 | 口令 `Y{n}/N{n}` |
| 表格 | 表格 | 卡片表格 | Markdown 表格 | 等宽文本 | 等宽文本 | Markdown/文本 | 纯文本列表 |
| 长文本 | 全文 | 卡片 ≤30 KB 分段 | 分段 | 分段 | 2000 字分段 | 分段 | 分段 + 详见控制台 |
| 附件 | 链接 | 文件 | 文件 | 文件 | 文件 | 富媒体 | 文件（CDN 加密上传，待实测）/链接（不可点，部分确认） |
渲染规则细节见 DESIGN-018 §6（IR → 渠道格式）。

## 8. 指标与验收
| 指标 | 目标 | 测量 |
|---|---|---|
| `wf_receipt_latency_ms{channel}` | p95 ≤ 3000 | 入站持久化时刻 → 回执 delivery `sent` |
| `wf_status_edits_total{channel,result}` | — | 编辑成功/失败 |
| `wf_digest_sent_total{channel}` | — | 摘要条数 |
| `wf_turn_frames_per_turn` | 中位数 ≤ 5（推断） | 每轮次 node→relay 帧数 |
验收：FakeChannel 模拟 editMessage=true/false 两类；FakeAgent 回放 50 条 chunk + 3 次 tool_call 的录制，断言外发帧 ≤ 5、状态卡编辑次数 ≤ ⌈时长/间隔⌉+状态变化数、微信模拟只收到 final。

## 9. 与契约的差异 / 待办
1. `channel-capabilities` 无“输入中指示（typing）”能力位 → 建议增 `typingIndicator: boolean`。
2. 无“被动回复窗口/次数”（QQ 60 min×4、群 5 min×5）与“流式编辑方式（edit / card-stream）”能力位 → 建议增 `passiveReply: {windowSec, maxReplies}|null`、`streamingEdit: 'none'|'edit'|'card_stream'`。
3. `agent.output` 无“更新哪张状态卡”的关联字段 → v1 借用 `replyToId` 指向本轮首条 status 消息；建议增 `turnId` 或 `supersedesMessageId`。
4. `message-body` 无 `blocked` 状态（status_card.state 只有 queued/running/waiting/done/failed）→ 阻塞用 `waiting` + callout(warn) 表达；如需区分，增 `blocked`。
