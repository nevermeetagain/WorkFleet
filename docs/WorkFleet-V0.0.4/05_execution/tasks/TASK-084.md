# TASK-084：ZCode 实验适配器（zcode-acp-server / app-server 方言）

```yaml
id: TASK-084
slice: S4
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: opus
size: 中
title: "ZCode 实验适配器（zcode-acp-server / app-server 方言）"
dependsOn: ["022"]
blocks: ["087"]
reqs: "REQ-F-007"
allowedPaths: ["apps/node/src/modules/agents/infrastructure/dialects/zcode/**", "packages/testkit/fixtures/acp/zcode/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S4（可演示：13 个 ACP 智能体 + Coze + Webhook 冒烟矩阵全部有结论）
- 来源需求：REQ-F-007
- 来源方案：ADR-007（通用 ACP 适配器 + 本地 InputAdapterSpec 表）、ADR-010、ADR-011；DEC-007/055

## 2. 目标
实现 ZCode 实验适配器的方言层：支持两条路径——社区桥 `zcode-acp-server`（标准 ACP）与 `zcode app-server --stdio` 私有 NDJSON 方言（翻译为 ACP 语义），实测哪条可用并写入节点侧覆盖与夹具；失败只标注、不阻塞切片。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.2/30-协议与端点/02-输入端接入矩阵.md`（§0 一页结论、§7 横向能力矩阵）
  - `docs/WorkFleet-V0.0.2/30-协议与端点/01-ACP协议深度分析.md`
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.2 agents（通用 ACP 适配器读 Registry + 本地 InputAdapterSpec 表）
  - `docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-007-输入端.md`
  - ACP 官方智能体列表 https://agentclientprotocol.com/overview/agents（2026-10-17 读取：列出 Gemini CLI、Qwen Code、Kimi CLI、OpenCode、Goose、Cline、Qoder CLI、GitHub Copilot（public preview）、OpenClaw，链接与 input-adapters.v1.json 的 docsUrl 一致；该页不给启动参数，启动参数一律待实测）
- 契约：
  - `packages/contracts/adapters/input-adapter-spec.schema.json`（launch.command/args/windowsCommand/env/cwdMode、detect.versionCommand/minVersion、auth、dialect、supportsLoadSession、supportsWriteTools、docsUrl、configSchema）
  - `packages/contracts/adapters/input-adapters.v1.json`（规划值，`$verify`：启动参数与 loadSession 为 U-05 假设）
  - `packages/contracts/schemas/entities/agent.schema.json`（kind=acp、experimental、writeMode）
  - `packages/contracts/protocol/frames/agent.prompt|agent.output|agent.status|approval.request|approval.decision`
  - `packages/contracts/errors/error-codes.json`：AGENT_UNAVAILABLE（可执行文件缺失/启动失败）
  - `packages/contracts/api/node-local.openapi.json`：`GET /local/v1/adapters/detect`
  - 方言钩子：input-adapter-spec 的 `dialect` 字段（“方言钩子 id，空 = 标准 ACP”）；契约中 zcode 行 dialect 为空、launch=`zcode-acp-server`、source=community、experimental=true
  - 规划值（待实测）：zcode `zcode-acp-server`（community, experimental=true）；dialect 规划值为空（本任务实测后在覆盖中设为 `zcode`）；supportsLoadSession=false
- 前置任务：TASK-022
- 前置状态：TASK-022 已合并（InputAdapterSpec 加载、探测与 Claude/Codex/Cursor 夹具流程可复用）；TASK-008 FakeAgent 录制回放可用

