# TASK-064：workspace-guard：写租约、自动 git worktree、AGENT_BUSY_WRITE_LEASE

```yaml
id: TASK-064
slice: S3
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: sonnect
size: 中
title: "workspace-guard：写租约、自动 git worktree、AGENT_BUSY_WRITE_LEASE"
dependsOn: ["021"]
blocks: ["067"]
reqs: "REQ-F-032"
allowedPaths: ["apps/node/src/modules/workspace-guard/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S3（可演示：两台电脑、个人+公司两个中转、主/子项目树；同目录第二个写入者被拒或分到 worktree）
- 来源需求：REQ-F-032
- 来源方案：DEC-053、G10；architecture §4.2 `workspace-guard`；ADR-003

## 2. 目标
节点侧对同一规范化工作目录只允许一个写入型智能体持有排他写租约；冲突时按配置拒绝（AGENT_BUSY_WRITE_LEASE）或自动为后来者创建 git worktree 并改用该目录。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §4.2（workspace-guard：写入租约或自动 git worktree）
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-032-同目录并发写保护.md`
  - `docs/WorkFleet-V0.0.4/02_requirements/non-functional/REQ-NF-006-可移植.md`（长路径 >260、CRLF）
- 契约：
  - `packages/contracts/errors/error-codes.json`：AGENT_BUSY_WRITE_LEASE（409，retryable，ui“该目录正被 {alias} 写入，可选 worktree”）
  - `packages/contracts/events/domain-events.json`：lease.acquired / lease.released（幂等键 leaseId）
  - `packages/contracts/schemas/entities/agent.schema.json`：writeMode read_only/write、workdir
  - `packages/contracts/protocol/frames/error.schema.json`（向中转回报冲突码）
  - `database/migrations/node/0001_init.sql`：`write_leases`（mode exclusive/worktree、worktree_path、heartbeat_at、`ux_write_leases_active` 对 exclusive 部分唯一）
- 前置任务：TASK-021
- 前置状态：TASK-021 ACP Host 已合并，会话启动前存在可调用的写租约钩子（见阻塞条件）

## 4. 输出
- `apps/node/src/modules/workspace-guard/domain/`：路径规范化（realpath、Windows/macOS 大小写不敏感、\\?\ 长路径）、租约规则
- `apps/node/src/modules/workspace-guard/application/`：acquire / heartbeat / release / reclaimStale / allocateWorktree
- `apps/node/src/modules/workspace-guard/infrastructure/`：write_leases 仓储、git CLI 封装（`git worktree add/remove`）
- `apps/node/src/modules/workspace-guard/index.ts`：公开 `acquireWriteLease(agent, policy)`、`releaseWriteLease(leaseId)`
- `apps/node/src/modules/workspace-guard/__tests__/`
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-064/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 实现 canonicalize(workdir)：realpath + 统一分隔符；Windows/macOS 按大小写不敏感比较；支持 >260 字符路径；单测覆盖符号链接指向同一目录。
2. [ ] 实现 acquire：read_only 智能体直接放行不建租约；write 智能体插入 exclusive 行，依赖 `ux_write_leases_active` 保证原子性，唯一冲突即判定被占用。
3. [ ] 冲突策略 reject：抛 AGENT_BUSY_WRITE_LEASE，details 带占用者 alias（用于 ui 文案占位 {alias}）。
4. [ ] 冲突策略 worktree：目录须为 git 仓库（否则退回 reject）；`git worktree add <节点数据目录>/worktrees/<alias>-<leaseId> -b wf/<alias>/<leaseId>`，插入 mode=worktree 行并返回新 workdir。
5. [ ] 实现心跳与过期回收：持有者每 30 s 更新 heartbeat_at；进程崩溃后超过阈值（默认 120 s，可配置）的租约由 reclaimStale 释放；释放时发 lease.released。
6. [ ] release 时 exclusive 置 released_at；worktree 模式保留目录（不自动删，避免丢失未提交改动），在证据中说明。
7. [ ] 写测试：两个写入型 FakeAgent 同目录 → 第二个被拒/分到 worktree；read_only 不受限；崩溃回收；Windows 路径大小写；并发 acquire 只有一个成功。
8. [ ] 在 index.ts 暴露公开 API，并在证据中记录 TASK-021 Host 的接入点（文件与函数名）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 两个 writeMode=write 智能体并发 acquire 同一目录，恰好 1 个成功、另一个得到 AGENT_BUSY_WRITE_LEASE（重复 100 次无例外）
- [ ] 策略为 worktree 时第二个得到新的 worktree 路径，`git worktree list` 可见，write_leases 有 mode=worktree 行
- [ ] read_only 智能体在被占用目录可启动，不写 write_leases
- [ ] 持有者心跳超时后租约被回收并发出 lease.released
- [ ] Windows 用例：`C:\Repo` 与 `c:\repo\` 判定为同一目录（三平台矩阵）
- [ ] 越界检查只输出 SCOPE OK；`make guard` 通过

## 7. 验证命令
```bash
pnpm --filter @workfleet/node exec vitest run src/modules/workspace-guard
pnpm --filter @workfleet/node exec tsc --noEmit
make guard
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(apps/node/src/modules/workspace-guard/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-064/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-064/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `apps/node/src/modules/workspace-guard/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-064/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/node/src/modules/agents/**（接入点由 Host 所有者实现）
- apps/node/src/modules/sessions/**

## 11. 依赖与阻塞
- Depends on：TASK-021
- Blocks：TASK-067
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - TASK-021 Host 未预留“启动写入会话前调用 workspace-guard”的端口，而本任务 allowedPaths 不含 agents/**：停止并请求 Agent-Node 规划补一个接线小任务或扩大路径
  - 冲突策略（reject 或 worktree）的默认值与配置位置在契约中不存在（agent.config 无字段）：默认取 reject，若需可配需规划裁决
  - 目标机器无 git 可执行文件且策略为 worktree

## 12. 建议执行档位
sonnect　理由：单模块并发控制，有唯一索引兜底、行为可完全单测，主力档足够。

## 13. 升级条件
- 发现需要跨进程/跨节点的租约（例如两台设备共享网络盘目录）→ 升 opus 出 ADR
- worktree 合并回主分支的策略被要求纳入 v1 → 升 opus

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联；与 U-08 相关：接线点缺失会导致 S3 演示延期。
- 假设：租约只在单个节点内生效；同一目录被两台设备同时写入不在 v1 范围（推断，architecture 只描述节点内）。
- 假设：worktree 目录位于节点数据目录下，不污染用户仓库根（推断）。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - 规划：TASK-064 allowedPaths 不含 agents Host 接线位置，需补接线任务
  - Agent-Contract：agent.configSchema 无“写冲突策略（reject/worktree）”字段

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-064/
- 验证者结论：
- 遗留问题 / 跟进项编号：
