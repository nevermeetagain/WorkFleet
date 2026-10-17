---
id: DESIGN-021
type: design
title: 分身数据（采集点、中转 twin.capture 转发、节点存储、查看/修改/删除/导出、隐私边界、v4 学习 loop 预留）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-037/044/048/049
  - REQ-F-029、REQ-NF-005、G21、backlog BL-007
  - packages/contracts/schemas/entities/twin-event.schema.json
  - packages/contracts/protocol/frames/twin.capture.schema.json
  - packages/contracts/api/node-local.openapi.json（/local/v1/twin/*）
  - packages/contracts/events/domain-events.json（message.received、message.routed、approval.decided、supervisor.verdict）
  - database/migrations/node/0001_init.sql（twin_events）
  - V0.0.2/10-参考项目/15-Hindsight §13 H4（persona loop，v4 参考）
---

# DESIGN-021：分身数据

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。v1 **只采不学**（product-requirements MUST NOT #8；DEC-049“学习 loop 按路线图后置”）。

## 1. 归属与范围
- 分身数据属于**设备所有者本人**（user）；只记录“用户本人发出的”指令与其任务时间线（DEC-049、REQ-F-029）。
- 存储：只在该用户的**主设备**节点 `twin_events`（architecture §7）；中转不持久化分身数据，只保留审计所需记录。
- 默认不并入智能体完整输出，需要时按 `refs.conversationId/messageId` 引用（DEC-049）。

## 2. 采集点清单
| twin kind（契约枚举） | 产生位置 | 触发（domain event / 本机事件） | text 内容 | refs | durationMs |
|---|---|---|---|---|---|
| `instruction` | 中转 | `message.received` 且作者 = 本人（IM 接收人 `linkedUserId`=U 或 Web 会话用户=U），非指令文本 | 用户原文（≤20,000 字） | conversationId, messageId, agentId（目标） | null |
| `command` | 中转 | 解析出 `/use /clear /stop /stop all /status /history /list /bind /boss /@alias` | 指令原文 | conversationId, messageId | null |
| `approval` | 中转 | `approval.decided` 且 decidedBy = U（含 Y{n}/N{n}、按钮、控制台） | `"{选项 label}：{审批 summary}"` | approvalId, conversationId, agentId | 从 createdAt 到决策的毫秒数（决策用时） |
| `correction` | 中转 | 本人消息满足任一：①引用回复一条 agent 输出；②同会话上一条 final 后 10 min 内、含纠正语（“不对/不是/重新/改成/撤销/别”等词表）（推断，启发式） | 用户原文 | conversationId, messageId（本人消息）, agentId | null |
| `routed` | 中转 | `message.routed`（本人消息被路由） | `"→ {alias}（{mode}，{原因：焦点/@别名/引用溯源}）"` | conversationId, messageId, agentId | null |
| `task_started` | 节点 | 轮次开始（Scheduler 出队，prompt 来源为本人或本人经总控分派） | 任务标题（prompt 前 120 字） | conversationId, agentId, messageId（prompt） | null |
| `task_finished` | 节点 | 轮次结束（stopReason） | `"{完成|失败|取消}：{结果前 200 字}"` | conversationId, agentId, messageId（final） | 轮次耗时 |
| `decision_point` | 节点 | 总控 escalate 被本人处理；会议 decision 事件；导入任务批次确认 | 决策要点（≤500 字） | conversationId, approvalId? | 从上报到决策的毫秒数 |
- 不采集：他人的消息、未授权发送者、智能体完整输出、思考与工具原文、系统告警。
- 总控对话（/boss）中的本人消息按 `instruction` 采集（中转侧，作者=本人）。
- 本机控制台的配置操作（改模型配置等）**不**采集（属于设置，不是工作指令；推断，可在 v4 前复议）。

## 3. 中转 → 节点：twin.capture
```text
TwinCaptureForwarder（中转 audit 模块旁路，architecture §4.1 audit“分身采集的中转侧原始事件转发”）
on(domain event e):
  ev = buildTwinEvent(e)         # 只有作者 = 本人时返回；id = twn_ULID，createdAt = 原事件时间
  if ev == null: return
  dev = primaryDevice(tenant, U)  # devices.is_primary AND revoked_at IS NULL（ux_devices_primary）
  if dev == null: return          # 用户在该组织无节点 → 不采集（中转不存）
  ev.text = secretMask(ev.text)   # DESIGN-019 §8.2，先遮蔽再发送
  node_outbox.append(dev, frame{type:'twin.capture', idempotencyKey:'twin:'+ev.id, payload:{event:ev}})
```
- 时序：与业务帧同一 outbox，设备离线时排队，重连续传（DESIGN-016 §3）。
- 节点：`INSERT OR IGNORE INTO twin_events`（id 主键 + inbox dedupe，双重幂等）。
- 中转留存：twin.capture 帧在 `node_outbox` 中 ack 后 24 h 删除（DESIGN-014 §7）；内容本就是账本中已存在的本人消息/审批，**不新增**中转侧数据暴露（推断）。审计不记录 twin 正文。
- 主设备变更：新事件发往新主设备；历史数据不迁移（用户可导出/导入，§5.4）。

## 4. 节点存储
- 表 `twin_events(id, kind, text, refs JSON, duration_ms, created_at, edited_at, deleted_at)` + `ix_twin_time`（0001）。
- 写入前校验 twin-event.schema.json；`text` > 20,000 字截断并附“…[截断]”。
- 节点本地事件（task_started/finished、decision_point）由 `twin` 模块订阅本机领域事件写入，同一幂等 id 规则（`twn_` ULID 按事件生成一次）。
- 多中转（DEC-048）：0001 无 `relay_link_id`，twin-event 契约 refs 也无该字段（差异 #1）。v1：所有中转连接的本人事件汇入同一表；本机控制台按 `refs.conversationId` 反查会话所属 relay link 做分组显示（会话 id 在节点 `sessions`/`agents.relay_link_id` 可解析，推断）。

## 5. 查看 / 修改 / 删除 / 导出（本机控制台，127.0.0.1:5100，设备所有者）
### 5.1 查看
`GET /local/v1/twin/events`（契约只定义返回数组，未定义查询参数，差异 #2）。约定参数：`kind`（多值）、`from`/`to`（RFC 3339）、`q`（LIKE 子串，≤100 字）、`limit`（1–200，默认 50）、`cursor`（`createdAt:id`）。默认 `deleted_at IS NULL`，按 `created_at DESC`。
### 5.2 修改
`PATCH /local/v1/twin/events/{id}`：只允许改 `text`（durationMs/refs/kind 不可改，保持时间线可信；推断）；写 `edited_at=now`；**不保留原文**（用户修改即意图覆盖）。
### 5.3 删除
`DELETE /local/v1/twin/events/{id}`：默认软删（`deleted_at=now`，30 天后物理删除，DESIGN-014 §7）；`?hard=true` 立即物理删除。批量（按时间段/类型）删除端点契约未列（差异 #3），v1 本机控制台多选逐条调用。
“清空全部分身数据”：本机控制台二次确认（输入“删除”）→ 物理删除全部行 + `VACUUM`（推断）。
### 5.4 导出
`GET /local/v1/twin/export`（契约：导出 JSONL）：约定参数 `from`、`to`、`kind`；输出 `application/x-ndjson`，每行一个 twin-event 对象（不含已删除）；同时写 `exports/twin-{ts}.jsonl`（24 h 清理）。
导入（换设备）：v1 通过整库备份恢复（DESIGN-014 §6.2）实现；单独 JSONL 导入端点不提供（差异 #4）。
### 5.5 暂停采集
本机设置 `twin.capture.enabled`（默认 true）。关闭时节点丢弃到达的 twin.capture（仍 ack）并停止本地事件写入；本机控制台显示“分身采集已暂停”。（REQ-F-029 要求“写入全部”，暂停开关属用户对自身数据的控制权，推断，需用户确认，差异 #5）

## 6. 隐私边界
| 规则 | 依据 |
|---|---|
| 分身数据只在节点；中转不建 twin 表、不做学习 | DEC-049 |
| 公司中转上只保留审计所需记录，不含分身学习结果 | DEC-049 |
| 采集只针对本人；他人消息即使发往本人的智能体也不采集 | DEC-049“由用户本人发出” |
| 不含智能体完整输出与代码；结果只取 ≤200 字摘要 | DEC-049、DEC-037 |
| 密钥在中转转发前与节点写入前各遮蔽一次 | DESIGN-019 §8.2 |
| 分身数据不进入任何外发消息，除非用户在本机主动导出 | REQ-NF-005 |
| 分身数据不进入外部 ACP 智能体上下文（v1） | 推断（防外泄到第三方模型） |
| 用户删除即生效：软删数据不再出现在查询/导出/学习输入中 | REQ-F-029 |

## 7. v4 学习 loop 接口预留（v1 不实现、不建表）
```ts
// apps/node/src/modules/twin/learning.ts（v4）
export interface TwinCorpusReader {               // 只读未删除事件
  read(range: { from: string; to: string }, kinds?: TwinKind[]): AsyncIterable<TwinEvent>;
}
export interface PromptTemplate   { id: string; title: string; template: string; evidence: string[] /* twinEventIds */ }
export interface DecisionPreference { id: string; situation: string; preferred: string; confidence: number; evidence: string[] }
export interface WorkflowTemplate { id: string; name: string; steps: { agentAlias?: string; instruction: string }[]; evidence: string[] }
export interface TwinLearner {
  run(reader: TwinCorpusReader, opts: { modelProfileId: string; budgetPurpose: 'twin_learning' }): Promise<{
    prompts: PromptTemplate[]; preferences: DecisionPreference[]; workflows: WorkflowTemplate[] }>;
}
export interface TwinProfileProvider {           // 总控读取（DESIGN-020 v4）
  topPreferences(situation: string, limit: number): Promise<DecisionPreference[]>;
  suggestTemplates(text: string, limit: number): Promise<PromptTemplate[]>;
}
```
- 约束：学习只用用户模型配置（DEC-044）、计入费用上限（DESIGN-022，purpose 新增 `twin_learning`）；每条产出带 `evidence`（可追溯到 twin 事件，删除事件时级联失效相关产出）；产出只在节点。
- 可选实现：Hindsight `persona:{userId}` bank（delta mental model + 定期全量刷新，V0.0.2/15 H4），按 DESIGN-012 §7 降级规则。
- 预留表名（v4）：`twin_prompts`、`twin_preferences`、`twin_workflows`、`twin_learning_runs`。

## 8. 测试
- 中转：本人 IM 消息 → twin.capture；他人消息/未授权 → 不发；无主设备 → 不发；密钥遮蔽。
- 节点：重复 twin.capture（同 id）只写一行；PATCH 只改 text 且 edited_at 更新；软删后不出现在导出；hard 删除即时。
- 导出 JSONL 每行通过 twin-event schema 校验。
- 关闭采集后 twin.capture 仍 ack 不入库。

## 9. 与契约的差异 / 待办
1. twin-event 无 `relayLinkId`/`tenantId`，node 表亦无对应列 → 多中转数据无法按组织分开导出/删除；建议契约 refs 增 `relayLinkId`，迁移 0002 增列。
2. `GET /local/v1/twin/events` 无分页/过滤参数定义（返回裸数组，不是 page.schema）→ 需补参数与分页结构。
3. 无批量删除端点（按时间段/类型）。
4. 无 JSONL 导入端点（换设备只能整库恢复）。
5. “暂停采集”开关与 REQ-F-029“写入全部”的关系需用户确认。
6. `correction` 的判定为启发式（推断），需在验收中给出样例集；契约 kind 枚举无 `meeting`/`dispatch` 等，当前以 `decision_point`/`routed` 覆盖。
