# TASK-086：Webhook 输入（127.0.0.1:5102，HMAC 签名）

```yaml
id: TASK-086
slice: S4
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: sonnect
size: 小
title: "Webhook 输入（127.0.0.1:5102，HMAC 签名）"
dependsOn: ["021"]
blocks: ["087"]
reqs: "REQ-F-008"
allowedPaths: ["apps/node/src/modules/agents/infrastructure/webhook/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S4（可演示：13 个 ACP 智能体 + Coze + Webhook 冒烟矩阵全部有结论）
- 来源需求：REQ-F-008
- 来源方案：ADR-007、ADR-001（节点端口只绑 127.0.0.1）；DEC-052/055；REQ-C-003（端口 5100–5200）

## 2. 目标
节点在 127.0.0.1:5102 提供 `POST /hooks/{hookId}`：用 HMAC-SHA256 校验 `X-WorkFleet-Signature`，把通过校验的消息作为该 webhook 智能体的输出（可带优先级、字段、barrierId）交给中转按绑定投递。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §3（5102 Webhook，只绑 127.0.0.1）、§4.2 agents（Webhook 输入）
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-008-非ACP输入-Coze与Webhook.md`
  - `docs/WorkFleet-V0.0.4/02_requirements/non-functional/REQ-NF-004-安全.md`
- 契约：
  - `packages/contracts/api/node-local.openapi.json`：`POST /hooks/{hookId}`（x-auth: hmac；body {title?, text, priority?, fields?, barrierId?}，additionalProperties:false；202）
  - `packages/contracts/adapters/input-adapters.v1.json`：webhook 行（family webhook、auth none、configSchema secretRef（必填）、defaultPriority p0–p3）
  - `packages/contracts/protocol/frames/agent.output.schema.json`（kind/priority/body）与 `barrier.submit.schema.json`（barrierId+agentId+messageId）
  - `packages/contracts/schemas/common/error.schema.json`；`errors/error-codes.json`：VALIDATION_FAILED、UNAUTHENTICATED、NOT_FOUND、PAYLOAD_TOO_LARGE、RATE_LIMITED
  - `database/migrations/node/0001_init.sql`：`agents`（config 中 secretRef、defaultPriority）、`relay_outbox`
- 前置任务：TASK-021
- 前置状态：TASK-021 已合并；节点进程可监听附加端口

## 4. 输出
- `apps/node/src/modules/agents/infrastructure/webhook/`：HTTP 监听（127.0.0.1:5102）、HMAC 校验、body 校验、输出帧组装
- `apps/node/src/modules/agents/infrastructure/webhook/__tests__/`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-086/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 启动监听：只绑定 127.0.0.1:5102（端口可配但限制在 5100–5200），拒绝其他地址绑定；body 上限 1 MiB（超出 413 PAYLOAD_TOO_LARGE）。
2. [ ] hookId → 查找 kind=webhook 的智能体（按 relay link 命名空间）；不存在 → 404 NOT_FOUND。
3. [ ] HMAC：用 secretRef 取出密钥，对原始字节计算 sha256，`timingSafeEqual` 比较 `sha256=<hex>`；缺失或不匹配 → 401 UNAUTHENTICATED。
4. [ ] 用 contracts 生成的校验器校验 body；不合法 → 400 VALIDATION_FAILED。
5. [ ] 组装 agent.output（kind=final，priority = body.priority ?? defaultPriority ?? p2，body 由 title/text/fields 组成），以 hookId+body 哈希+分钟桶生成幂等键写入 relay_outbox；带 barrierId 时另发 barrier.submit。
6. [ ] 返回 202；中转不可达时仍 202（已入本地 outbox 续传）。
7. [ ] 写测试：签名正确/错误/缺失、非法 body、超大 body、barrierId 分支、重复请求去重、只绑回环地址。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 正确签名返回 202 并在 relay_outbox 产生 1 条 agent.output，帧通过 envelope.schema.json 校验
- [ ] 错误或缺失签名返回 401，body 不合法返回 400，未知 hookId 返回 404，均符合 error.schema.json
- [ ] 带 barrierId 的请求额外产生 barrier.submit 帧
- [ ] 监听地址只为 127.0.0.1（测试断言从非回环地址连接失败）
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/node exec vitest run src/modules/agents/infrastructure/webhook
# 手动签名示例（本机节点运行时）
BODY='{"text":"hello"}'; SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$WF_HOOK_SECRET" -hex | sed 's/^.* //')
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:5102/hooks/$WF_HOOK_ID -H 'Content-Type: application/json' -H "X-WorkFleet-Signature: sha256=$SIG" -d "$BODY"
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/node/src/modules/agents/infrastructure/webhook/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-086/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-086/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/node/src/modules/agents/infrastructure/webhook/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-086/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/node/src/modules/agents/** 中 infrastructure/webhook/ 以外的部分
- apps/relay/**（投递由中转既有 routing/delivery 完成）

## 11. 依赖与阻塞
- Depends on：TASK-021
- Blocks：TASK-087
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 契约没有“节点主动发起会话”的帧：webhook 消息需要 conversationId，若中转未为 webhook 智能体预建会话，停止并请求 Agent-Contract/Relay 裁决
  - secretRef 对应的密钥存储（钥匙串）不可用（依赖 TASK-161 的问题同 TASK-085）
  - 需要防重放时间戳头（契约未定义）

## 12. 建议执行档位
sonnect　理由：单端点 + HMAC 校验，规则明确、可完全自动化测试。

## 13. 升级条件
- 需要新增帧或请求头（防重放、会话创建）→ 升 opus 出 ADR 并转 Agent-Contract
- 安全审查发现 SSRF/本机暴露风险 → 升 opus

## 14. 预估规模
小(<0.5d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联。
- 安全风险：契约签名只覆盖 body，无时间戳，存在重放可能；本任务以幂等键缓解，登记跟进项。
- 假设：webhook 智能体在 agents 表中有 workdir 必填值（agent.schema minLength 1），对 webhook 无意义，填占位值（推断）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：缺少 webhook 专用错误码（签名错误复用 UNAUTHENTICATED）与防重放头
  - Agent-Contract：缺少节点发起新会话的帧语义（webhook/Coze 主动消息需要 conversationId）

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-086/
- 验证者结论：
- 遗留问题 / 跟进项编号：
