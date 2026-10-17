# TASK-067：S3 集成/E2E：两中转隔离、两设备路由、写冲突

```yaml
id: TASK-067
slice: S3
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-QA
tier: sonnect
size: 中
title: "S3 集成/E2E：两中转隔离、两设备路由、写冲突"
dependsOn: ["062", "063", "064", "065", "066"]
blocks: ["210"]
reqs: "REQ-F-005/006/032"
allowedPaths: ["tests/integration/s3/**", "tests/e2e/s3/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。

## 1. 归属
- 所属切片：S3（可演示：两台电脑、个人+公司两个中转、主/子项目树；同目录第二个写入者被拒或分到 worktree）
- 来源需求：REQ-F-005/006/032
- 来源方案：ADR-011（E2E 仅 ubuntu）、ADR-005；DEC-029（Fake 测试替身）；slices.md S3 演示脚本

## 2. 目标
用真中转（两实例）+ 真节点 + FakeAgent 自动化验证 S3 演示：两中转隔离、两设备按别名路由与离线排队、同目录写冲突拒绝/worktree。

## 3. 输入
- 文档：
  - `docs/WorkFleet-V0.0.4/04_planning/slices.md`（S3 行）
  - `docs/WorkFleet-V0.0.4/02_requirements/features/REQ-F-005/006/032`
  - `docs/WorkFleet-V0.0.4/03_solution/architecture.md` §3 端口段（5110–5119 E2E 测试中转实例）
- 契约：
  - `packages/contracts/api/relay.openapi.json`：projects、devices（pairing-codes/claim/primary）、agents、conversations/messages 端点
  - `packages/contracts/api/node-local.openapi.json`：`/local/v1/relay-links`
  - `packages/contracts/protocol/frames/agent.prompt|agent.output|error`
  - `packages/contracts/errors/error-codes.json`：DEVICE_OFFLINE、AGENT_BUSY_WRITE_LEASE、NOT_FOUND
  - `packages/contracts/ux/ux-states.json`：project_tree、device_list、chat 的 data-ux-state
- 前置任务：TASK-062, TASK-063, TASK-064, TASK-065, TASK-066
- 前置状态：TASK-062/063/064/065/066 全部合并；TASK-008 testkit（FakeAgent、FakeRelay）与 TASK-013 Playwright 骨架可用

## 4. 输出
- `tests/integration/s3/`：relay-isolation.test.ts、device-routing.test.ts、write-lease.test.ts（vitest，起真进程）
- `tests/e2e/s3/`：s3-demo.spec.ts（Playwright：项目树 → 两设备 → 发消息 → 离线提示）及其 fixtures
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-067/`（验证日志、截图或录制摘要、结论 README.md）

## 5. Execution Steps
1. [ ] 编写测试夹具：在 5110、5111 起两个中转实例（独立数据目录），在临时目录起两个节点进程（node-A、node-B），全部用 FakeAgent。
2. [ ] 集成用例 1（隔离）：node-A 同时连 5110 与 5111；在 5110 注册的智能体对 5111 不可见；跨中转 agent.prompt 被拒；两库 grep 不到对方消息。
3. [ ] 集成用例 2（两设备路由）：同账号两节点各一智能体 z1/z2；`@z1`、`@z2` 分别到达对应节点；停掉 node-B 后发 `@z2` 收到“设备离线，已排队”，重启后恰好收到一次。
4. [ ] 集成用例 3（写冲突）：两个 write 模式 FakeAgent 指向同一 git 临时仓库；第二个收到 AGENT_BUSY_WRITE_LEASE；切换策略后得到 worktree 路径。
5. [ ] E2E：Playwright 驱动中转控制台建主项目+子项目、查看跨项目视图、设主设备、在聊天中观察离线提示（断言 data-ux-state）。
6. [ ] 所有用例使用随机临时目录与固定端口段，结束时清理；失败时保留日志到证据目录。
7. [ ] 在 ubuntu 上连续跑 3 次确认无抖动，把结果与耗时写入证据。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] `tests/integration/s3` 三组用例全部通过且连续 3 次无抖动
- [ ] 隔离用例断言：两个中转的 relay.db 中互相 grep 不到对方的消息文本与令牌
- [ ] 离线排队用例：重连后消息恰好投递一次（按 messageId 计数 = 1）
- [ ] `tests/e2e/s3` Playwright 用例通过（ubuntu），截图保存到证据目录
- [ ] 越界检查只输出 SCOPE OK

## 7. 验证命令
```bash
pnpm exec vitest run tests/integration/s3
pnpm exec playwright test tests/e2e/s3 --reporter=list
for i in 1 2 3; do pnpm exec vitest run tests/integration/s3 || exit 1; done
# 越界检查：只输出 SCOPE OK 才算通过
git diff --name-only origin/main...HEAD | grep -vE '^(tests/integration/s3/|tests/e2e/s3/|docs/WorkFleet-V0\.0\.4/06_validation/evidence/EVD-067/)' || echo 'SCOPE OK'
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-067/
- `README.md`：结论（PASS/FAIL/UNKNOWN）、执行环境（OS、Node 版本、提交哈希）
- `test-output.txt`：§7 命令完整输出

## 9. 允许修改
- `tests/integration/s3/**`
- `tests/e2e/s3/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-067/**`（证据目录；依据 `04_planning/ownership-matrix.md` §4 全局例外，tasks.v1.json 未列出）

## 10. 禁止修改
- packages/contracts/**（契约唯一源，ADR-002；发现缺陷只登记跟进项）
- database/migrations/**（v1 冻结，仅 Agent-Data 新增）
- Makefile、.github/**、.dependency-cruiser.cjs、根目录 package.json / apps/*/package.json（Agent-Guard 所有）
- apps/**、packages/testkit/**（发现被测缺陷只提 issue，不修实现）
- tests/e2e/s1/**、s2/** 等其他切片目录

## 11. 依赖与阻塞
- Depends on：TASK-062, TASK-063, TASK-064, TASK-065, TASK-066
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - FakeRelay/FakeAgent 不支持本场景（如多实例端口参数），且 packages/testkit 不在本任务路径内
  - 任一被测任务未合并或其验收未通过
  - Playwright 骨架（TASK-013 的 playwright.config.ts）未覆盖 tests/e2e/s3

## 12. 建议执行档位
sonnect　理由：测试脚本编写，断言来自已冻结契约，主力档。

## 13. 升级条件
- 测试暴露跨模块设计缺陷（隔离失败）→ 升 opus 仲裁并回退被测任务
- 同一用例 2 次失败 → 熔断，重写任务书

## 14. 预估规模
中(≈1d)　是否小于 2 小时：否

## 15. 风险与假设
- 无 U-xx 直接关联；U-08：被测任务延期会推迟本卡。
- 假设：worktree 用例的 git 在 CI ubuntu 镜像中可用。
- 假设（推断）：pnpm 包名 `@workfleet/relay`、`@workfleet/node`、`@workfleet/web` 与 vitest/playwright 脚本以 TASK-001/014 落地为准；若命名不同，只替换验证命令中的包名，不改步骤。
- 跟进项（只登记，不在本任务修改）：
  - 规划：tasks.v1.json 中 067 未依赖 TASK-008/013（经由传递依赖存在，但未显式列出）

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 证据：docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-067/
- 验证者结论：
- 遗留问题 / 跟进项编号：
