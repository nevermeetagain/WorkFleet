---
id: DESIGN-020
type: design
title: 总控（把关管线、四分级准则、随时对话、任务分派、会议引擎、导入任务清单、成本控制、可观测）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-005/006/018/019/043/044/045/049/056
  - ADR-013
  - REQ-F-022/023/024/025/026、REQ-NF-010、G8/G22/G24
  - architecture §4.2/§6.2/§7
  - packages/contracts/schemas/entities/agent.schema.json（kind=supervisor）、meeting.schema.json、approval.schema.json（kind=supervisor_escalation/major_decision）、model-profile.schema.json
  - packages/contracts/protocol/frames/agent.output.schema.json（supervisorVerdict）
  - packages/contracts/commands/im-commands.json（/boss）
  - packages/contracts/events/domain-events.json（supervisor.verdict、meeting.round_closed、budget.exceeded）
  - packages/contracts/api/node-local.openapi.json（/local/v1/supervisor、/supervisor/import-tasks）
  - database/migrations/node/0001_init.sql（supervisor_settings/verdicts/tasks、meetings、meeting_events）
  - docs/WorkFleet-V0.0.4/05_execution/task-template.md
  - V0.0.2/10-参考项目/16-BettaFish §M2/M3（HostPolicy、四段式纪要）、V0.0.2/30-协议与端点/04 §5
---

# DESIGN-020：总控

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。总控 = 本机节点上的自有智能体（`agent.kind='supervisor'`），只调用用户自管的模型配置（DEC-044、ADR-013）。

## 1. 架构
```text
                       ┌────────────────────── node: supervisor 模块 ──────────────────────┐
 ACP 智能体轮次输出 ──▶ │ Gatekeeper 把关管线：Rules → LLM → Fallback → Verdict 执行器     │──▶ agent.output(supervisorVerdict) → relay
 approval.request ────▶ │   （审批只做标注与升级，不代批）                                  │──▶ approval.request
 /boss 对话 ──────────▶ │ ChatChannel（独立会话、独立 LLM 槽位）── Tools ─┐                 │
                       │ Dispatcher（supervisor_tasks DAG）◀──────────────┤                 │
                       │ MeetingEngine（meetings / meeting_events）◀──────┤                 │
                       │ TaskImporter（task-template 解析）◀───────────────┘                 │
                       │ CostGuard（DESIGN-022 预算判定）  LlmClient（DESIGN-022 薄客户端）  │
                       └────────────────────────────────────────────────────────────────────┘
```
- 运行位置：用户的**主设备**（`devices.is_primary`，G22）；每条中转连接一个独立总控实例（DEC-048 隔离），共享本机模型配置。
- 中转侧：总控只是一个普通智能体（别名默认 `boss`，可改），走同一路由内核与账本（DEC-043）。

## 2. 把关范围与“不可关闭”的落实（DEC-018、REQ-F-022）
- 被把关对象：属于 `mode=supervisor` 绑定的源智能体的**每一条**外发候选（final / error / status / digest）。
- 节点如何知道哪些智能体受控：契约没有中转→节点的绑定同步帧（差异 #2）。v1：
  1. 本机设置 `supervisor.gatedAgentIds`（本机控制台“总控管辖”页维护；创建 supervisor 绑定时 Web 控制台提示“请在本机确认管辖”）；
  2. **中转兜底强制**：对 `mode=supervisor` 绑定的源智能体，中转拒绝投递 `supervisorVerdict == null` 的 `agent.output`（入账本但 delivery=`suppressed`，审计 `supervisor.verdict_missing`，p1 提醒本机配置）——保证“不可关闭”不依赖节点配置正确。
- 审批请求（approval.request）**不被丢弃或代批**：总控只可附加说明（summary 前缀“总控意见：…”）与升级优先级；决策只能由人（DESIGN-019 §4）。

