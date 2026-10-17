# TASK-012：Web 聊天页（最小）：会话列表、消息流、发送框

```yaml
id: TASK-012
slice: S0
status: todo
owner: Agent-App
tier: sonnect
size: 中
title: "Web 聊天页（最小）：会话列表、消息流、发送框"
dependsOn: ["009", "010"]
blocks: ["013", "027"]
reqs: "REQ-F-015"
allowedPaths: ["apps/web/src/pages/chat/**", "apps/web/src/features/chat/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-012/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-015（tasks.v1.json 原值 `REQ-F-015`）
- 来源方案：architecture §6.4（Web 默认渠道）、ADR-008（TanStack Query + Zustand）、DESIGN-005 交互（文档未落地）

## 2. 目标
Web 最小聊天页：左侧会话列表、右侧消息流（IR 块渲染、实时追加）、底部发送框；离线/急停/智能体不可用等错误在会话内按错误码提示，界面实现 `chat` 屏的 6 种 UX 状态。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §6.4
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-F-015、REQ-NF-011
  - docs/项目完整目录结构.txt §10.2
- 契约：
  - `packages/contracts/api/relay.openapi.json`：`GET /api/v1/conversations`、`POST /api/v1/conversations`（`{agentId}`）、`GET /api/v1/conversations/{conversationId}/messages`、`POST /api/v1/conversations/{conversationId}/messages`（`Idempotency-Key`、`X-CSRF-Token`；`DEVICE_OFFLINE`、`EMERGENCY_STOPPED`、`AGENT_UNAVAILABLE`）、`GET /api/v1/agents`（新建会话时选智能体）、`GET /api/v1/stream`
  - `packages/contracts/schemas/entities/{conversation,message,message-body,agent}.schema.json`（IR 块：paragraph、heading、list、code、table、callout、kpi、attachment、approval、status_card）
  - `packages/contracts/ux/ux-states.json` screen `chat`（6 态，`data-ux-state`）；`errors/error-codes.json` 中上述 3 码的 `ui` 文案（`DEVICE_OFFLINE`：“会话内提示：设备离线，已排队”）
- 前置任务：TASK-009、TASK-010
- 前置状态：TASK-009（路由自动收集、data-access、`<UxState>`、websocket 客户端）与 TASK-010（会话/消息 API、stream）已合并

## 4. 输出
- `apps/web/src/pages/chat/{routes.tsx,ChatPage.tsx}`（路由 `/chat`、`/chat/:conversationId`）
- `apps/web/src/features/chat/{components,hooks,api,store,types}/**`、`index.ts`：`ConversationList`、`MessageStream`、`MessageBlocks`（IR 渲染；对外导出 `registerBlockRenderer(type, Component)` 扩展点，供 TASK-029 注册 `approval` 块的交互卡片）、`Composer`、`NewConversationDialog`；`useConversationStream`（订阅 `/api/v1/stream` 事件 `message.created`/`conversation.updated`/`agent.status` 并写入 Query 缓存）
- 同目录测试 `apps/web/src/features/chat/**/*.test.tsx`

## 5. Execution Steps
1. [ ] `features/chat/api`：基于 TASK-009 `data-access/client.ts` 封装 4 个会话/消息端点与 `GET /agents`；消息分页用 cursor 无限滚动（向上加载历史）。
2. [ ] `useConversationStream`：使用 `data-access/websocket.ts` 断线自动重连；收到 `message.created` 时按 `id` 去重插入（与乐观消息合并），保证同一消息不重复显示。
3. [ ] `Composer`：Enter 发送、Shift+Enter 换行；每次发送生成一个 Idempotency-Key 并在重试时复用；乐观插入“发送中”气泡。
4. [ ] 错误映射：`DEVICE_OFFLINE`→气泡标“已排队”并显示 offline 横幅（最后在线时间）；`EMERGENCY_STOPPED`→全局红色横幅；`AGENT_UNAVAILABLE`→会话内提示 + 诊断链接占位。
5. [ ] `MessageBlocks`：实现全部 IR 块的只读渲染（`approval` 块渲染占位卡片，审批交互由 TASK-029 实现；`code` 块等宽可复制）。
6. [ ] `NewConversationDialog`：列出智能体（alias/设备/状态）创建会话后跳转。
7. [ ] 测试：发送→乐观气泡→stream 回推后替换；重复 `message.created` 不重复渲染；`DEVICE_OFFLINE` 显示“已排队”；`chat` 屏 6 态 `data-ux-state` 断言。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm -F @workfleet/web test src/features/chat` 全绿。
- [ ] AC-2：组件测试：发送后出现乐观气泡；模拟 stream 推送相同 messageId 的 `message.created` 后气泡被替换且总数不增加。
- [ ] AC-3：POST 返回 409 `DEVICE_OFFLINE` 时气泡显示“已排队”且出现 offline 横幅；423 `EMERGENCY_STOPPED` 时显示全局红色横幅。
- [ ] AC-4：`chat` 屏 empty/loading/error/no_permission/success/offline 六态均有测试并断言 `data-ux-state`。
- [ ] AC-5：10 种 IR 块均能渲染且不抛错（快照或 DOM 断言）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/web test src/features/chat
pnpm -F @workfleet/web typecheck && pnpm -F @workfleet/web build
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-012/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `apps/web/src/pages/chat/**`
- `apps/web/src/features/chat/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-012/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-012/` 除外）
- `apps/web/src/features/chat/commands/**`（TASK-027）
- `apps/web/src/{app,components,data-access,lib,styles,i18n}/**`（TASK-009；需新增共享组件或文案时 blocked 提单）
- `apps/web/src/features/approvals/**`（TASK-029）
- `apps/relay/**`、`apps/node/**`

## 11. 依赖与阻塞
- Depends on：TASK-009, TASK-010
- Blocks：TASK-013, TASK-027
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - i18n 文案文件 `src/i18n/locales/*.json` 归 TASK-009 → 本卡文案以 `features/chat/i18n.ts` 局部资源注册到 i18n 实例（若 TASK-009 未提供命名空间注册 API 则 blocked）
  - stream 事件 schema 契约缺失 → 与 TASK-010 的事件名约定（`message.created` 等）不一致时 blocked
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：前端组件与状态管理属主力档常规工作，sonnect 足够。

## 13. 升级条件
- 实时去重/乐观更新在 E2E（TASK-013）中连续 2 次出现重复或丢失消息 → 升 opus 复核缓存策略
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：stream 事件名沿用 TASK-010 卡的 `message.created/conversation.updated/agent.status`（契约缺失）。
- 假设（NON_BLOCKING，U-07）：移动端 PWA 体验不在本卡。
- 风险：Web 会话在组织内共享（见 TASK-010 风险），多人同时聊天会互相看到 → UI 标注发送者。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-012/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
