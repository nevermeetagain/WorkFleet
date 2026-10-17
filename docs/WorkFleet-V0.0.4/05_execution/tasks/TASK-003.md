# TASK-003：迁移运行器（relay/node 共用）+ 应用 0001 + 仓储基类（Kysely）

```yaml
id: TASK-003
slice: S0
status: todo
owner: Agent-Data
tier: sonnect
size: 中
title: "迁移运行器（relay/node 共用）+ 应用 0001 + 仓储基类（Kysely）"
dependsOn: ["001"]
blocks: ["005", "007"]
reqs: "REQ-F-002"
allowedPaths: ["scripts/database/**", "apps/relay/src/core/db/**", "apps/node/src/core/db/**"]
evidence: docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-003/
```

> 冻结字段（id/slice/title/owner/tier/size/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，修改需走规划变更。

## 1. 归属
- 所属切片：S0
- 来源需求：REQ-F-002（tasks.v1.json 原值 `REQ-F-002`）
- 来源方案：ADR-003（两侧 SQLite WAL 单写者，Kysely 保留迁移路径）、ADR-009（better-sqlite3 + Kysely）、ADR-012（DB 列 snake_case、时间 INTEGER 毫秒）；ownership-matrix §1（仓储基类由本卡提供）

## 2. 目标
提供 relay/node 共用的迁移运行器，可把 `database/migrations/{relay,node}/0001_init.sql` 幂等地应用到 SQLite（WAL），并提供 Kysely 仓储基类与测试库工厂，供各模块仓储实现复用。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-003-存储.md、ADR-009-后端运行栈.md、ADR-012-全局命名与格式.md
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §7（数据归属）
  - docs/WorkFleet-V0.0.4/04_planning/ownership-matrix.md §1（仓储归属偏离说明）
- 契约：
  - `database/migrations/relay/0001_init.sql`（只读：表 `schema_migrations`、`tenants`、`users`、`memberships`、`web_sessions`、`devices`、`pairing_codes`、`conversations`、`messages`、`messages_fts`、`deliveries`、`node_outbox`、`node_inbox_dedupe`、`idempotency_keys`、`audit_log` 等；触发器 `messages_no_update`、`audit_no_update`、`audit_no_delete`）
  - `database/migrations/node/0001_init.sql`（只读：`relay_links`、`agents`、`sessions`、`transcript_index`、`transcript_fts`、`relay_outbox`、`relay_inbox_dedupe`、`prompt_queue`、`write_leases`、`pending_permissions` 等）
  - `packages/contracts/schemas/common/ids.schema.json`（ID 前缀 + ULID 正则，用于仓储基类 `newId(prefix)`）、`schemas/common/timestamp.schema.json`
- 前置任务：TASK-001
- 前置状态：TASK-001 已合并（根脚本 `db:migrate`=`tsx scripts/database/migrate.ts`）

## 4. 输出
- `scripts/database/migrate.ts`（CLI：`--target relay|node --db <path>`；读取 `database/migrations/<target>/*.sql`，按版本号排序，只执行 `schema_migrations` 中未记录的版本，单事务）
- `scripts/database/lib/migrator.ts`（共用实现，供两侧 core/db 调用）
- `apps/relay/src/core/db/{connection.ts,migrate.ts,repository-base.ts,testing.ts,index.ts}`
- `apps/node/src/core/db/{connection.ts,migrate.ts,repository-base.ts,testing.ts,index.ts}`
- `repository-base.ts`：`BaseRepository<DB>`（事务 `withTx()`、`newId(prefix)` 生成前缀+ULID、`toDbTime()/fromDbTime()` RFC3339↔毫秒、乐观锁 `updateWithVersion()` 冲突抛 `CONFLICT`）
- `testing.ts`：`openTestDatabase()` 在临时目录建库并应用 0001，返回 Kysely 实例与 `close()`
- 测试：`apps/relay/tests/unit/core/db/**`、`apps/node/tests/unit/core/db/**`

## 5. Execution Steps
1. [ ] 实现 `scripts/database/lib/migrator.ts`：打开 better-sqlite3，设 `PRAGMA journal_mode=WAL`、`foreign_keys=ON`、`busy_timeout=5000`；按文件名前缀版本排序；以 `schema_migrations` 判定已应用；每个文件在单事务内执行。
2. [ ] 注意 0001 末尾自带 `INSERT INTO schema_migrations(version=1)`：运行器在执行前检查版本，执行后不再重复插入（避免主键冲突）。
3. [ ] 实现 `scripts/database/migrate.ts` CLI 并接到根脚本 `pnpm db:migrate --target relay --db .local/runtime/relay.db`。
4. [ ] 在两侧 `core/db/connection.ts` 封装 Kysely + SqliteDialect（单写者连接；只读查询可另开只读连接），`migrate.ts` 在进程启动时调用共用 migrator。
5. [ ] 实现 `repository-base.ts`（见“输出”），时间与 ID 规则严格按 ADR-012。
6. [ ] 实现 `testing.ts` 的 `openTestDatabase()`，并写单测：迁移幂等（运行两次版本仍为 1）、WAL 已开启、`messages` 的 UPDATE body 被触发器拒绝、`audit_log` DELETE 被拒、`newId('cnv')` 匹配 `^cnv_[0-9A-HJKMNP-TV-Z]{26}$`、乐观锁冲突抛 CONFLICT。
7. [ ] 执行第 7 节命令并保存证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] AC-1：`pnpm db:migrate --target relay --db <tmp>` 与 `--target node` 各执行两次，第二次输出“no pending migrations”，`SELECT max(version) FROM schema_migrations` = 1。
- [ ] AC-2：`PRAGMA journal_mode` 返回 `wal`；`PRAGMA foreign_keys` 返回 1。
- [ ] AC-3：单测断言：`UPDATE messages SET body=...` 抛 `messages is append-only`；`DELETE FROM audit_log` 抛 `audit_log is append-only`。
- [ ] AC-4：`newId()` 生成值通过 `ids.schema.json` 对应正则；`toDbTime('2026-10-17T10:00:00.000Z')` = 1792231200000 往返一致。
- [ ] AC-5：`pnpm -F @workfleet/relay test tests/unit/core/db` 与 `pnpm -F @workfleet/node test tests/unit/core/db` 全绿。

