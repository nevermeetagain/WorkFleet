---
id: DESIGN-022
type: design
title: 模型配置与费用（字段、钥匙串写入流程、provider 薄客户端、usage 与费用公式、日/月上限与时区、超限动作、看板）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-040/043/044/045
  - ADR-012、ADR-013
  - REQ-F-026、REQ-NF-004/010、REQ-C-006、G17
  - packages/contracts/schemas/entities/model-profile.schema.json、schemas/common/money.schema.json
  - packages/contracts/api/node-local.openapi.json（/local/v1/model-profiles*、/usage、/supervisor）
  - packages/contracts/events/domain-events.json（budget.exceeded）
  - packages/contracts/errors/error-codes.json（BUDGET_EXCEEDED、MODEL_PROVIDER_ERROR）
  - packages/contracts/identity/permissions.json（forbiddenPaths #3：中转不得接收或返回模型 Key）
  - database/migrations/node/0001_init.sql（model_profiles、model_usage、supervisor_settings）
---

# DESIGN-022：模型配置与费用

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。模型配置只存在于节点（DEC-044、REQ-C-006）；外部工具（Claude Code、Codex 等）用其自有账号与模型，不受此配置约束、不计入本费用（DEC-044）。

## 1. 模型配置字段（model-profile.schema.json，已确认契约）
| 字段 | 约束 | 说明 / 默认 |
|---|---|---|
| `id` | `mdl_` + ULID | — |
| `name` | 1–80 | 显示名 |
| `provider` | `openai_compatible` \| `anthropic` | ADR-013 |
| `baseUrl` | URI ≤500 | openai_compatible：含版本前缀，如 `https://api.openai.com/v1`、`https://api.deepseek.com/v1`；anthropic：`https://api.anthropic.com`（客户端拼 `/v1/messages`）。要求 `https://`；`http://` 仅允许 `127.0.0.1`/`localhost`（本机模型服务，推断） |
| `model` | 1–120 | 提供方模型名 |
| `keyRef` | ≤128 | 钥匙串条目名 `wf:model-key:{id}`（DESIGN-014 §3.2）；明文 Key 永不出现在契约 |
| `params.temperature` | 0–2 | 默认 0.2（把关调用强制 0，DESIGN-020 §3.3） |
| `params.maxTokens` | 1–1,000,000 | 默认 2,048 |
| `params.timeoutSec` | 5–600 | 默认 30 |
| `params.retries` | 0–5 | 默认 2（DESIGN-018 §2.2） |
| `pricing.inputPerMTokMicros` / `outputPerMTokMicros` | 整数 ≥0 | 每百万 token 价格的**微单位**（ADR-012）：$3/MTok → `3000000` |
| `pricing.currency` | ISO 4217 | 如 `USD`、`CNY` |
| `limits.dailyMicros` / `monthlyMicros` | 整数或 null | null = 不限；币种 = `pricing.currency` |
| `limits.onExceed` | `degrade_to_rules` \| `pause` | 默认 `degrade_to_rules`（DEC-044） |
| `systemPrompt` | 0–20,000 | v1 只支持系统提示词；技能文件上传在 v3（DEC-045） |
| `createdAt` | RFC 3339 | — |
- 使用关系：总控通过 `supervisor_settings.model_profile_id` 指定（`PUT /local/v1/supervisor`）；v1 其他“自有智能体”只有总控（agent.kind=supervisor）。删除被引用的配置 → 409 `CONFLICT`（推断）。
- 乐观锁：`model_profiles.version`；PATCH 需带 version，不匹配 → 409 `CONFLICT`（契约 PATCH 体未声明 version，差异 #1）。

## 2. 校验规则（创建/修改）
| 规则 | 错误 |
|---|---|
| schema 校验 | VALIDATION_FAILED（details.fields） |
| `apiKey` 非空、≤ 4,096 字符、不含换行 | VALIDATION_FAILED |
| `limits` 非 null 时 `monthlyMicros ≥ dailyMicros`（若二者都非 null） | VALIDATION_FAILED |
| `pricing` 为 0 时提示“费用统计将为 0，上限不会触发”（警告，不阻断） | — |

