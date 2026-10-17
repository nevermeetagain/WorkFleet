# TASK-203：Web Push 发送（VAPID）与订阅管理（中转）

```yaml
id: TASK-203
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Relay
tier: sonnect
size: 小
title: "Web Push 发送（VAPID）与订阅管理（中转）"
dependsOn: ["125"]
blocks: ["204"]
reqs: "REQ-F-015"
allowedPaths: ["apps/relay/src/modules/notifications/infrastructure/webpush/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-015
- 来源方案：ADR-014（PWA 与 Web Push，VAPID）；DEC-057；DEC-023（p0–p3）

## 2. 目标
中转实现 Web Push 发送：VAPID 密钥生成与保管、`GET /api/v1/push/vapid-public-key`、`POST /api/v1/push-subscriptions` 登记（按 endpoint 去重）、按 `minPriority` 过滤推送、失效订阅（404/410）自动清理；作为 notifications 的一个投递通道。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-014-PWA与WebPush.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-015、U-07）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-023、DEC-057）
- 契约：
  - packages/contracts/api/relay.openapi.json：`GET /api/v1/push/vapid-public-key`（public）、`POST /api/v1/push-subscriptions`（notification.subscribe；body endpoint、keys.p256dh/auth、minPriority）
  - packages/contracts/schemas/common/ids.schema.json（`pushSubscriptionId`）；identity/permissions.json：`notification.subscribe`（三角色均可，且为 viewer 唯一可调用的非 GET）
  - database/migrations/relay/0001_init.sql：`push_subscriptions`（endpoint 唯一、min_priority 默认 p1、failed_count）
- 前置任务：TASK-125
- 前置状态：TASK-125 notifications（p0–p3、备用渠道）已合并，提供通道注册点。

## 4. 输出
- apps/relay/src/modules/notifications/infrastructure/webpush/（VAPID 密钥管理、订阅仓储、发送器、失效清理、通道适配到 notifications）
- apps/relay/src/modules/notifications/infrastructure/webpush/__tests__/
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-203/`（见 §8）

## 5. Execution Steps
1. [ ] 选库：评估 Node 端 Web Push 实现（如 npm `web-push`）的许可与维护状态，写入 EVD；**许可待核实**后再引入，第三方声明交 Guard 写 THIRD_PARTY_NOTICES。
2. [ ] VAPID：首次启动生成密钥对；私钥与中转主密钥同等保管（主机密钥文件 0600 或环境变量，TR-08），不入库、不进日志；公钥经端点返回。
3. [ ] 订阅：按 endpoint upsert 到当前用户；`minPriority` 缺省 p1；校验 endpoint 为 https URL。
4. [ ] 发送：notifications 发出 ≥ minPriority 的通知时对该用户全部订阅推送（payload 只含标题、简短正文、跳转 URL，不含消息全文）；404/410 → 删除订阅；其他失败 failed_count+1，连续 ≥5 次删除（推断阈值）。
5. [ ] 写测试：本地假推送服务接收并校验 VAPID JWT 头与加密载荷格式；去重、优先级过滤、410 清理、私钥不出现在日志。
6. [ ] iOS 行为（U-07）：PRD 把实测分配给本卡，但 PWA 安装界面在 TASK-204 才存在 → 本卡只做服务端；iOS 真机实测记录移交 TASK-204/210，在 EVD 注明。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 假推送服务收到的请求带合法 VAPID 授权头与 aes128gcm 加密载荷（测试解析断言）。
- [ ] 同一 endpoint 重复登记只保留 1 行；p2 通知不推给 minPriority=p1 的订阅。
- [ ] 推送服务返回 410 后该订阅被删除（测试）。
- [ ] VAPID 私钥不出现在 relay.db 与日志（grep 0 命中）。
- [ ] `make guard` 通过。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-203/
pnpm --filter ./apps/relay exec vitest run src/modules/notifications/infrastructure/webpush --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-203/vitest.txt
pnpm --filter ./apps/relay exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-203/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-203/guard.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-203/
- `vitest.txt`、`tsc.txt`、`guard.txt`
- `library-choice.md`（库、许可、版本；证据标签）

## 9. 允许修改
- `apps/relay/src/modules/notifications/infrastructure/webpush/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-203/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-203/` 除外，见 ownership-matrix §4）
- apps/relay/src/modules/notifications/ 下除 infrastructure/webpush 外文件（含 interfaces/http）
- THIRD_PARTY_NOTICES（Guard 所有）

## 11. 依赖与阻塞
- Depends on：TASK-125
- Blocks：TASK-204
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - “订阅管理”在契约中只有登记，无列出/删除订阅端点（已扫描 relay.openapi.json 未找到 `DELETE /api/v1/push-subscriptions/{id}`）：用户无法主动退订 → 报契约缺陷；本卡不得私加端点。
  - 两个端点的接口层（notifications/interfaces）不在允许路径：若 TASK-125 未预留委托 → blocked。
  - 所选库许可与 Apache-2.0 不兼容 → 改自写 VAPID/加密（RFC 8291/8292）并升级档位评估。

## 12. 建议执行档位
sonnect　理由：标准协议 + 现成库，服务端逻辑小。

## 13. 升级条件
- 需要自写 Web Push 加密（无合规库）→ opus（密码学实现风险）。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
小　是否小于 2 小时：否

## 15. 风险与假设
- 证据不足：iOS Web Push 行为（ADR-014 写“iOS 16.4+ 添加到主屏幕才支持”，部分确认），需真机实测。
- 假设：失败 5 次清理（推断）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-203/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-203.md`）