## 7. 验证命令
> 脚本约定（由 TASK-001 定义，全部卡共用）：根 `make install|test|typecheck|lint|contracts|db-migrate|e2e|guard|ci`；根 `pnpm test|typecheck|lint|contracts:gen|contracts:test|db:migrate|e2e`；各包 `pnpm -F @workfleet/<relay|node|web|contracts|testkit> <test|typecheck|lint|build|dev|start>`；`pnpm -F @workfleet/<pkg> test <路径过滤>` 透传给 `vitest run`。
```bash
TMP=$(mktemp -d)
pnpm db:migrate --target relay --db $TMP/relay.db && pnpm db:migrate --target relay --db $TMP/relay.db
pnpm db:migrate --target node  --db $TMP/node.db  && pnpm db:migrate --target node  --db $TMP/node.db
sqlite3 $TMP/relay.db "PRAGMA journal_mode; SELECT max(version) FROM schema_migrations;"
pnpm -F @workfleet/relay test tests/unit/core/db
pnpm -F @workfleet/node test tests/unit/core/db
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-003/
- `test-output.txt`：第 7 节命令的完整输出（含退出码）
- `summary.md`：AC 逐条结论（PASS/FAIL/UNKNOWN）+ 提交哈希

## 9. 允许修改
- `scripts/database/**`
- `apps/relay/src/core/db/**`
- `apps/node/src/core/db/**`
- 明确写出的测试目录（本模块专属；allowedPaths 未含测试路径，按任务指令 §3 在此显式声明，执行前须经主 Agent 确认）：
  - `apps/relay/tests/unit/core/db/**`
  - `apps/node/tests/unit/core/db/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-003/**`（仅证据）

## 10. 禁止修改
- `packages/contracts/**`（契约唯一源，ADR-002）
- `database/migrations/**`（v1 冻结，只能由 Agent-Data 新增文件）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`、`eslint.config.js`（仅 TASK-001/014 可改）
- `docs/**`（`06_validation/evidence/EVD-003/` 除外）
- `apps/relay/src/core/**`（除 `core/db/**`，其余归 TASK-004）
- `apps/node/src/core/**`（除 `core/db/**`，其余归 TASK-007）
- `apps/*/src/modules/**`（各模块仓储实现归各模块任务）

## 11. 依赖与阻塞
- Depends on：TASK-001
- Blocks：TASK-005, TASK-007
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 0001 SQL 在 better-sqlite3 内置 SQLite 版本上执行失败（如 fts5 trigram 需 SQLite ≥3.34）→ 记录版本号，blocked 交 Agent-Data/主 Agent
  - 需要新增/修改 `packages/contracts/**` 中任何 schema、端点、帧或错误码 → 立即停止，标 blocked，写明缺失字段与用途，提交契约变更请求（新任务 + ADR，Agent-Contract 执行）
  - 需要修改 `database/migrations/**`（含新增列/表/索引）→ blocked，交 Agent-Data 以新增迁移文件处理
  - 需要修改本卡“允许修改”之外的路径（含其他任务的模块目录）→ blocked，按所有权矩阵 §1 提交 ADR，不得“先写了再说”

## 12. 建议执行档位
sonnect　理由：迁移运行器与仓储基类是标准样板，表结构已冻结，sonnect 足够。

## 13. 升级条件
- 需要多写者/连接池或跨进程写入方案（超出 ADR-003 单写者）→ 升 opus 评审
- 同一验收连续 2 次失败（cost-budget §4 熔断）→ 停止改代码，升一档（haiku→sonnect→opus），重写任务书后再执行
- 发现必须改契约或迁移才能完成 → 升 opus 做契约语义评审，并将本卡标 blocked（fable 仅在需推翻已冻结契约/需求时启用）

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设（NON_BLOCKING）：better-sqlite3 预编译包内置 SQLite 支持 fts5 trigram（≥3.34）——证据不足/待实测，三平台 CI 由 TASK-014 验证。
- 风险：node 侧 `transcript_fts` 无同步触发器，需 TASK-023 写入时手工同步——本卡在 `repository-base` 注释中提示。
- 本卡不涉及 U-02…U-08。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 执行者自测：AC-1…AC-n 结论 + 第 7 节命令输出摘要
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-003/
- 偏离与遗留：
- 验证者结论：PASS / FAIL / UNKNOWN（待填）