## 4. 输出
- `apps/node/src/modules/agents/infrastructure/dialects/zcode/overrides.v1.json`：实测后的 spec 覆盖项（节点侧，不改契约）
- `apps/node/src/modules/agents/infrastructure/dialects/zcode/loader.ts`、`probe.ts`、`__tests__/`：覆盖合并、实测探针、回放测试
- `packages/testkit/fixtures/acp/zcode/`：每个智能体的录制夹具（脱敏）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-084/`（每个智能体的版本、实测命令与 initialize 摘要、真机冒烟结论；spec-measurements.md）

## 5. Execution Steps
1. [ ] 在 `apps/node/src/modules/agents/infrastructure/dialects/zcode/` 建 `overrides.v1.json`（数组，每项必须通过 input-adapter-spec.schema.json 校验）与 `loader.ts`（把覆盖项按 adapterId 合并到 TASK-022 加载的基础表，覆盖优先）。
2. [ ] 对每个智能体（zcode）在已安装并登录的真机上执行 `detect.versionCommand`，记录版本号与 OS；未安装的记 AGENT_UNAVAILABLE 并在证据中写“待实测”。
3. [ ] 用契约中的 launch.command/args 启动，发送 ACP `initialize`；若失败，按官方文档逐个尝试候选参数，记录每次尝试的命令与退出码；以首个能完成 initialize 的组合为实测值。
4. [ ] 从 `initialize` 响应读取 `agentCapabilities.loadSession`、promptCapabilities 与 authMethods，填入 supportsLoadSession；Windows 下确认是否需要 windowsCommand（如 .cmd 包装）。
5. [ ] 完成一轮最小会话：`session/new` → `session/prompt`（固定提示词“只回复 OK”）→ 至少 1 次 `session/request_permission`（让其写临时文件）→ `session/cancel`；用 TASK-008 FakeAgent 录制器保存为夹具。
6. [ ] 夹具脱敏（去除 token、用户名、绝对路径）后写入 `packages/testkit/fixtures/acp/zcode/`，每个智能体至少 `initialize.jsonl`、`prompt-basic.jsonl`、`permission.jsonl`、`cancel.jsonl` 与 `meta.json`（版本、OS、录制日期、实测 launch）。
7. [ ] 在 `apps/node/src/modules/agents/infrastructure/dialects/zcode/` 写回放测试：通用 ACP Host 驱动 FakeAgent 回放每个夹具，断言 agent.output(final)、approval.request、cancel 后 agent.status=idle。
8. [ ] 实现方言翻译器（只在 dialects/zcode 内）：按接入矩阵 §5.2（部分确认，社区逆向）映射 `session/create|resume → session/subscribe → session/send → session/event(model.streaming/tool.updated/turn.completed|failed) → session/close`；消息不带 `jsonrpc` 字段、无 initialize 握手；字段“宽进严出”校验，未知事件记日志不崩溃。
9. [ ] 实现“通知可能丢失”兜底（turn 超时后轮询 `session/read`）与 `/clear` = session/close + session/create；会话仅在进程内存，节点重启后 supportsLoadSession=false；在覆盖文件中把 dialect 设为 `zcode`（app-server 路径可用时）或保持空（仅社区桥可用时），写明依据。
10. [ ] 把实测结果（命令、参数、版本、loadSession、是否需 windowsCommand、失败原因）写入证据 `spec-measurements.md`，并登记“需 Agent-Contract 后续同步 input-adapters.v1.json”跟进项。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] `overrides.v1.json` 每项通过 input-adapter-spec.schema.json 校验（ajv 测试），且覆盖 1 个 adapterId
- [ ] 1 个智能体各有 ≥4 个夹具文件，回放测试全部通过（CI 不依赖真实智能体）
- [ ] 夹具与证据中 grep 不到 token/密钥/本机用户名（gitleaks 通过）
- [ ] `spec-measurements.md` 为每个智能体给出：实测启动命令与参数、版本、supportsLoadSession 实测值与依据、真机冒烟结论（PASS/FAIL+原因）
- [ ] 方言单测覆盖：缺失 turn.completed 时经 session/read 轮询收敛；未知事件不抛异常；/clear 产生 close+create 两条请求
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
# 1) 自动化：spec 覆盖校验 + 夹具回放（CI）
pnpm --filter @workfleet/node exec vitest run src/modules/agents/infrastructure/dialects/zcode/
pnpm exec gitleaks detect --no-git --source packages/testkit/fixtures/acp --redact
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/node/src/modules/agents/infrastructure/dialects/zcode/|packages/testkit/fixtures/acp/zcode/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-084/)' || echo 'SCOPE OK'
```

