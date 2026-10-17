# TASK-001：Monorepo 脚手架、根白名单文件、AGENTS.md、Makefile 骨架

```yaml
id: TASK-001
slice: S0
status: todo
owner: Agent-Guard
tier: sonnect
size: 中
title: "Monorepo 脚手架、根白名单文件、AGENTS.md、Makefile 骨架"
dependsOn: []
blocks: ["002", "003", "014"]
reqs: "REQ-C-001/007"
allowedPaths: ["package.json", "pnpm-workspace.yaml", "tsconfig.base.json", "Makefile", "AGENTS.md", "README.md", "CHANGELOG.md", ".editorconfig", ".env.example", ".gitignore", "apps/*/package.json", "apps/*/tsconfig.json", "apps/*/AGENTS.md"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-001/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-C-001、REQ-C-007（tasks.v1.json 原值 `REQ-C-001/007`）
- 来源方案：ADR-004（pnpm workspaces + Makefile，Node 22 LTS，TS 5 strict）、ADR-011（守卫入口）、ADR-012（命名）；PROJECT-STRUCTURE-SPEC §5（根白名单）/§7（根结构）

## 2. 目标
建立可安装、可运行空测试的 pnpm Monorepo 骨架：根白名单文件齐全，`make install && make test && make typecheck` 在干净克隆上退出码为 0，并冻结全仓共用的脚本名与包名。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-004-仓库形态.md、ADR-009-后端运行栈.md、ADR-008-前端.md、ADR-011-架构守卫与CI门禁.md
  - docs/项目完整目录结构.txt §5.1 根目录白名单、§6 .gitignore、§7 根结构、§8.2/§10.2 应用内分层
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §3（部署单元、端口段 5100–5200）
  - docs/WorkFleet-V0.0.4/04_planning/ownership-matrix.md §4（全局禁止修改）
- 契约：
  - `packages/contracts/README.md`（包名 `@workfleet/contracts`、`pnpm contracts:gen`/`contracts:test` 脚本名约定）
  - 无 schema 依赖；仅在 `pnpm-workspace.yaml` 中纳入 `packages/*`
- 前置任务：无
- 前置状态：仓库仅有 `LICENSE`、`.gitignore`、`database/`、`docs/`、`packages/contracts/`；分支 docs/v0.0.4 之后的实现分支

## 4. 输出
- `package.json`（根，`private: true`，`engines.node: ">=22 <23"`，`packageManager: pnpm@9.x`；scripts：`test`=`pnpm -r --if-present test`、`typecheck`、`lint`、`contracts:gen`=`pnpm -F @workfleet/contracts contracts:gen`、`contracts:test`、`db:migrate`=`tsx scripts/database/migrate.ts`、`e2e`=`playwright test`）
- `pnpm-workspace.yaml`（`apps/*`、`packages/*`）
- `tsconfig.base.json`（strict、`moduleResolution: bundler`、`target: ES2023`、`noUncheckedIndexedAccess`）
- `Makefile`：`install test typecheck lint contracts db-migrate e2e dev-relay dev-node dev-web`，并预留 `# >>> guard/ci（TASK-014 维护）` … `# <<< guard/ci` 段（含占位 `guard`、`ci` 目标）
- `AGENTS.md`（AI 规范入口：分层、所有权、禁止修改、任务卡流程）、`apps/relay/AGENTS.md`、`apps/node/AGENTS.md`、`apps/web/AGENTS.md`
- `README.md`、`CHANGELOG.md`、`.editorconfig`、`.env.example`（`WF_RELAY_PORT=5101`、`WF_RELAY_DATA_DIR`、`WF_RELAY_MASTER_KEY_FILE`、`WF_RELAY_PUBLIC_URL`、`WF_NODE_DATA_DIR`、`WF_NODE_CONSOLE_PORT=5100`、`WF_LOG_LEVEL`，无任何密钥值）、`.gitignore`（补 `.local/`、`dist/`、`*.db*`、`.env`）
- `apps/relay/package.json`（`@workfleet/relay`）、`apps/node/package.json`（`@workfleet/node`，`bin.workfleet-node` → `dist/bootstrap/cli.js`，script `cli`=`tsx src/bootstrap/cli.ts`）、`apps/web/package.json`（`@workfleet/web`，scripts `build`=`vite build --mode relay`、`build:node`=`vite build --mode node`）；三者 scripts 统一含 `dev build start test typecheck lint`，`test`=`vitest run --passWithNoTests`
- `apps/relay/tsconfig.json`、`apps/node/tsconfig.json`、`apps/web/tsconfig.json`（extends 根 base）
- 工作区依赖预声明：三个应用 `dependencies` 含 `@workfleet/contracts: workspace:*`，relay/node `devDependencies` 含 `@workfleet/testkit: workspace:*`；根 `devDependencies` 含 `@playwright/test`、`tsx`、`typescript@5`
- 依赖预声明（ADR-008/009 已定的运行栈）：relay/node：fastify@5、ws、better-sqlite3、kysely、pino、ajv、ulid、argon2（relay）、tsx、vitest；web：react@19、react-dom、react-router、@tanstack/react-query、zustand、@radix-ui/*、tailwindcss@4、@tailwindcss/vite、@rjsf/core、@rjsf/validator-ajv8、vite、vitest、jsdom、@testing-library/react

## 5. Execution Steps
1. [ ] 按 §5.1 白名单创建根文件；任何白名单外的根文件不得出现（`LICENSE` 已存在，保持不动）。
2. [ ] 写 `pnpm-workspace.yaml` 与根 `package.json`；按“输出”固定脚本名（后续所有卡的验证命令依赖这些名字，写入 `AGENTS.md` 的“命令速查”）。
3. [ ] 写 `tsconfig.base.json` 与三个 `apps/*/tsconfig.json`；`apps/*/src/` 暂不创建源码（归其他任务），仅用 `--passWithNoTests` 保证空测试通过。
4. [ ] 写三个 `apps/*/package.json`，按 ADR-008/009 预声明依赖（后续任务无权改 package.json，漏声明的依赖将导致其 blocked，故需一次列全并在 AGENTS.md 写明“新增依赖须提单给 Agent-Guard”）。
5. [ ] 写 `Makefile`：每个目标只调用 pnpm 脚本；`e2e` 目标在 `playwright.config.ts` 不存在时打印提示并以 0 退出；预留 guard/ci 段落标记。
6. [ ] 写 `.env.example`（仅变量名与非敏感默认值，端口全部落在 5100–5200）与 `.gitignore`。
7. [ ] 写 `AGENTS.md` 与 `apps/*/AGENTS.md`：分层依赖方向（architecture §5）、所有权矩阵摘要、禁止修改清单、任务卡 16 项流程、证据目录约定。
8. [ ] 在干净克隆执行 `make install && make test && make typecheck`，把输出写入证据目录。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`make install && make test && make typecheck` 在 Node 22 + pnpm 9 干净克隆上退出码均为 0。
- [ ] AC-2：`pnpm -F @workfleet/relay test`、`pnpm -F @workfleet/node test`、`pnpm -F @workfleet/web test` 均可执行（空测试 PASS）。
- [ ] AC-3：根目录 `ls -A` 结果 ⊆ §5.1 白名单 ∪ {`apps`,`packages`,`database`,`docs`,`tests`,`scripts`,`infra`,`.github`,`.git`,`.local`,`node_modules`,`pnpm-lock.yaml`}（脚本断言，见第 7 节）。
- [ ] AC-4：`.env.example` 中不含任何值形如密钥的字符串（`grep -E '(KEY|TOKEN|SECRET)=.+' .env.example` 无输出），且所有端口 ∈ [5100,5200]。
- [ ] AC-5：`AGENTS.md` 含“命令速查”表，列出第 4 节全部脚本名；`apps/node/package.json` 声明 `bin.workfleet-node`。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
make install && make test && make typecheck
pnpm -F @workfleet/relay test && pnpm -F @workfleet/node test && pnpm -F @workfleet/web test
# 根白名单断言
ls -A | grep -vxE 'README.md|AGENTS.md|CHANGELOG.md|LICENSE|Makefile|docker-compose.yml|\.gitignore|\.editorconfig|\.env.example|package.json|pnpm-workspace.yaml|tsconfig.base.json|pnpm-lock.yaml|apps|packages|database|docs|tests|scripts|infra|\.github|\.git|\.local|node_modules' && echo "ROOT POLLUTED" && exit 1 || echo "root ok"
! grep -E '(KEY|TOKEN|SECRET)=.+' .env.example
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-001/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `package.json`
- `pnpm-workspace.yaml`
- `tsconfig.base.json`
- `Makefile`
- `AGENTS.md`
- `README.md`
- `CHANGELOG.md`
- `.editorconfig`
- `.env.example`
- `.gitignore`
- `apps/*/package.json`
- `apps/*/tsconfig.json`
- `apps/*/AGENTS.md`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-001/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `docs/**`（`06_validation/evidence/EVD-001/` 除外）
- `packages/**`（契约包与 testkit 的 package.json 归 TASK-002/008）
- `apps/*/src/**`、`apps/*/tests/**`（归各实现任务）
- `scripts/**`、`tests/**`、`infra/**`

## 11. 依赖与阻塞
- Depends on：—
- Blocks：TASK-002, TASK-003, TASK-014
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - `pnpm-lock.yaml` 由 `pnpm install` 生成但不在本卡 allowedPaths、也不在 §5.1 白名单 → 先请主 Agent 裁定是否纳入（建议纳入，否则 CI `--frozen-lockfile` 不可用）
  - `tsconfig.base.json` 不在 PROJECT-STRUCTURE-SPEC §5.1 白名单（仅在本卡 allowedPaths）→ 按 allowedPaths 执行，并在完成记录中登记偏离
  - ACP TypeScript SDK 包名未定（U-05）→ 不预声明，留给 TASK-021 提单，不阻塞本卡
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：样板与配置为主、可逆性高，sonnect 足够；但脚本名是全仓接口，需按本卡清单一次定稿。

## 13. 升级条件
- 脚本名/包名需偏离本卡约定（会使其他 31 张卡的验证命令失效）→ 升 opus 评审后统一修订任务卡
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING，U-08）：工期未定，本卡不做性能/缓存优化（无 Turborepo，ADR-004 可逆）。
- 假设（NON_BLOCKING，U-05）：ACP SDK 依赖由 TASK-021 实测后再声明，届时需 Agent-Guard 改 `apps/node/package.json`（跨所有权，需提单）。
- 风险：后续任务新增依赖都要改 `apps/*/package.json`（仅本卡所有）→ 规划缺陷，已在汇报中列出；缓解为本卡一次预声明 ADR-008/009 全部运行栈。
- 风险：Windows 下 `make` 不可用 → `AGENTS.md` 同时给出等价 `pnpm` 命令（REQ-NF-006）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-001/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