## 3. 把关管线
```text
gate(c: Candidate{agentId, conversationId, kind, priority, text, origin:'user'|'supervisor_task'|'meeting', taskId?}):
  1 预处理：text 归一化；hash = sha256(agentId + normalize(text))
  2 内置规则（不可删除，按序，首个命中即决）
       R1 kind=error                                   → escalate, p1
       R2 text 为空或仅空白/仅确认语（≤ 8 字且命中“好的/收到/开始/OK”词表） → drop
       R3 同 hash 在 10 min 内已出现                     → drop（理由“重复”）
       R4 kind=status                                  → merge（mergeKey=conversationId）
       R5 输出命中密钥扫描（DESIGN-019 §8.2）              → escalate, p1（正文已遮蔽）
  3 用户规则（supervisor_settings.rules，按序，`stop:true` 时命中即决；schema 见 §3.2）
  4 若未决 且 CostGuard.allow(purpose='gate') 且 模型熔断未开：LLM 分级（§3.3）
  5 若仍未决（降级/超时/非法输出）：Fallback 表（§3.4），reason 前缀“规则降级”
  6 记录 supervisor_verdicts(message_id, conversation_id, verdict, reason, by_rules, created_at)；发 domain event supervisor.verdict
  7 执行 verdict（§3.5）
```

### 3.1 时延
规则阶段 < 5 ms；LLM 阶段超时 15 s（推断；超时即 Fallback）；把关不阻塞智能体执行（智能体轮次已结束或在继续，候选在独立队列）。

### 3.2 用户规则 schema（存 `supervisor_settings.rules`，经 `PUT /local/v1/supervisor`；契约为未约束 array，差异 #3）
```json
{ "id": "r-weekly", "when": { "kind": ["final"], "agentAlias": ["z1"], "textRegex": "周报", "minLength": 0, "maxLength": 100000, "origin": ["user"] },
  "then": { "verdict": "reply", "priority": "p2" }, "stop": true }
```
`textRegex` 用 RE2 语义子集（防 ReDoS；实现选 `re2` 包或限制长度 ≤200 + 超时，待 TASK 定）。

### 3.3 LLM 分级
- 请求：`system` = 固定模板（四分级定义 + §4 准则 + 输出 JSON 约定）+ 用户 `systemPrompt`；`user` = `<<<UNTRUSTED source=agent:{alias}>>>{text 截断}<<<END>>>` + 上下文元数据（任务标题、发起人类型、最近 3 条同会话裁决）。
- 截断：text > 4,000 字 → 头 2,000 + 尾 1,000 + “[中间省略 N 字]”。
- 参数：`temperature=0`，`maxTokens=300`（覆盖 profile 值的上限），JSON 输出。
- 输出 schema（ajv 校验，失败视为非法 → Fallback）：
```json
{ "verdict": "reply|merge|escalate|drop", "reason": "≤200 字", "priority": "p0|p1|p2|p3", "summary": "≤500 字，可选；merge/escalate 时用于摘要" }
```
- 模型不得改写正文：`reply` 发原文；`summary` 只用于 merge 摘要与 escalate 说明（防模型篡改结果，推断）。

### 3.4 Fallback 表（无模型 / 超预算 `degrade_to_rules` / 熔断 / 超时）
| kind | verdict | priority |
|---|---|---|
| final | reply | 原值 |
| digest | reply | 原值 |
| status | merge | p3 |
| error | escalate | p1 |
超限动作为 `pause` 时（model-profile.limits.onExceed）：把关仍按 Fallback 执行（不可停止把关，DEC-018），只暂停 /boss 对话与会议的 LLM 调用（DESIGN-022 §6）。

### 3.5 Verdict 执行
| verdict | 动作 |
|---|---|
| reply | origin=user → `agent.output{supervisorVerdict:'reply'}` 到原会话（发起人）；origin=supervisor_task → 不外发，结果交 Dispatcher 推进 DAG |
| merge | 进入 MergeBuffer（key=mergeKey 或 taskId）；flush 时机：所属任务结束、60 min、缓冲 ≥ 20 条 → 一条 `kind=digest, supervisorVerdict:'merge'` 发往原会话（或总控会话） |
| escalate | `agent.output{supervisorVerdict:'escalate', priority≥p1}` 发往**总控会话**（用户与总控的对话，即“上报给用户”）；若需要人做决定（LLM summary 含“需决定”或 R1 且任务为关键路径）→ `approval.request{kind:'supervisor_escalation', options:[继续/重试/取消/自定义]}` |
| drop | 不外发；本机记录可在本机控制台“把关记录”查看；每日在 merge 摘要中附“今日丢弃 N 条” |