**人工验收项（需要真实凭据，不进 CI）**
- 前提：执行者本机已安装并登录 zcode（WorkFleet 不代为登录，见 PRB §8）。
- 对每个智能体执行：
```bash
# 记录版本与实测启动参数（结果写入 docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-084/spec-measurements.md）
pnpm --filter @workfleet/node exec tsx src/modules/agents/infrastructure/dialects/zcode/probe.ts --adapter <adapterId> --record --out docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-084/<adapterId>/
```
- 判断标准（每个智能体独立判定）：PASS = initialize 成功 + 一轮 prompt 得到最终回复 + 权限请求能转成 approval.request 并按批准结果继续 + cancel 后进程不残留；FAIL 必须写明失败步骤、错误输出与已尝试参数。实验项允许 FAIL，但必须有原因（REQ-F-007）。

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-084/
- `README.md`：总体结论与环境
- `spec-measurements.md`：每个 adapterId 一节（实测 launch、版本、supportsLoadSession、冒烟结论、失败原因）
- `<adapterId>/`：version.txt、initialize.json（脱敏）、smoke.log
- `followups.md`：需 Agent-Contract 同步 input-adapters.v1.json 的字段差异清单

## 9. 允许修改
- `apps/node/src/modules/agents/infrastructure/dialects/zcode/**`
- `packages/testkit/fixtures/acp/zcode/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-084/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/node/src/modules/agents/** 中本任务 spec 目录以外的部分（Host 属 TASK-021，spec 加载属 TASK-022）
- packages/testkit/** 中本任务夹具目录以外的部分（FakeAgent 属 TASK-008）

## 11. 依赖与阻塞
- Depends on：TASK-022
- Blocks：TASK-087
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-022 未提供可合并覆盖项的扩展点（只能改 specs/ 根目录）→ 停止并请求 Agent-Node 规划
  - 执行者没有可用的真机/账号完成某个智能体的登录：该智能体真机冒烟标 UNKNOWN 并写明缺失条件，不阻塞其余智能体与回放测试
  - 实测结果需要的字段在 input-adapter-spec.schema.json 中不存在（schema additionalProperties:false）→ 写入证据，不扩展 schema
  - 实测需要使用社区包（自述 Unofficial、可能违反 ToS）：仅在执行者本机测试，不把其代码拷入仓库；许可/ToS 结论写入证据，若不可接受则只保留 app-server 路径

## 12. 建议执行档位
opus　理由：私有协议逆向翻译、语义映射有歧义且涉及 ToS 判断，需要 opus 的判断力。

## 13. 升级条件
- 需要修改通用 ACP Host（dialect 钩子接口不足）→ 升 fable/规划变更，不在本任务内改 Host
- 社区桥 ToS 结论不明确且影响是否保留该路径 → 交用户裁决

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- U-05（NON_BLOCKING）：各智能体启动参数与 loadSession 以官方文档为准、待实测；本任务即其实测落点。
- 风险：智能体 CLI 版本漂移导致夹具过期 → meta.json 记录版本，回放测试只依赖夹具。
- U-06（NON_BLOCKING）：ZCode app-server 私有协议稳定性未知，标实验；失败不阻塞切片验收。
- R-02 / REQ-C-009：ZCode 协议私有且未文档化，社区 ACP 桥有 ToS 风险（接入矩阵 §5.2 部分确认）。
- REQ-C-004 / DEC-038：冒烟前必须关闭 ZCode 自带微信 Bot Channel，避免争抢同一 ClawBot 绑定（接入矩阵 §5.3 推断）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - Agent-Contract：按 `followups.md` 同步 `packages/contracts/adapters/input-adapters.v1.json`（launch、supportsLoadSession、experimental、docsUrl），并移除对应 `$verify`
  - Agent-Contract：input-adapters.v1.json 每行含 `$verify` 字段，而 input-adapter-spec.schema.json 为 additionalProperties:false，按行校验会失败

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-084/
- 验证者结论：
- 遗留问题 / 跟进项编号：
