---
id: DESIGN-012
type: design
title: 知识库（v1 会话检索；v3 知识库/目录结构图谱/上下文记忆预留；Hindsight 可选接入）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-004/015/016/037/044/049
  - ADR-003、ADR-009
  - REQ-F-019、REQ-NF-002、REQ-NF-007、backlog BL-006
  - packages/contracts/api/relay.openapi.json（GET /api/v1/history/search）
  - packages/contracts/protocol/frames/history.query|history.result.schema.json
  - packages/contracts/commands/im-commands.json（/history）
  - database/migrations/relay/0001_init.sql（messages、messages_fts）
  - database/migrations/node/0001_init.sql（sessions、transcript_index、transcript_fts）
  - V0.0.2/10-参考项目/15-Hindsight技术架构与实现路线.md §13
---

# DESIGN-012：知识库

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。术语按 `00_governance/glossary.md`。
> 范围：v1 只做**会话检索**（DEC-015）；v3 的知识库、目录结构图谱、上下文记忆只定义**接口与数据边界**，v1 不建表、不实现（product-requirements §5 MUST NOT #8）。

## 1. 目标与非目标
| 目标（v1） | 依据 |
|---|---|
| 在中转按关键词（中文可用）检索 IM 侧消息账本 | REQ-F-019、DEC-015、relay `messages_fts` |
| 按 `displayId` / 原生 `nativeSessionId` 精确定位会话 | REQ-F-019、conversation.schema.json |
| 节点在线时按会话取智能体侧转录（两端记录） | REQ-F-019、history.query/result 帧 |
| 本机转录在节点内可检索（本机控制台） | node `transcript_fts` |

非目标（v1）：语义/向量检索、跨会话自动记忆注入、知识库与目录图谱（v3，BL-006）、分身学习（v4+，DEC-049）。

## 2. 两侧检索索引

### 2.1 中转侧：消息账本 FTS
- 表：`messages.plain_text` + `messages_fts`（FTS5，`tokenize='trigram'`，external content，`content_rowid='rowid'`），插入触发器 `messages_ai` 已在 0001 中（已确认，迁移文件）。
- `plain_text` 由应用层在 `conversations.appendMessage()` 写入时从 `body`（小 IR，message-body.schema.json）**确定性抽取**，规则：

| IR 块 | 抽取到 plain_text |
|---|---|
| paragraph / heading / callout | `text` |
| list | `items` 以 `\n` 连接 |
| code | `text`（截前 8 KiB，避免代码稀释索引；推断） |
| table | `columns` 与每行单元格以 ` | ` 连接 |
| kpi | `label: value delta` |
| status_card | `title`（不含 state，避免“running”类噪声） |
| attachment | `name` |
| approval | 不抽取（审批摘要由 approvals.summary 承载） |

  - 规范化：Unicode NFKC；去掉零宽字符；连续空白折叠为一个空格；总长截断 64 KiB（推断：控制索引膨胀）。
  - `tags`（如 `[项目A/z1]`）追加到末尾，便于按项目/别名检索。
- 注意：0001 只有 INSERT 触发器。messages 是 append-only（`messages_no_update` 禁止改 body/plain_text），但**删除**（会话软删 7 天后物理删，见 DESIGN-014 §7）时 FTS 需同步删除 → 需迁移 0002 增加 `AFTER DELETE` 触发器执行 `INSERT INTO messages_fts(messages_fts, rowid, plain_text) VALUES('delete', old.rowid, old.plain_text)`。见文末差异 #1。

### 2.2 节点侧：转录 FTS
- 转录正文在 JSONL 文件（格式见 DESIGN-014 §5），`transcript_index` 每行一条（`conversation_id, generation, line_no, role, plain_text, created_at`），`transcript_fts` 为 external content trigram。
- 0001 未给 `transcript_fts` 建触发器 → v1 由 `sessions` 模块在**同一事务**中写 `transcript_index` 与 `INSERT INTO transcript_fts(rowid, plain_text)`（rowid 取 `transcript_index` 隐式 rowid）。迁移 0002 宜补触发器（差异 #2）。
- 只索引 role ∈ {user, agent}（agent 的最终消息文本与 agent_message_chunk 聚合后文本）；`thought`、工具原始输出**不索引**（体积大、含代码，代码不出本机但也无检索价值；推断）。