## 3. Key 写入钥匙串流程
```text
POST /local/v1/model-profiles {profile, apiKey}            # 仅 127.0.0.1:5100，本机会话（DESIGN-019 §3.5）
 1 校验（§2）；生成 id；keyRef = 'wf:model-key:' + id
 2 secretStore.set(keyRef, apiKey)                         # DPAPI/Keychain/libsecret/加密文件回退
 3 v = secretStore.get(keyRef); assert v == apiKey          # 回读校验
 4 更新 secrets.bundle（NMK 加密镜像，DESIGN-014 §3.3）
 5 BEGIN; INSERT model_profiles(... key_ref=keyRef ...); COMMIT
 6 失败回滚：任一步失败 → secretStore.delete(keyRef)，返回错误（Key 不入日志）
 7 响应 201：model-profile（含 keyRef，不含 apiKey）
PATCH /{id} {…, apiKey?}：apiKey 存在 → 先写新值到临时 ref（keyRef+':next'）→ 回读 → 原子切换（set keyRef 新值，删 next）→ bundle → 更新行
DELETE /{id}：被引用 → 409；否则 软删行（deleted_at）→ secretStore.delete(keyRef) → bundle；model_usage 保留（看板历史）
POST /{id}/test：读取 Key → 最小请求（§4.4）→ 返回 {latencyMs, usage, ok, errorCode?}；usage 记 purpose='test' 并计入预算（真实费用）
```
- Key 防泄露：内存中 Key 只在发起 HTTP 请求时读取（不缓存超过一次请求；推断，钥匙串读取延迟待实测，若 >50 ms 则进程内缓存 10 min）；pino redact 覆盖 `apiKey`、`authorization`、`x-api-key`；提供方错误响应体写日志前做 DESIGN-019 §8.2 密钥遮蔽；中转任何端点与帧均无 Key 字段（forbiddenPaths #3），E2E grep 验收（REQ-F-026）。

## 4. Provider 薄客户端（ADR-013）
### 4.1 接口
```ts
// apps/node/src/modules/models/provider.ts
export type ChatRole = 'system' | 'user' | 'assistant' | 'tool';
export interface ChatMessage { role: ChatRole; content: string; toolCallId?: string; toolCalls?: ToolCall[] }
export interface ToolDef { name: string; description: string; parameters: object /* JSON Schema */ }
export interface ToolCall { id: string; name: string; arguments: string /* JSON 文本 */ }
export interface Usage { inputTokens: number; outputTokens: number; cacheReadTokens?: number; cacheWriteTokens?: number; estimated: boolean }
export interface ChatRequest {
  system?: string; messages: ChatMessage[]; tools?: ToolDef[];
  temperature?: number; maxTokens: number; responseFormat?: 'text' | 'json';
  signal?: AbortSignal; traceId: string; purpose: UsagePurpose;
}
export interface ChatResponse { content: string; toolCalls: ToolCall[]; stopReason: 'end' | 'max_tokens' | 'tool_use' | 'other'; usage: Usage; latencyMs: number; providerRequestId?: string }
export interface ChatDelta { textDelta?: string; toolCallDelta?: Partial<ToolCall>; usage?: Usage; done?: boolean }
export interface ProviderClient {
  chat(req: ChatRequest): Promise<ChatResponse>;
  chatStream(req: ChatRequest): AsyncIterable<ChatDelta>;
}
export type UsagePurpose = 'gate' | 'chat' | 'meeting' | 'import' | 'test'; // v4 增 'twin_learning'
export function createClient(profile: ModelProfile, secrets: SecretStore, http: HttpClient): ProviderClient;
// 所有调用必须经 ModelGateway.call(profileId, req)：CostGuard.reserve → client → UsageRecorder.settle（§5、§6）
```

### 4.2 映射
| 项 | openai_compatible | anthropic |
|---|---|---|
| 端点 | `POST {baseUrl}/chat/completions` | `POST {baseUrl}/v1/messages` |
| 鉴权头 | `Authorization: Bearer <key>` | `x-api-key: <key>`、`anthropic-version: 2023-06-01` |
| system | messages[0] role=system | 顶层 `system` |
| maxTokens | `max_tokens`（部分提供方改用 `max_completion_tokens`，方言待实测） | `max_tokens`（必填） |
| JSON 输出 | `response_format: {type:"json_object"}`（提供方支持度不一，部分确认；不支持时仅靠提示 + ajv 校验） | 提示 + ajv 校验 |
| 工具 | `tools:[{type:"function", function:{name, description, parameters}}]` → `tool_calls` | `tools:[{name, description, input_schema}]` → `tool_use` 内容块 |
| usage | `usage.prompt_tokens / completion_tokens`；流式需 `stream_options:{include_usage:true}`（OpenAI 文档，兼容方支持度部分确认） | `usage.input_tokens / output_tokens`（+ `cache_creation_input_tokens`、`cache_read_input_tokens`）；流式：`message_start` 带输入、`message_delta` 带输出 |
| 流式 | SSE `data:` 行，`[DONE]` 结束 | SSE 事件 `message_start / content_block_delta / message_delta / message_stop` |
| stopReason | `finish_reason`: stop→end、length→max_tokens、tool_calls→tool_use | `stop_reason`: end_turn→end、max_tokens、tool_use |
- HTTP：Node 22 内置 `fetch`（undici）；超时 `AbortSignal.timeout(timeoutSec*1000)`；不跟随跨域重定向（防 Key 外发到其他主机，推断）。
- 代理：遵守 `HTTPS_PROXY`（节点可能在大陆，模型访问需代理，DEC-040；undici 需显式 `EnvHttpProxyAgent`，待实测）。

