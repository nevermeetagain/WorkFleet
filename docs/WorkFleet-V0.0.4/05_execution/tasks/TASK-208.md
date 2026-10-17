# TASK-208：画像向导 P1/P2（Web）

```yaml
id: TASK-208
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-App
tier: sonnect
size: 中
title: "画像向导 P1/P2（Web）"
dependsOn: ["204", "207"]
blocks: ["210"]
reqs: "REQ-F-031"
allowedPaths: ["apps/web/src/features/onboarding/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-031
- 来源方案：REQ-F-031（画像向导 P1/P2）；DEC-034/038（REQ-C-004）；DEC-046（微信不向他人群发）；DEC-057（Web 为默认渠道）

## 2. 目标
Web 向导按画像生成默认配置：P1（微信 + 本机 CLI，管理模式）与 P2（飞书 + 外部智能体，通知/团队模式）；向导中执行配对、渠道绑定、默认绑定创建与 dry-run 预览，遇 `BOT_IDENTITY_CONFLICT` 阻断，并引导开启 PWA 推送。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（§1 画像 P1/P2、REQ-F-031、REQ-F-016、REQ-NF-005 明示中转可见明文、MUST NOT 第 4 条）
  - docs/WorkFleet-V0.0.4/04_planning/slices.md（S10）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-034、DEC-046、DEC-057）
- 契约：
  - packages/contracts/api/relay.openapi.json：`/api/v1/devices/pairing-codes`、`/api/v1/channels`、`/api/v1/channels/{id}/qr-login`、`/api/v1/channels/{id}/credential`、`/api/v1/routes`、`/api/v1/routes/dry-run`、`/api/v1/agents`、`/api/v1/adapters/input`、`/api/v1/adapters/channel`
  - packages/contracts/errors/error-codes.json：`BOT_IDENTITY_CONFLICT`（向导阻断 + 说明）、`ROUTE_INVALID`、`PAIRING_CODE_INVALID`
  - packages/contracts/schemas/entities/route.schema.json（mode management/notification/team）；adapters/channel-kinds.v1.json
  - packages/contracts/ux/ux-states.json（6 态规范；无 onboarding screen）
- 前置任务：TASK-204, TASK-207
- 前置状态：TASK-204（PWA 订阅 UI）、TASK-207（身份冲突检测）已合并；渠道与绑定页组件（TASK-046/104）可复用。

## 4. 输出
- apps/web/src/features/onboarding/（向导状态机、P1/P2 步骤组件、默认配置生成器、隐私提示组件）
- apps/web/src/features/onboarding/__tests__/
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-208/`（见 §8）

## 5. Execution Steps
1. [ ] 向导状态机：选画像 → 隐私提示（“中转可见 IM 明文”，REQ-NF-005，需勾选确认）→ 配对节点 → 渠道 → 智能体 → 默认绑定 + dry-run → 推送开启（可跳过）→ 完成；可中断续做（状态存服务端已创建对象推导，不存本地敏感数据）。
2. [ ] P1：微信扫码（复用渠道扫码组件）→ 选本机已探测的 CLI 智能体 → 创建 management 绑定（接收人=本人）；提示关闭 ZCode 自带微信 Bot（REQ-C-004）。
3. [ ] P2：飞书应用凭据 → 明示“不得与 OpenClaw 等共用同一飞书应用”→ 外部智能体（Coze/Webhook/ACP）→ notification 或 team 绑定；校验通知模式接收人不是他人的微信（DEC-046，服务端 `ROUTE_INVALID` 时展示原因）。
4. [ ] 任一步收到 `BOT_IDENTITY_CONFLICT` → 阻断并显示说明与处理建议，不允许跳过。
5. [ ] dry-run 步骤展示一条样例消息会去哪、每个接收人可见内容。
6. [ ] 6 态实现与组件测试（MSW）：P1/P2 全流程、冲突阻断、ROUTE_INVALID 展示；运行验证命令并存证。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] P1 全流程（MSW）结束时依次调用配对、渠道、智能体、management 绑定、dry-run 端点且参数正确。
- [ ] P2 全流程结束时创建 notification/team 绑定并展示 dry-run 结果。
- [ ] `BOT_IDENTITY_CONFLICT` 时向导停在当前步且无“跳过”（测试）。
- [ ] 隐私提示未确认时无法进入下一步（测试）。
- [ ] 向导各步 6 态可用 `data-ux-state` 断言；`pnpm --filter ./apps/web build` 成功。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-208/
pnpm --filter ./apps/web exec vitest run src/features/onboarding --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-208/vitest.txt
pnpm --filter ./apps/web build | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-208/build.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-208/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-208/
- `vitest.txt`、`build.txt`、`guard.txt`
- `screenshots/`（P1、P2 各步骤、冲突阻断）

## 9. 允许修改
- `apps/web/src/features/onboarding/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-208/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-208/` 除外，见 ownership-matrix §4）
- apps/web/src/app/**、pages/**（向导入口路由挂载不在本卡路径）
- apps/web/src/features/channels/**、routes/**、pwa/**（复用不修改）

## 11. 依赖与阻塞
- Depends on：TASK-204, TASK-207
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 向导入口需要路由/页面挂载（app/** 或 pages/onboarding，均不在允许路径）→ 报主 Agent。
  - ux-states.json 无 onboarding screen → 按通用 6 态实现并报缺陷。

## 12. 建议执行档位
sonnect　理由：前端流程编排，调用已有端点，可逆。

## 13. 升级条件
- 画像默认配置与 MUST NOT（DEC-046）存在冲突需改规则 → opus。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 假设：P1/P2 的默认值以 PRD §1 画像描述为准（推断细节写在 EVD）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-208/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-208.md`）
