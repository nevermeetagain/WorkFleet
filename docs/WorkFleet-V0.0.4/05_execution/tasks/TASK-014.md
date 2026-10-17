# TASK-014：CI 守卫：dependency-cruiser、根污染、命名、gitleaks、契约测试、三平台矩阵

```yaml
id: TASK-014
slice: S0
status: todo
owner: Agent-Guard
tier: sonnect
size: 中
title: "CI 守卫：dependency-cruiser、根污染、命名、gitleaks、契约测试、三平台矩阵"
dependsOn: ["001", "002"]
blocks: ["209"]
reqs: "REQ-NF-004/006/009"
allowedPaths: [".github/**", ".dependency-cruiser.cjs", "eslint.config.js", ".gitleaks.toml", "Makefile（仅 guard/ci 目标段）"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-014/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-NF-004、REQ-NF-006、REQ-NF-009（tasks.v1.json 原值 `REQ-NF-004/006/009`）
- 来源方案：ADR-011（dependency-cruiser + ESLint + Makefile guard + gitleaks + 契约测试；三平台矩阵单测、E2E 只在 ubuntu）、ADR-002（漂移检查）、ADR-012（命名）、PROJECT-STRUCTURE-SPEC §15–17（三层守卫）

## 2. 目标
CI 在每个 PR 上机器执行：分层依赖守卫、根目录污染检查、命名检查、gitleaks 密钥扫描、契约生成物漂移与契约测试、ubuntu/windows/macos 三平台单测与类型检查、ubuntu E2E；任一失败即阻断合并。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-011-架构守卫与CI门禁.md、ADR-002-契约唯一源.md、ADR-012-全局命名与格式.md
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §5（依赖方向）
  - docs/项目完整目录结构.txt §5（根白名单）、§15（ESLint 边界）、§16（dependency-cruiser）、§17（Makefile 根污染）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md REQ-NF-004/006/009
- 契约：
  - `packages/contracts/**`（`pnpm contracts:gen` + `git diff --exit-code -- packages/contracts/generated` + `pnpm contracts:test`，由 TASK-002 提供脚本）
  - `packages/contracts/identity/permissions.json` forbiddenPaths“中转任何端点不得返回或接收模型 Key”→ secret-scan 门禁（gitleaks 规则 + `grep` 禁止 `apiKey` 出现在 `apps/relay/**`）
  - `database/migrations/**` 命名规则 `^\d{4}_[a-z0-9_]+\.sql$`、只追加（CI 检查已合并迁移文件未被修改）
- 前置任务：TASK-001、TASK-002
- 前置状态：TASK-001（Makefile 预留 guard/ci 段、脚本名）与 TASK-002（contracts:gen/test）已合并

## 4. 输出
- `.github/workflows/ci.yml`：jobs `guard`（ubuntu：`make guard`）、`contracts`（ubuntu：`make contracts` + 漂移检查）、`test`（matrix ubuntu-latest/windows-latest/macos-latest × Node 22：`make install test typecheck`）、`e2e`（ubuntu：`make e2e`，`tests/e2e` 存在时）
- `.dependency-cruiser.cjs`：后端 `interfaces→application→domain←infrastructure`（domain 不得依赖 application/interfaces/infrastructure/框架）；跨模块只能 import 对方 `modules/<m>/index.ts`；`apps/relay` 与 `apps/node`、`apps/web` 互不 import；跨应用只经 `@workfleet/contracts`；前端 `pages→features→components→lib`，features 之间只经 `index.ts`；禁止循环依赖
- `eslint.config.js`：TS 推荐规则 + `no-restricted-imports`（同上边界的快速反馈版）+ 禁止 `console.log`（使用 pino）
- `.gitleaks.toml`：默认规则 + 自定义 `workfleet-device-token`、`openai/anthropic key`、`iLink bot_token` 规则；允许清单只含测试夹具中明确的假值
- `Makefile`（仅 `# >>> guard/ci` 段）：`guard-root`（§5.1 白名单）、`guard-deps`（depcruise）、`guard-lint`、`guard-naming`、`guard-secrets`（gitleaks）、`guard-migrations`、`guard`（以上全部）、`ci`（guard + contracts + test + typecheck + e2e）

## 5. Execution Steps
1. [ ] 写 `.dependency-cruiser.cjs` 规则并在空仓库 + 一个故意违规的临时样例（放在 `.local/guard-fixtures/`，不入库）上验证能报错。
2. [ ] 写 `eslint.config.js`（flat config），各包 `lint` 脚本指向根配置（TASK-001 已定 `lint` 脚本名）。
3. [ ] 写 `guard-root`：根目录条目 ⊆ §5.1 白名单 ∪ 允许目录；写 `guard-naming`：后端 `.ts` 文件 kebab-case、React 组件 `PascalCase.tsx`、目录 kebab-case、任务卡 `TASK-\d{3}\.md`、迁移文件名规则。
4. [ ] 写 `guard-migrations`：对比 `origin/main`，已存在的 `database/migrations/**` 文件不得被修改，只允许新增。
5. [ ] 写 `.gitleaks.toml` 与 `guard-secrets`（含 `apps/relay` 中禁止出现模型 Key 字段的 grep 检查，对应 permissions.json forbiddenPaths）。
6. [ ] 写 `.github/workflows/ci.yml`：pnpm 缓存、Node 22、三平台矩阵（windows 上设置 `git config core.autocrlf false` 并开启长路径 `core.longpaths true`，为 REQ-NF-006 用例提供环境）；E2E 仅 ubuntu。
7. [ ] 在 PR 上运行一次全绿；再以临时分支各制造一次违规（越层 import、根目录新文件、假密钥、修改 0001 迁移）验证对应 job 失败，截图/日志存证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`make guard` 在当前主干上退出码 0；`make ci` 本地可执行。
- [ ] AC-2：故意越层（domain import infrastructure）、跨模块绕过 `index.ts`、relay import node 三类违规各自让 `guard-deps` 失败（违规样例日志入证据）。
- [ ] AC-3：根目录新增 `foo.txt` → `guard-root` 失败；新增含假 OpenAI Key 的文件 → `guard-secrets` 失败；修改 `database/migrations/relay/0001_init.sql` → `guard-migrations` 失败。
- [ ] AC-4：`ci.yml` 的 `test` job 在 ubuntu/windows/macos 三平台均运行并通过；`contracts` job 在生成物漂移时失败。
- [ ] AC-5：CI 中 E2E job 仅在 ubuntu 运行（ADR-011）。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
make guard
make ci
pnpm exec depcruise --config .dependency-cruiser.cjs apps packages
gitleaks detect --config .gitleaks.toml --no-banner
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-014/
- `test-output.txt`：`make guard`/`make ci` 输出
- `violations/`：四类故意违规的失败日志
- `ci-run.md`：PR 上三平台矩阵运行链接与结论

## 9. 允许修改
- `.github/**`
- `.dependency-cruiser.cjs`
- `eslint.config.js`
- `.gitleaks.toml`
- `Makefile（仅 guard/ci 目标段）`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-014/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `docs/**`（`06_validation/evidence/EVD-014/` 除外）
- `Makefile` 中 `# >>> guard/ci` 段以外的目标（TASK-001 所有）
- `apps/**`、`packages/**`、`tests/**`（守卫只读扫描，不改业务代码）

## 11. 依赖与阻塞
- Depends on：TASK-001, TASK-002
- Blocks：TASK-209
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `Makefile（仅 guard/ci 目标段）` 依赖 TASK-001 预留段落标记；若缺失则 blocked 请 TASK-001 补
  - 现有代码已违反守卫规则（由早于本卡合并的任务引入）→ 不改业务代码，列清单退回对应任务，CI 先以 warning 模式合入需主 Agent 批准
  - `.gitleaks.toml` 同时出现在 TASK-146 的 allowedPaths → 本卡建立基线，后续调整归 TASK-146
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：守卫配置可逆、规则来自已批准 ADR 与规范，sonnect 足够；规则语义不自行发明。

## 13. 升级条件
- 守卫规则需与 ADR-011/architecture §5 不同的分层解释（如允许 application 直接用 Kysely）→ 升 opus 裁定
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-08）：GitHub Actions 三平台 runner 可用、时长可接受（ADR-011 已接受 CI 变慢）。
- 风险：better-sqlite3 在 windows/macos runner 上需预编译包，失败时会表现为测试失败 → 记录为平台问题并退回 TASK-003（证据不足/待实测）。
- 风险：GBK 控制台/CRLF/长路径（REQ-NF-006）的具体用例不在本卡，本卡只保证矩阵环境。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-014/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