### 4.3 错误映射
| 提供方响应 | errorClass | 对外 |
|---|---|---|
| 401/403 | auth | MODEL_PROVIDER_ERROR（ui：“Key 无效或无权限”），不重试，p1 |
| 404（模型名错） | fatal | MODEL_PROVIDER_ERROR，不重试 |
| 429 | rate_limited | 重试（retry-after ≤30 s） |
| 5xx/529/网络/超时 | transient/timeout | 重试 |
| 400 上下文超长 | fatal | 截断后重试 1 次（推断），仍失败 → Fallback |

### 4.4 连通性测试请求
`messages=[{role:'user', content:'ping'}]`，`maxTokens=8`，`temperature=0`，记录延迟与 usage。

## 5. usage 统计与费用估算
### 5.1 记录
每次调用（含失败但已产生 usage 的调用）写一行 `model_usage(model_profile_id, purpose, input_tokens, output_tokens, cost_micros, currency, created_at)`（0001）。
### 5.2 公式（整数运算，BigInt 防溢出）
```text
inputTok  = usage.inputTokens + (usage.cacheReadTokens ?? 0) + (usage.cacheWriteTokens ?? 0)   # 缓存 token 按输入价计（契约无缓存单价，差异 #2）
outputTok = usage.outputTokens
cost_micros = ceil(inputTok × inputPerMTokMicros / 1_000_000) + ceil(outputTok × outputPerMTokMicros / 1_000_000)
```
例：输入 1,500、输出 400，价格 $3 / $15 每 MTok（3,000,000 / 15,000,000 微单位）→ 4,500 + 6,000 = 10,500 微美元 = $0.0105。
- 精度：费用 = 返回 usage × 用户填写单价（ADR-013 风险“部分确认”）；与提供方账单可能存在差异（缓存折扣、批量价、汇率），看板标注“估算”。
- 无 usage（流式中断、提供方不返回）：估算 `inputTok ≈ ceil(输入字符数 / 2)`、`outputTok ≈ ceil(输出字符数 / 2)`（中文保守高估，推断），`Usage.estimated=true`；`model_usage` 无 estimated 列（差异 #3），v1 在 `purpose` 后缀 `:est`（如 `gate:est`）标记（推断；看板按前缀聚合）。

## 6. 日/月上限判定与时区
### 6.1 时区与窗口
- 契约无时区字段（差异 #4）。v1：预算时区 = `kv_settings['models.budgetTz']`，默认取节点 OS 时区（`Intl.DateTimeFormat().resolvedOptions().timeZone`，用户默认 Asia/Shanghai）。
- 日窗口 = 该时区的 `[当日 00:00, 次日 00:00)`；月窗口 = 当月 1 日 00:00 起的自然月；以 IANA 规则转换为 UTC 毫秒边界后查询 `ix_model_usage_time`（DST 当天窗口可能为 23/25 小时，按规则如实）。
- 修改时区：新窗口立即按新时区计算，历史数据不重算（存的是 UTC）。

### 6.2 判定（CostGuard，单进程内存预留 + 库内累计）
```text
reserve(profile, req):
  est = ceil(estInputTok(req) × inPrice / 1e6) + ceil(req.maxTokens × outPrice / 1e6)   # 上界
  for period in [day, month] where limit != null:
     spent = SUM(cost_micros) WHERE profile AND created_at ∈ window(period)   （缓存 60 s，写入时增量更新）
     if spent + reserved[period] + est > limit: return deny(period)
  reserved += est; return ticket
settle(ticket, actualCost): reserved -= est; INSERT model_usage(actualCost)
  if spent_after ≥ limit(period): enterExceeded(profile, period)
  elif spent_after ≥ 80% limit 且本窗口未提醒: p2 “模型费用已达 80%”（推断阈值）
```
- deny 也视为超限（预估会越线即拦截，宁可少用不超支，REQ-NF-010“硬上限”）。
- 例外：`purpose='test'` 在超限时也拒绝（避免绕过上限）。