### 2.3 trigram 的中文特性（必须处理）
- SQLite FTS5 trigram 分词器按 3 个 Unicode 字符切分，**少于 3 个字符的查询词无法通过 MATCH 命中**；trigram 索引同时可加速 `LIKE '%xyz%'`（模式中连续子串 ≥3 字符时）（已确认：SQLite FTS5 文档 trigram tokenizer 一节；需 SQLite ≥ 3.34，better-sqlite3 内置版本远高于此，TASK 中 `select sqlite_version()` 复核）。
- 查询规划（`QueryPlanner.plan(q)`）：

```text
terms = split(NFKC(q), /\s+/) 去空、去重，最多 8 个
longTerms  = terms.filter(len >= 3)       → FTS 短语："term" （双引号内的 " 转义为 ""）
shortTerms = terms.filter(len in 1..2)    → 追加 AND plain_text LIKE '%term%' ESCAPE '\'
若 longTerms 为空：仅 LIKE 扫描，强制附加时间窗（默认最近 90 天）与 LIMIT，且扫描上限 50,000 行（推断，待实测 p95）
FTS 表达式 = longTerms 以 AND 连接
```
- 中文“2 字词”（如“部署”“告警”）是常见查询 → 走 LIKE 回退，响应时间待实测；若 p95 > 500 ms（推断阈值），v2 评估 ICU/jieba 分词扩展（证据不足：三平台预编译可用性）。

## 3. 检索 API（中转）

### 3.1 端点
`GET /api/v1/history/search`（权限 `history.search`，会话鉴权；契约 relay.openapi.json）。响应体按契约：`{ conversations: Conversation[], messages: Message[], agentTranscript: array|null }`。

契约未声明查询参数（差异 #3），本设计约定以下参数（实现时由 Agent-Contract 补入 openapi，不在本文改契约）：

| 参数 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `q` | string ≤200 | — | 全文关键词；与 displayId/nativeSessionId 三选一（可组合 q + 过滤） |
| `displayId` | string，`^[A-Z]{2,4}-\d{1,6}$` | — | 精确会话 |
| `nativeSessionId` | string ≤256 | — | 智能体原生 session/resume id |
| `projectId` / `agentId` | id | — | 过滤 |
| `generation` | int ≥1 | 全部 | 只看某代 |
| `from` / `to` | RFC 3339 | 近 90 天（仅 LIKE 回退时强制） | 时间窗 |
| `limit` | 1–200 | 50 | 每页条数 |
| `cursor` | string | — | 不透明游标（base64url(`createdAt:rowid`)） |
| `sort` | `recent` \| `relevance` | `recent` | relevance 用 `bm25(messages_fts)` |
| `includeAgentTranscript` | bool | false | 仅在精确定位到单个会话时生效 |

### 3.2 判定与执行顺序
```text
searchHistory(principal, params):
  1 assertPermission(principal, 'history.search')                   # permissions.json
  2 scope = tenant = principal.tenantId; projects = expandScope(membership.projectScope)  # DESIGN-019 §4
  3 if displayId: conv = conversations WHERE tenant_id=? AND display_id=? AND deleted_at IS NULL
    elif nativeSessionId: conv = conversations WHERE native_session_id=? AND tenant_id=?   # ix_conversations_native
       （同一 nativeSessionId 可能出现在多代：返回全部匹配会话，按 updated_at desc）
  4 conv 不在 projects 范围 → 404 NOT_FOUND（不泄露存在性，forbiddenPaths #1）
  5 if q: 执行 §2.3 计划，JOIN conversations 限定 tenant + projects + deleted_at IS NULL
  6 messages 结果附 snippet(messages_fts, 0, '«', '»', '…', 16)（LIKE 回退时由应用层截取 ±40 字符）
  7 if includeAgentTranscript 且结果唯一会话：见 §3.3
```
- 执行位置：FTS/LIKE 查询放 `worker_threads`（ADR-009 风险项），单次查询超时 2 s → 返回已得结果 + 响应头 `X-WorkFleet-Partial: 1`（推断，待契约化）。
- 只读连接：worker 内单独 `readonly` 连接，WAL 下与写者并发（ADR-003）。

### 3.3 两端记录（includeAgentTranscript）
```text
Relay                                            Node
 | 设备离线 → agentTranscript = null，响应正常返回（UI 提示“设备离线，仅显示 IM 侧记录”）
 | history.query{requestId=ULID, conversationId, generation|null, limit<=200} ───▶ |
 |                                                  读 transcript_index（按 line_no 倒序取 limit）
 | ◀─── history.result{requestId, entries:[{lineNo, role, text, createdAt}]} ───── |
 | 10 s 未到 → agentTranscript = null + 审计不记；结果到达后丢弃（requestId 不再等待）
```
- `entries` 在契约中是无约束 `object` 数组（差异 #4）；本设计约定条目形状 `{ lineNo:int, generation:int, role:'user'|'agent'|'tool'|'system', text:string(≤20000), createdAt:RFC3339 }`。
- 节点侧在返回前做**本机过滤**：不返回 `thought` 与工具原始输出，代码块保持文本（用户主动查询属于“用户主动发送”的范围，DEC-037；推断，需用户确认，见差异 #5）。
- 契约 history.query **没有 q 字段**，所以“对智能体转录做全文检索”无法经中转发起 → v1 只能在本机控制台检索转录（§4），差异 #6。

