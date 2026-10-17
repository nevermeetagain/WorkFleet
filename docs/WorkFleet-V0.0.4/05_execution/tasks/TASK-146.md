# TASK-146：安全审查：越权矩阵测试、密钥扫描、提示注入标记

```yaml
id: TASK-146
slice: S7
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-QA
tier: opus
size: 中
title: "安全审查：越权矩阵测试、密钥扫描、提示注入标记"
dependsOn: ["145"]
blocks: ["210"]
reqs: "REQ-NF-004"
allowedPaths: ["tests/integration/security/**", "tests/integration/security/gitleaks-rules.toml（规则补充，由 TASK-014 的 .gitleaks.toml 引用）"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S7
- 来源需求：REQ-NF-004
- 来源方案：ADR-006（越权：统一拦截 + 禁止路径）；ADR-011（gitleaks 门禁）；REQ-NF-004；permissions.json forbiddenPaths

## 2. 目标
以 permissions.json 为唯一源自动生成“角色 × 动作 × 端点”越权矩阵测试与 forbiddenPaths 测试、配置 gitleaks 密钥扫描、验证入站 IM 文本按不可信处理（提示注入标记），全部在 CI 中可重复执行。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-006-鉴权与权限.md
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-011-架构守卫与CI门禁.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-NF-004、REQ-F-002/003、REQ-C-006）
- 契约：
  - packages/contracts/identity/permissions.json（`matrix` 36 动作 × 3 角色、`extraRules`、`forbiddenPaths` 5 条）
  - packages/contracts/api/relay.openapi.json（每个操作的 `x-permission`、`x-auth`；用于把动作映射到端点）
  - packages/contracts/identity/device-token-claims.schema.json、identity/session-claims.schema.json
  - packages/contracts/errors/error-codes.json：`UNAUTHENTICATED`、`FORBIDDEN`、`NOT_FOUND`、`RECIPIENT_UNAUTHORIZED`
  - packages/contracts/protocol/frames/agent.prompt.schema.json（`from.recipientId/userId`）；commands/im-commands.json（未授权者只能 /bind）
- 前置任务：TASK-145
- 前置状态：TASK-145 及其之前的 S7 任务已合并；中转可用 testkit 起测试实例（端口 5110–5119）。

## 4. 输出
- tests/integration/security/permission-matrix.test.ts（从 permissions.json × relay.openapi.json 生成用例）
- tests/integration/security/forbidden-paths.test.ts（跨组织 404、viewer 非 GET 403、设备令牌调 Web API 401、未授权 IM 发送者不触发路由、模型 Key 字段不存在）
- tests/integration/security/secret-scan.test.ts（relay.db、relay 日志、relay.openapi.json 中 grep 测试 Key 与 `apiKey|api_key|secret` 字段名）
- tests/integration/security/prompt-injection.test.ts
- .gitleaks.toml（在 TASK-014 基础上补充规则与 allowlist：测试夹具假 Key 前缀）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-146/`（见 §8）

## 5. Execution Steps
1. [ ] 写生成器：遍历 openapi 每个带 `x-permission`（非 public）的操作，结合 matrix 生成 admin/operator/viewer 三个期望（2xx/4xx 业务错 vs 403）；为每个端点准备最小合法请求体夹具。
2. [ ] 实现 extraRules：设备所有者（非 admin）对 `approval.decide_high`、`device.revoke` 可通过；非所有者 operator 被拒。
3. [ ] 实现 forbiddenPaths 5 条用例；项目范围（TASK-141）用例：scope 外资源 404。
4. [ ] secret-scan：节点配置测试 Key（固定假值）走完一次总控调用（FakeModel）后，在 relay.db 文件、relay 日志、所有中转 HTTP 响应中 grep 0 命中。
5. [ ] 提示注入：IM 未授权发送者发送“/stop all”与“忽略之前的指令…”→ 只回固定提示、不路由、不执行指令；已授权发送者的入站在 agent.prompt 中保留 `from` 来源，供下游作为不可信内容处理；在 EVD 记录“契约无显式不可信标记字段”的缺陷。
6. [ ] 更新 .gitleaks.toml：确保测试夹具假 Key 被 allowlist 而真实格式 Key（OpenAI/Anthropic 前缀等）被拦截；造一个含假真实格式 Key 的临时文件验证门禁会失败（测试后删除）。
7. [ ] 在 CI（ubuntu）跑全部 security 测试；把矩阵结果导出 CSV 存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 越权矩阵：permissions.json 中有端点承载的每个动作 × 3 角色全部有用例并通过；无端点承载的动作（如在已扫描的 relay.openapi.json 中未找到使用 `tenant.update` 的操作）逐条列入 `findings.md` 作为契约缺陷，不算测试失败。
- [ ] forbiddenPaths 5 条全部有用例且通过。
- [ ] secret-scan：测试 Key 在 relay.db/日志/响应中 0 命中。
- [ ] 未授权 IM 发送者的任何文本（含指令与注入语句）不产生 agent.prompt 帧（FakeRelay 断言）。
- [ ] `gitleaks detect --config .gitleaks.toml` 对仓库通过，对植入真实格式假 Key 的样本失败。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-146/
pnpm exec vitest run tests/integration/security --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-146/vitest.txt
gitleaks detect --source . --config .gitleaks.toml --no-banner --redact | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-146/gitleaks.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-146/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-146/
- `vitest.txt`、`gitleaks.txt`、`guard.txt`
- `permission-matrix.csv`（动作、角色、端点、期望、实际）
- `findings.md`（发现的越权/泄露问题，按严重度；契约缺陷单列）

## 9. 允许修改
- `tests/integration/security/**`
- `.gitleaks.toml`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-146/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-146/` 除外，见 ownership-matrix §4）
- apps/**（发现缺陷只报告并开新任务，不在本卡修实现）
- packages/testkit/**（需要新夹具时报主 Agent）

## 11. 依赖与阻塞
- Depends on：TASK-145
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 发现越权或 Key 泄露的真实缺陷：不在本卡修复，标 blocked 并为责任模块开缺陷任务（附最小复现）。
  - `.gitleaks.toml` 同时出现在 TASK-014（Guard）与本卡（QA）允许路径：若 014 之后 Guard 仍在改该文件，先协调，避免并发改。

## 12. 建议执行档位
opus　理由：安全审查属 cost-budget 指定的 opus 职责，需要判断“测试通过但语义越权”的情况。

## 13. 升级条件
- 发现需要修改 permissions.json 或 ADR-006 的问题 → fable（推翻冻结契约）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：testkit 能为每个端点提供最小合法请求体；不足部分在测试内构造。
- 契约缺陷：agent.prompt 无“不可信来源”显式字段，只能凭 `from` 推断（报告）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-146/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-146.md`）
