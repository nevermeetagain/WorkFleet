# TASK-085：Coze HTTP 适配器

```yaml
id: TASK-085
slice: S4
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: sonnect
size: 中
title: "Coze HTTP 适配器"
dependsOn: ["021"]
blocks: ["087"]
reqs: "REQ-F-008"
allowedPaths: ["apps/node/src/modules/agents/infrastructure/coze/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S4（可演示：13 个 ACP 智能体 + Coze + Webhook 冒烟矩阵全部有结论）
- 来源需求：REQ-F-008
- 来源方案：ADR-007（非 ACP 用专用适配器）、ADR-009、ADR-013（模型调用只在本机）；DEC-052/055

## 2. 目标
在节点实现 Coze HTTP 输入适配器：经 `POST /v3/chat`（SSE）与 Coze 智能体多轮对话，`/clear` 映射为清空会话上下文，同一 conversation 串行执行，Key 只经 keyRef 从本机安全存储读取。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.2/30-协议与端点/02-输入端接入矩阵.md` §6（Coze：/v3/chat、SSE、conversation_id、/v1/conversations/{id}/clear、4016、submit_tool_outputs、速率限制证据不足）
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.2 agents（Coze HTTP 适配器）、§7（模型 Key 不出节点）
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-008-非ACP输入-Coze与Webhook.md`
- 契约：
  - `packages/contracts/adapters/input-adapters.v1.json`：coze 行（family coze_http、source builtin、auth env_key、supportsLoadSession=true、supportsWriteTools=false；configSchema botId、apiBase ∈ {https://api.coze.cn, https://api.coze.com}、keyRef）
  - `packages/contracts/adapters/input-adapter-spec.schema.json`
  - `packages/contracts/schemas/entities/agent.schema.json`（kind=coze）
  - `packages/contracts/protocol/frames/agent.prompt|agent.output|agent.clear|agent.cancel|agent.status`
  - `packages/contracts/errors/error-codes.json`：AGENT_UNAVAILABLE、RATE_LIMITED、MODEL_PROVIDER_ERROR（上游 5xx 映射，推断）
  - `database/migrations/node/0001_init.sql`：`sessions`（native_session_id 存 Coze conversation_id）、`prompt_queue`（每会话串行）
- 前置任务：TASK-021
- 前置状态：TASK-021 Host 已合并（非 ACP 适配器可按同一 InputAdapter 端口注册）

## 4. 输出
- `apps/node/src/modules/agents/infrastructure/coze/`：CozeAdapter（HTTP 客户端、SSE 解析、会话映射、clear、错误映射）
- `apps/node/src/modules/agents/infrastructure/coze/__fixtures__/`：录制的 SSE 响应（脱敏）
- `apps/node/src/modules/agents/infrastructure/coze/__tests__/`：基于本地 HTTP mock 的回放测试
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-085/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 实现配置校验：按契约 configSchema 校验 botId/apiBase/keyRef；apiBase 只允许两个枚举值。
2. [ ] 实现 Key 读取：只通过节点安全存储按 keyRef 取 PAT，请求日志中对 Authorization 头脱敏。
3. [ ] 实现 prompt：`POST {apiBase}/v3/chat?conversation_id=...`，`stream=true`、`auto_save_history=true`，解析 SSE `conversation.message.delta` 聚合，完成后发 agent.output(final)；首次对话无 conversation_id 时把返回的 id 写入 sessions.native_session_id。
4. [ ] 实现串行：同一 conversation 依赖 prompt_queue 串行；若仍收到 4016（同会话已有进行中 chat）→ 退避重试并记录。
5. [ ] 实现 /clear：调用 `/v1/conversations/{conversation_id}/clear`，generation+1；实现 cancel：接口未核实（证据不足），v1 以本地中止 SSE 读取实现并在证据中注明。
6. [ ] 错误映射：401/403 → AGENT_UNAVAILABLE（附“检查 Coze Key”提示）；429 → RATE_LIMITED；5xx/网络 → 可重试错误。
7. [ ] 用本地 HTTP mock 回放录制的 SSE 完成单测：多轮、clear、4016 重试、401、断流。
8. [ ] 真机冒烟一次（人工验收项），结论与脱敏响应写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 回放测试：两轮对话复用同一 conversation_id，第二轮请求带上该 id
- [ ] /clear 发出 clear 请求且 generation+1；4016 被退避重试后成功
- [ ] 请求日志与 node.db 中 grep 不到 PAT 明文
- [ ] 401 → agent.status=error 且错误码 AGENT_UNAVAILABLE
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/node exec vitest run src/modules/agents/infrastructure/coze
pnpm exec gitleaks detect --no-git --source apps/node/src/modules/agents/infrastructure/coze --redact
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/node/src/modules/agents/infrastructure/coze/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-085/)' || echo 'SCOPE OK'
```

**人工验收项（需要真实凭据，不进 CI）**
- 前提：执行者在 coze.cn 或 coze.com 有可用 Bot 与 PAT，PAT 已存入本机安全存储并得到 keyRef。
```bash
WF_LIVE_COZE=1 WF_COZE_BOT_ID=<botId> WF_COZE_API_BASE=https://api.coze.cn WF_COZE_KEY_REF=<keyRef> \
  pnpm --filter @workfleet/node exec vitest run src/modules/agents/infrastructure/coze/__live__
```
- 判断标准：PASS = 两轮对话第二轮能引用第一轮内容 + /clear 后不再引用 + 无 4016 未处理错误；结果写入证据 `live-smoke.md`。

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-085/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/node/src/modules/agents/infrastructure/coze/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-085/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/node/src/modules/agents/** 中 infrastructure/coze/ 以外的部分
- apps/node/src/modules/models/**（钥匙串归 TASK-161）

## 11. 依赖与阻塞
- Depends on：TASK-021
- Blocks：TASK-087
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 节点安全存储（钥匙串抽象）由 TASK-161 提供且排在本任务之后：若 core 中无可用的按 keyRef 读密钥接口，停止并请求规划裁决（不得把 PAT 写入 node.db 或配置文件）
  - Host 的 InputAdapter 端口不支持非 ACP 家族注册

## 12. 建议执行档位
sonnect　理由：单个 HTTP 客户端适配器，接口为官方文档已确认，主力档。

## 13. 升级条件
- 需要实现 requires_action / submit_tool_outputs 端插件审批 → 升 opus 设计审批映射
- Coze 速率限制实测导致需要全局令牌桶 → 升 opus

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 接入矩阵 §6（证据不足）：Coze 速率限制/配额未读到官方数值；cancel 接口未核实。
- 接入矩阵 §6（已确认）：Coze 为云端执行，不能操作本地代码，supportsWriteTools=false。
- U-05（NON_BLOCKING）相关：非 ACP 适配器参数同样以官方文档为准。
- 命名不一致：agent.schema 的 kind 为 `coze`，input-adapter-spec 的 family 为 `coze_http`，本任务按 adapterId=coze 关联，不做重命名。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - 规划：TASK-085 依赖钥匙串（TASK-161）但 DAG 中无此边
  - Agent-Contract：agent.kind `coze` 与 family `coze_http` 命名不一致

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-085/
- 验证者结论：
- 遗留问题 / 跟进项编号：