### 3.4 IM 指令 `/history`
`/history [displayId|resumeId] [n]`（im-commands.json，默认 n=10，上限 50 推断）：无参数 → 当前焦点会话最近 n 条；参数匹配 displayId 正则 → 按 displayId；否则按 nativeSessionId。结果按 DESIGN-018 §6 IR 渲染，每条一行 `HH:mm 作者: 摘要(≤120 字)`。

## 4. 本机转录检索（节点）
- 接口（node-local 契约未列，差异 #7；约定）：`GET /local/v1/transcripts/search?q=&conversationId=&limit=&cursor=`，仅 127.0.0.1，权限 = 本机控制台（设备所有者）。
- 规划同 §2.3；结果返回 `{conversationId, generation, lineNo, role, snippet, createdAt}`。
- 多中转隔离（DEC-048）：转录路径与 `agents.relay_link_id` 关联；本机控制台按 relayLink 分组展示，检索默认全部（本机所有者即全部数据所有者）。

## 5. 容量与性能（推断，待实测）
| 项 | 估算 | 依据/验证 |
|---|---|---|
| trigram 索引体积 | ≈ 原文 2–4 倍 | 推断；TASK 用 10 万条中文样本测 |
| FTS MATCH p95（100 万行） | < 100 ms | 推断；`baseline-metrics.md` 记录 |
| LIKE 回退 p95（5 万行扫描） | < 500 ms | 推断 |
| 写入放大 | 每条消息 1 次 FTS 插入 | 0001 触发器 |
触发 ADR-003 迁移条件（单库 > 20 GB）时，优先把 FTS 拆到 `relay-fts.db`（ATTACH），再评估 PostgreSQL。

## 6. v3 预留：知识库、目录结构图谱、上下文记忆

### 6.1 数据边界（硬约束）
| 数据 | 存放 | 可否上中转 | 依据 |
|---|---|---|---|
| 项目设计文档、代码派生的目录结构图谱 | 仅节点 | ❌（代码与工作目录不出本机） | DEC-037、MUST NOT #5 |
| 上下文记忆（从会话提炼的事实/偏好） | 仅节点 | ❌；中转只存用户主动发出的摘要 | DEC-049、DEC-044（需模型，模型只在节点） |
| 知识检索结果被智能体用于回复 | 回复文本按普通 agent.output 经中转 | ✅（等同用户可见输出） | DEC-037 |

### 6.2 端口（v1 只定义类型，不实现）
```ts
// apps/node/src/modules/knowledge/index.ts（v3 才创建模块目录；v1 不建，避免空模块）
export interface KnowledgeScope { relayLinkId: string; projectId: string }
export interface KnowledgeDoc { id: string; scope: KnowledgeScope; kind: 'design_doc'|'dir_graph'|'memory'; title: string; text: string; sourcePath?: string; updatedAt: string }
export interface KnowledgeHit { docId: string; score: number; snippet: string; kind: KnowledgeDoc['kind'] }
export interface KnowledgeStore {
  ingest(doc: KnowledgeDoc): Promise<void>;                       // 幂等：按 id upsert
  remove(docId: string): Promise<void>;
  query(q: string, scope: KnowledgeScope, opts?: { limit?: number; kinds?: KnowledgeDoc['kind'][] }): Promise<KnowledgeHit[]>;
  health(): Promise<'ok'|'degraded'|'down'>;
}
export interface DirGraph { nodes: { id: string; path: string; type: 'dir'|'file'|'module' }[]; edges: { from: string; to: string; type: 'contains'|'imports' }[] }
export interface DirGraphBuilder { build(workdir: string, opts: { respectGitignore: true; maxFiles: number }): Promise<DirGraph> }
export interface ContextMemory {
  recall(scope: KnowledgeScope, q: string, limit: number): Promise<KnowledgeHit[]>;   // 同步路径只读，≤800 ms 超时
  retain(scope: KnowledgeScope, item: { text: string; refs: { conversationId?: string; messageId?: string } }): Promise<void>; // 异步，永不阻塞
}
```
- 实现候选：`SqliteKnowledgeStore`（FTS，零依赖，默认）与 `HindsightKnowledgeStore`（§7）。
- 预留表名（v3 迁移才创建）：`kb_documents`、`kb_graph_nodes`、`kb_graph_edges`、`memory_items`、`kb_retain_outbox`（节点库）。
- 目录图谱构建规则（v3）：遵守 `.gitignore`；跳过 `node_modules`、`.git`、二进制；`maxFiles` 默认 20,000（推断）；只存路径与关系，不存文件内容。
- 总控使用点（v3）：会议议题包与任务分派前 `recall()` 取 ≤5 条（DESIGN-020 §9 预留）。