## 4. 四分级判定准则与示例
| 分级 | 准则（满足任一） | 示例 |
|---|---|---|
| reply 直回 | 用户亲自发起的任务的正常完成；内容完整、无错误、无需决定；不含敏感信息 | 用户 `@cc1 修一下 lint` → cc1 输出“已修复 12 处，测试通过” |
| merge 合并 | 过程/进度；总控分派子任务的中间结果；多个同类低价值成功；同一任务的连续状态 | 会议中 3 个子任务各自“完成单测”；z1 每 2 s 的进度状态 |
| escalate 上报 | 失败、阻塞、需要决定（方案取舍、资源申请、超范围改动）；智能体之间结论冲突；涉及高风险操作；用户规则标注的关键词（如“发布”“删除”） | codex1 报“迁移脚本与 z1 的 schema 冲突”；智能体问“是否升级大版本依赖？” |
| drop 丢弃 | 空/纯确认语；重复；对 prompt 的复述；智能体自述“我将开始…”且无信息量 | “好的，我开始处理。” |

## 5. 随时对话（REQ-F-023：不打断执行、不丢消息）
- 入口：IM `/boss <text>`（im-commands.json，权限 agent.prompt）或 Web 打开总控会话。中转将其路由为发往总控智能体的 `agent.prompt`（独立会话，按发送人分会话，G25）。
- 隔离：
  - 总控对话**不进入任何执行智能体的 prompt_queue**；
  - LLM 并发槽位：总共 2（DESIGN-015 §2）：槽 A 专供 ChatChannel，槽 B 供 Gatekeeper/会议；把关积压不会阻塞对话；
  - 对话期间执行中的轮次照常运行，其输出照常进入把关。
- 上下文组装（每次对话请求）：system 模板 + 用户 systemPrompt；最近 20 条对话；**任务快照**（JSON：运行中/排队/待审批的会话、supervisor_tasks 状态、最近 10 条 escalate 摘要），快照 ≤ 4,000 token（推断）。
- 工具（函数调用，ADR-013 薄客户端支持工具调用）：

| 工具 | 参数 | 效果 | 权限 |
|---|---|---|---|
| `list_agents` | — | 本中转连接下本设备智能体与状态 | 读 |
| `get_status` | `alias?` | 智能体/任务状态 | 读 |
| `dispatch_task` | `alias, title, prompt, dependsOn?[]` | 新建 supervisor_tasks 并分派（§6） | 等同用户 `agent.prompt` |
| `cancel_task` | `taskId` | 取消任务（运行中 → session/cancel） | 等同 `agent.stop` |
| `open_meeting` | `topic, participants[], maxRounds?, roundTimeoutSec?` | §7 | 等同 `agent.prompt` |
| `import_tasks` | `dir, dryRun` | §8 | 同本机 API |
- 工具调用由节点执行前做参数校验与权限检查（发起人 = 本条 prompt 的 `from.userId` 的权限，由中转已校验 agent.prompt；分派到 write 智能体仍受写租约约束）。工具结果作为 tool 消息回填，循环 ≤ 5 次（防失控，推断）。
- 无模型/超预算时：对话回复固定文案“总控模型不可用（已降级为规则把关），可用指令：/status、/list …”（BUDGET_EXCEEDED ui）。

## 6. 任务分派（Dispatcher）
- 状态机（`supervisor_tasks.state`）：
```text
pending ──依赖全部 done──▶ ready ──Scheduler 接受──▶ dispatched ──轮次开始──▶ running
running ──final(reply/merge)──▶ done
running ──error / AGENT_UNAVAILABLE──▶ failed ──用户“重试”──▶ ready
任意 ──cancel_task / 急停──▶ cancelled
依赖任一 failed/cancelled ──▶ pending 保持并 escalate “依赖失败”
```
- 分派会话：v1 **只能分派给同一设备、同一中转连接下的智能体**（节点无法在中转创建会话，契约缺帧，差异 #1）。节点为每个任务创建本机内部会话（`sessions.conversation_id` = 节点生成的 `cnv_` ULID，不注册到中转），输出经把关后以**总控会话**的 `agent.output` 外发（reply→结果进 DAG；escalate/merge→总控会话）。完整转录留在本机（DEC-037）。
- 并发：遵守 DESIGN-015 调度上限与写租约；同一智能体同时最多 1 个总控任务（推断，避免上下文混杂）。
- 每次分派写 twin_event `routed`（DESIGN-021）。