### 6.3 超限进入与恢复
```text
enterExceeded(profile, period):
  supervisor_settings.degraded_since = now（若该 profile 为总控所用）
  emit budget.exceeded（idempotencyKey = modelProfileId + ':' + period + ':' + windowStart，如 mdl_…:day:2026-10-17）
  通知：p1，经总控会话 agent.output（kind=status, callout warn “总控已降级为规则把关：今日费用 ¥x / 上限 ¥y”）+ 本机控制台横幅（BUDGET_EXCEEDED ui）
  API：总控对话/会议调用 LLM 时返回 BUDGET_EXCEEDED（402）
每分钟检查：若所有非 null 上限的窗口均已回到限额内（新的一天/月）→ degraded_since = NULL，p2 “已恢复模型把关”
用户提高上限 → 立即重新判定
```

### 6.4 超限动作（limits.onExceed）
| 动作 | 把关（不可关闭） | /boss 对话 | 会议 | 总控分派/导入 |
|---|---|---|---|---|
| `degrade_to_rules`（默认） | 规则 + Fallback（DESIGN-020 §3.4） | 回固定文案，可用指令仍工作（工具不经 LLM 的直达指令） | 纪要无模型降级（DESIGN-020 §7.4），继续 | 继续执行已分派任务；新分派可经控制台/指令发起 |
| `pause` | 规则 + Fallback（同上，DEC-018 不可停） | 暂停（提示“已暂停至 {窗口结束}”） | 不开新轮次，进行中轮次结束后停在 `open`，恢复后继续 | 不再创建新任务，已运行的继续到结束 |

## 7. 看板（本机控制台“模型与费用”页；`GET /local/v1/usage`）
契约响应为未约束 object（差异 #5），约定：
```json
{ "tz": "Asia/Shanghai",
  "profiles": [{ "id": "mdl_…", "name": "DeepSeek 总控", "currency": "CNY",
     "day":   { "windowStart": "2026-10-17T00:00:00+08:00", "spentMicros": 1230000, "limitMicros": 5000000, "pct": 24.6 },
     "month": { "windowStart": "2026-10-01T00:00:00+08:00", "spentMicros": 18300000, "limitMicros": 100000000, "pct": 18.3 },
     "calls": 412, "inputTokens": 820000, "outputTokens": 96000, "estimatedCalls": 3,
     "byPurpose": { "gate": 9800000, "chat": 6100000, "meeting": 2300000, "import": 0, "test": 100000 },
     "degraded": false }],
  "series": [{ "date": "2026-10-17", "profileId": "mdl_…", "costMicros": 1230000 }] }
```
- 展示：每配置日/月进度条（≥80% 黄、≥100% 红）、按用途堆叠、近 30 天折线、“估算”标注、降级横幅与恢复时间。
- 多币种不合并汇总（无汇率源，推断）。
- 中转控制台不展示费用（数据不出节点，DEC-044）；仅显示总控“已降级”状态（经总控会话消息得知）。

## 8. 可观测
`wf_model_calls_total{profile,purpose,result}`、`wf_model_latency_ms{profile}`、`wf_model_cost_micros_total{profile,currency}`、`wf_model_budget_pct{profile,period}`、`wf_model_degraded{profile}`。日志只记 profileId、purpose、tokens、cost、latency、traceId，不记 prompt 正文（DESIGN-018 §9）。

## 9. 测试
- 钥匙串：三平台各跑 set/get/delete；回退文件后端；写入中途失败回滚无残留。
- grep 验收：E2E 后中转库/日志/抓包无 Key（REQ-F-026）。
- 客户端：录制两类提供方响应（含流式 usage、工具调用、429 retry-after、401）。
- 费用：公式整数边界（1 token、0 价格、超大 token）；时区 Asia/Shanghai 与 America/New_York DST 日窗口；并发 2 个调用不超支（预留）。
- 超限：degrade_to_rules 与 pause 两种动作的行为矩阵（§6.4）；跨日自动恢复。

## 10. 与契约的差异 / 待办
1. `PATCH /local/v1/model-profiles/{id}` 请求体未声明 `version`（乐观锁）→ 建议补充。
2. `pricing` 无缓存读/写单价 → 缓存 token 只能按输入价计；建议增 `cacheReadPerMTokMicros`、`cacheWritePerMTokMicros`。
3. `model_usage` 无 `estimated`、`trace_id`、`latency_ms` 列 → 0002 补列（v1 用 purpose 后缀 `:est` 过渡）。
4. `limits` 无时区与预警阈值字段 → 建议 `limits.tz`（IANA）与 `limits.warnPct`；另：超限通知需要“总控会话”的 conversationId，节点如何得知该会话（首次 /boss 之前不存在）未定义 → v1 无会话时仅本机横幅 + 节点向中转发 agent.status(error) 由中转生成系统通知（DESIGN-017 §8）。
5. `GET /local/v1/usage` 响应为未约束 object → 需 schema（§7）。
6. `PUT /local/v1/supervisor` 未包含 onExceed 覆盖与 budgetTz 设置 → 由本机设置端点承载（DESIGN-015 差异 #2）。
