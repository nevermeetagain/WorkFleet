# TASK-022：InputAdapterSpec 加载与探测；Claude Code/Codex/Cursor 夹具录制与真机冒烟

```yaml
id: TASK-022
slice: S1
status: todo
owner: Agent-Node
tier: sonnect
size: 中
title: "InputAdapterSpec 加载与探测；Claude Code/Codex/Cursor 夹具录制与真机冒烟"
dependsOn: ["021"]
blocks: ["030", "081", "082", "083", "084"]
reqs: "REQ-F-007"
allowedPaths: ["apps/node/src/modules/agents/infrastructure/specs/**", "packages/testkit/fixtures/acp/{claude-code,codex,cursor}/**", "docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-022/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-022/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S1
- 来源需求：REQ-F-007（tasks.v1.json 原值 `REQ-F-007`）
- 来源方案：ADR-007（新增智能体 = 一条 spec + 一个录制夹具；实验项标注）、REQ-F-007（DEC-055 实测清单每项需录制回放夹具 + 一次真机冒烟）

## 2. 目标
节点可加载并校验 InputAdapterSpec 表（契约内置表 + 用户本地覆盖），探测本机已安装智能体的可执行文件与版本；为 Claude Code、Codex、Cursor 各录制至少一套回放夹具并完成一次真机冒烟，结论写入证据。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-007-输入端.md
  - docs/WorkFleet-V0.0.2/30-协议与端点/01-ACP协议深度分析.md（ACP v1：initialize、session/new、session/prompt、session/update、session/request_permission、session/cancel、session/load、session/resume、session/close；v2 为 draft）
  - docs/WorkFleet-V0.0.2/30-协议与端点/02-输入端接入矩阵.md（各智能体启动方式，含“待实测”标注）
  - packages/testkit/fixtures/acp/README.md（夹具格式，TASK-008）
- 契约：
  - `packages/contracts/adapters/input-adapter-spec.schema.json`（必填：adapterId、displayName、family、source、experimental、auth、supportsLoadSession、supportsWriteTools、configSchema；可选 launch、detect、dialect）
  - `packages/contracts/adapters/input-adapters.v1.json`：`claude-code`（`npx -y @zed-industries/claude-agent-acp`）、`codex`（`npx -y @zed-industries/codex-acp`）、`cursor`（`agent acp`）——启动参数标注“待实测”
  - `packages/contracts/api/node-local.openapi.json`：`GET /local/v1/adapters/detect`（路由由 TASK-021 提供，本卡提供实现）；`api/relay.openapi.json`：`GET /api/v1/adapters/input`（中转侧展示，需节点探测结果）
- 前置任务：TASK-021
- 前置状态：TASK-021 已合并（`SpecSource` 端口、ACP Host 可按 spec 拉起子进程）；TASK-008 的 `recorder.ts` 可用；执行机已安装并登录 Claude Code / Codex / Cursor（真机冒烟前置，product-requirements §8）

## 4. 输出
- `apps/node/src/modules/agents/infrastructure/specs/{index.ts,loader.ts,detector.ts,validate.ts}`：`createSpecSource()`——加载契约内置表 → 叠加 `<WF_NODE_DATA_DIR>/adapters.local.json`（同 schema，逐字段覆盖，按 adapterId 合并）→ ajv 校验，非法行跳过并告警
- `detector.ts`：按 `detect.versionCommand`（缺省时 `<command> --version`）探测；Windows 用 `where`/`windowsCommand`，POSIX 用 `which`；返回 `{adapterId, installed, version, path, meetsMinVersion}`
- `packages/testkit/fixtures/acp/claude-code/**`、`fixtures/acp/codex/**`、`fixtures/acp/cursor/**`（每个至少 `basic.jsonl`；支持权限请求的另录 `permission.jsonl`）
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-022/{smoke-matrix.md,claude-code.log,codex.log,cursor.log,spec-diff.md}`（真机冒烟矩阵、实测启动参数与契约表差异）
- 测试：`apps/node/tests/unit/modules/agents/specs/**`（loader/detector/校验）与 `apps/node/tests/integration/modules/agents/replay-{claude-code,codex,cursor}.test.ts`（以录制夹具回放跑通 Host）

## 5. Execution Steps
1. [ ] 实现 `loader.ts` 与 `validate.ts`：内置表来自 `@workfleet/contracts`；本地覆盖文件不存在时忽略；校验失败行写告警日志（含 adapterId 与 ajv 路径），不影响其他行。
2. [ ] 实现 `detector.ts` 与 `index.ts`（`createSpecSource()` 满足 TASK-021 的 `SpecSource` 端口）；探测命令超时 5 s。
3. [ ] 单测：覆盖文件合并、非法行跳过、命令不存在→`installed:false`、版本解析与 `minVersion` 比较。
4. [ ] 真机录制：用 `recorder.ts` 代理 Claude Code / Codex / Cursor 的 ACP 会话，分别执行“读取 README 并总结一句”的只读任务；涉及写工具的再录一次权限请求；对夹具中的路径、token、用户名打码。
5. [ ] 真机冒烟：经 Host 实际与三者各完成 2 轮对话，记录启动命令、版本、首包时延、是否支持 `session/load`（与表中 `supportsLoadSession:false` 比对，如 Cursor 文档写明支持 session/load）。
6. [ ] 回放测试：三套夹具经 FakeAgent 回放驱动 Host，断言产生合法 `agent.output`（权限夹具断言 `approval.request`）。
7. [ ] 把实测启动参数与契约表差异写入 `spec-diff.md`（如 V0.0.2 记载 Claude 适配器包名已迁至 `@agentclientprotocol/claude-agent-acp`，与表中 `@zed-industries/…` 不一致）；只报告，不改契约。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm -F @workfleet/node test tests/unit/modules/agents/specs` 全绿；内置表 15 行全部通过 `input-adapter-spec.schema.json` 校验。
- [ ] AC-2：`curl http://127.0.0.1:5100/local/v1/adapters/detect` 返回数组，每项含 `adapterId/installed/version`；未安装的智能体 `installed:false`。
- [ ] AC-3：`fixtures/acp/{claude-code,codex,cursor}/basic.jsonl` 存在且回放测试通过（产生 schema 合法的 `agent.output{kind:final}`）。
- [ ] AC-4：`EVD-022/smoke-matrix.md` 对三者各给出 PASS/FAIL/UNKNOWN、版本号、启动命令、时间戳；FAIL/UNKNOWN 附原因与日志。
- [ ] AC-5：夹具与日志经 `gitleaks detect` 无发现（无真实 token/用户路径泄露）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
pnpm -F @workfleet/node test tests/unit/modules/agents/specs tests/integration/modules/agents/replay-
gitleaks detect --no-git --source packages/testkit/fixtures/acp --no-banner
curl -s http://127.0.0.1:5100/local/v1/adapters/detect | jq '.[] | {adapterId, installed, version}'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-022/
- `smoke-matrix.md`：三者真机冒烟结论（PASS/FAIL/UNKNOWN）
- `spec-diff.md`：实测启动参数 vs 契约表差异（待 Agent-Contract 处理）
- `*.log`：冒烟会话日志（已打码）
- `test-output.txt`：第 7 节输出

## 9. 允许修改
- `apps/node/src/modules/agents/infrastructure/specs/**`
- `packages/testkit/fixtures/acp/{claude-code,codex,cursor}/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-022/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/node/tests/unit/modules/agents/specs/**`
  - `apps/node/tests/integration/modules/agents/replay-*.test.ts`

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-022/` 除外）
- `apps/node/src/modules/agents/**` 中除 `infrastructure/specs/**` 外的路径（TASK-021）
- `apps/node/src/modules/agents/infrastructure/specs/{group-a,group-b,openclaw}/**`（TASK-081/082/083）
- `packages/testkit/**` 中除上述三个夹具目录外的路径（TASK-008/081–084）

## 11. 依赖与阻塞
- Depends on：TASK-021
- Blocks：TASK-030, TASK-081, TASK-082, TASK-083, TASK-084
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 执行环境没有已登录的 Claude Code/Codex/Cursor → 对应项真机冒烟标 UNKNOWN 并 blocked（需用户提供环境），回放夹具可用社区公开样例代替但须标注“非本机录制”
  - 实测启动参数与契约表不一致导致无法拉起 → 不改契约；在 `adapters.local.json`（用户数据目录，不入库）中临时覆盖完成冒烟，并提交契约变更请求
  - 节点探测结果无帧上报中转（`GET /api/v1/adapters/input` 声称包含“节点探测结果”，但 envelope 无对应帧）→ 本卡只提供本机端点，中转侧展示缺口已报告
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：加载/探测是常规代码，录制与冒烟是按清单执行的实测工作，sonnect 足够；实验项失败允许标注。

## 13. 升级条件
- 三者中 ≥2 个真机冒烟失败且原因指向 Host 协议实现（非环境）→ 升 opus 复核 TASK-021
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-05）：各智能体启动参数以官方文档为准，表中值为规划值（“待实测”）；实测差异写入 `spec-diff.md`。
- 风险：Claude Code/Codex 适配器包名迁移（`@zed-industries/*` → `@agentclientprotocol/*`，V0.0.2 部分确认）可能使表中 `npx` 命令失效——证据不足/待实测。
- 风险：夹具含个人信息或令牌 → 录制器打码 + gitleaks 校验。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-022/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