## 7. 会议引擎（REQ-F-024、DEC-019）
### 7.1 状态机（`meetings.status` 契约枚举 open/summarizing/decided/cancelled；轮内子状态在内存 + meeting_events）
```text
open:
  round r 开始 → event round_opened(r) → 向每位参与者发议题包 P_r(agent)
  collecting：收到参与者本轮 final → event speech(r, agent)
     全员提交 或 roundTimeoutSec 到期（policy=all_or_timeout）→ event round_closed(r)（缺席者记入 content.missing）
     → domain event meeting.round_closed（key meetingId+round）
  host：生成纪要 M_r（四段式，§7.2）→ event minutes(r)
     若 M_r.needsUserDecision 或 r == maxRounds 或 M_r.consensusReached → summarizing
     否则 r+1，回到 open
summarizing:
  生成决策草案（任务 DAG + 分工）→ 若需用户拍板：approval.request{kind:'major_decision'}（总控会话）
  用户批准/自动（无需拍板）→ event decision → decided → Dispatcher 创建 supervisor_tasks(source='meeting')
cancelled: 用户取消 / 急停 / 全部参与者 unavailable
```
- 参数：`roundTimeoutSec` 30–3600、`maxRounds` 1–10（meeting.schema.json）；默认 600 s / 3 轮（推断）。
- 参与者会话：每位参与者每个会议一个本机内部会话（与 §6 相同机制），议题包作为 prompt。
- 会议中禁止写：参与者会话中的 `request_permission` 若 risk ≥ medium → 节点自动回 reject（不打扰用户），并在发言中注明“会议阶段只讨论”（推断，防会议中改代码）。
- 主持锁：同一会议同一时刻只有一个 host 生成（单写者），不阻塞其他会议（V0.0.2/16）。

### 7.2 纪要四段式（BF MeetingDigest 模板，clean-room，V0.0.2/16）
```json
{ "round": 2,
  "consensus":   ["需求与共识 …"],
  "divergence":  [{"topic":"…","positions":{"z1":"…","cc1":"…"}}],
  "risks":       ["风险/依赖/资源需求 …"],
  "openItems":   [{"question":"…","assigneeSuggestion":"cc1","needsUserDecision":true}],
  "consensusReached": false, "needsUserDecision": true }
```
人读渲染：四个 heading（需求与共识 / 方案对比与分歧 / 风险依赖资源 / 待决与分工）+ list/table（DESIGN-018 §6）。
### 7.3 议题包定制（纪要注入下一轮）
`P_{r+1}(agent) = topic + M_r.consensus + 与该 agent 相关的 divergence 条目 + 指向该 agent 的 openItems`（只发相关分歧，控制上下文，V0.0.2/16 M3）。
### 7.4 无模型降级
纪要 = 按参与者拼接发言（每人截 1,000 字）+ “未生成结构化纪要（模型不可用）”；`needsUserDecision=true`，决策必须由用户在总控会话中给出。
### 7.5 回放
`meeting_events` 按 `(meeting_id, round, id)` 有序，本机控制台“会议”页按时间线回放五类事件（round_opened/speech/minutes/decision/round_closed，0001 CHECK）；对外发送的只有纪要与决策摘要（总控会话 agent.output，kind=digest）。

## 8. 导入任务清单（REQ-F-025、G24）
- 入口：`POST /local/v1/supervisor/import-tasks{dir, dryRun}` 或总控工具 `import_tasks`。
- 文件：`dir` 下（不递归，推断）匹配 `TASK-*.md`；`dir` 必须位于某个已登记智能体的 `workdir` 之内（防读任意路径，推断）。
- 解析（按 `05_execution/task-template.md`）：
  1. 第一个 ```yaml 代码块 → `id`（`^TASK-\d{3,}$`）、`slice`、`status`、`owner`（`Agent-<Role>`）、`tier`、`size`；
  2. 按二级标题 `## {n}. {名称}` 切分章节，取：`2. 目标`、`3. 输入`、`4. 输出`、`5. Execution Steps`、`6. 验收标准`、`7. 验证命令`、`9. 允许修改`、`10. 禁止修改`、`11. 依赖与阻塞`（解析行 `Depends on：TASK-001, TASK-002`，全角/半角冒号与逗号均可）；
  3. 只导入 `status ∈ {todo, ready}`；`done/cancelled` 跳过；`blocked` 列出但不分派。