## 7. Hindsight 可选接入（v3 起；v1 不启用，DEC-015）
| 项 | 设计 | 依据 |
|---|---|---|
| 许可/形态 | MIT；外部服务，不拷贝代码 | V0.0.2/15、DEC-009 |
| 部署位置 | 只在**节点侧**（本机或用户自管主机），因其 retain/reflect 需 LLM，模型只在节点（DEC-044） | DEC-044 |
| 端口 | 5180 API / 5181 UI（DEC-016 预留；HS 自身默认 8888，需配置改端口，待实测） | DEC-016、V0.0.2/15 H1 |
| 依赖 | PostgreSQL + pgvector 或 pg0 嵌入式（部分确认；未在本项目实测） | V0.0.2/15 |
| 接口 | REST `/v1/default/banks/{bank_id}/…`；retain = `POST …/memories`（`async=true`）；recall/reflect 精确路径**待实测**（V0.0.2 只记录到前缀与 retain） | V0.0.2/15 §2.1、L0 |
| bank 命名 | `project:{projectId}`、`persona:{userId}`（v4 分身）、`manager:{deviceId}` | V0.0.2/15 H2 |
| 中文 | HS 默认嵌入/BM25 对 CJK 支持需 PoC（H9），未通过则不启用 | V0.0.2/15 H9 |

降级（DEC-015：不可用时降级、绝不阻断路由）：
```text
状态机 hs: disabled → probing → up ⇄ degraded → down
  probing/up：每 60 s GET 健康检查（路径待实测），超时 2 s
  连续 3 次失败 → down（p2 通知一次，DESIGN-017），之后每 5 min 探测
  recall()：hs≠up → 立即返回 []；up 时超时 800 ms → 返回 [] 并计数
  retain()：写入本地 kb_retain_outbox，后台按 1/s 推送；hs down 时积压，>7 天或 >10,000 条丢弃最旧并记录
  任何 HS 错误都不改变路由、把关分级与投递结果
```

## 8. 可观测
| 指标（/metrics，DESIGN-010/018） | 说明 |
|---|---|
| `wf_history_search_duration_ms{mode="fts|like|exact"}` | 直方图 |
| `wf_history_search_partial_total` | 超时部分返回 |
| `wf_history_transcript_fetch_total{result="ok|offline|timeout"}` | 两端记录 |
| `wf_kb_hindsight_state`（v3） | 0 down / 1 degraded / 2 up |

## 9. 测试要点
- 中文 1/2/3/4 字查询各一例（含“部署”“告警系统”），断言 2 字走 LIKE、≥3 字走 MATCH。
- 跨 tenant / 项目范围外检索返回 404 而非空结果泄露（forbiddenPaths）。
- `/clear` 后旧 generation 可检索（REQ-F-019）。
- 设备离线时 `includeAgentTranscript=true` 返回 `agentTranscript=null`，HTTP 200。
- FakeRelay + FakeNode：history.result 超时 10 s 丢弃。

## 10. 与契约的差异 / 待办（不改契约，提交 Agent-Contract）
1. relay 迁移缺 `messages_fts` 删除触发器（物理删除消息时 FTS 残留）→ 0002 补 `messages_ad`。
2. node 迁移缺 `transcript_fts` 插入/删除触发器 → 0002 补，或保留应用层同事务写入（本文默认）。
3. `GET /api/v1/history/search` 在 openapi 中未声明任何 query 参数（q、displayId、nativeSessionId、limit、cursor、includeAgentTranscript…）→ 需补 `parameters`。
4. `history.result.entries` 为无约束 object → 需定义条目 schema（§3.3 形状）。
5. 经中转返回智能体转录是否属于“用户主动发送”需用户确认（DEC-037 边界）；默认仅在用户显式勾选时取。
6. `history.query` 无 `q` 字段，中转无法对节点转录做全文检索 → 若需要，增加可选 `q`（≤200）。
7. node-local.openapi 无转录检索端点 → 增加 `GET /local/v1/transcripts/search`。