- 分配：`owner` → 智能体别名映射表 `supervisor_settings.rules` 之外的 `ownerMap`（存 kv_settings `supervisor.ownerMap`，如 `{"Agent-Relay":"cc1","Agent-Node":"codex1"}`）；未映射的任务在 dryRun 结果中列为 `unassigned`，需用户补映射。
- 校验：id 唯一；依赖存在（不存在 → `unresolvedDeps`）；DAG 无环（Kahn 拓扑排序，环 → 整批拒绝 `VALIDATION_FAILED`，details 列出环）。
- dryRun 响应（契约为未约束 object，差异 #4）：`{ tasks:[{id,title,assignee,dependsOn,status}], order:[[批次1 ids],[批次2]…], unassigned:[], unresolvedDeps:[], skipped:[] }`。
- 执行：写 `supervisor_tasks(source='import', spec=章节 JSON)`，交 Dispatcher；prompt = 目标 + 输入 + 输出 + 步骤 + 验收 + 验证命令 + 允许/禁止修改，整体包在 UNTRUSTED 标记内（DESIGN-019 §6.2）。不回写任务卡文件（v1 只在本机记录完成状态）。

## 9. 成本控制（REQ-NF-010、DEC-043）
| 手段 | 设计 |
|---|---|
| 规则优先 | R1–R5 + 用户规则先决，status 类默认不进 LLM |
| 预算前置 | 每次 LLM 调用前 `CostGuard.allow(purpose)`（DESIGN-022 §5），超限即降级 |
| 估算上限 | 请求前按 `maxTokens` 与输入 token 估算（字符数/2 作为中文保守估计，推断）预估费用；若本次可能使日上限超出 → 视为超限 |
| 截断 | 把关输入 ≤ 3,000 字；对话快照 ≤ 4,000 token；会议发言每人 ≤ 2,000 字 |
| 缓存 | 同 hash 10 min 内复用上次裁决（R3 已 drop；非重复但同模板文本可复用，推断） |
| 槽位 | LLM 并发 2 |
| v3 预留 | 知识检索 `ContextMemory.recall()` 结果 ≤ 5 条注入（DESIGN-012 §6） |

## 10. 可观测
| 指标（节点 /metrics 5104） | 说明 |
|---|---|
| `wf_sup_verdict_total{verdict, by="rules|llm|fallback"}` | 分级分布 |
| `wf_sup_gate_latency_ms{stage}` | 规则/LLM 时延 |
| `wf_sup_llm_calls_total{purpose="gate|chat|meeting|import", result}` | 调用与失败 |
| `wf_sup_degraded`（0/1） | `supervisor_settings.degraded_since` 非空 |
| `wf_sup_tasks{state}` | 任务状态 |
| `wf_meeting_rounds_total{result="complete|timeout"}` | 会议轮次 |
- 本机控制台：把关记录（verdict、reason、by_rules、原文预览）、降级横幅（BUDGET_EXCEEDED）、任务 DAG、会议回放。
- 日志带 traceId（继承触发该候选的 prompt traceId）。

## 11. 测试
- 规则：R1–R5 各一例；用户规则顺序与 stop；ReDoS 正则被拒。
- LLM：桩模型返回合法/非法/超时 → reply/Fallback；预算超限 → Fallback 且不调用模型。
- 不可关闭：节点未配置 gatedAgentIds 时，中转对 supervisor 绑定输出 `suppressed` 并告警。
- 对话不打断：执行中轮次 + 并发 /boss，断言执行轮次无 cancel、消息无丢失（REQ-F-023）。
- 会议：3 参与者 × 2 轮（桩 LLM），一人超时 → round_closed 标注缺席；纪要 needsUserDecision → major_decision 审批（BF M2 测试思路）。
- 导入：环检测、未映射 owner、blocked 跳过。

## 12. 与契约的差异 / 待办
1. 无节点→中转“新建会话/分派”帧（如 `conversation.open`/`supervisor.dispatch`）→ v1 分派仅限同设备同中转连接，子任务会话不进中转账本；跨设备分派与 Web 可见子会话需契约补充。
2. 无中转→节点的绑定/模式同步帧 → 节点不知道哪些智能体处于 supervisor 绑定；v1 本机配置 + 中转强制 suppress 兜底。
3. `PUT /local/v1/supervisor` 的 `rules` 为未约束 array → 需 rule schema（§3.2），并补 `ownerMap`、`gatedAgentIds` 字段。
4. `import-tasks` 响应为未约束 object → 需 dryRun 结果 schema（§8）。
5. meeting 实体无当前轮次、纪要结构字段；无会议相关帧（Web 端无法实时看会议）→ v1 仅经总控会话 digest 呈现。
6. audit-entry `actor.kind` 无 `supervisor`（DESIGN-018 差异 #4）。
