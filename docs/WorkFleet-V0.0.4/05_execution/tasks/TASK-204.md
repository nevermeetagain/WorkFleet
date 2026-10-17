# TASK-204：PWA：manifest、service worker、订阅 UI

```yaml
id: TASK-204
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-App
tier: sonnect
size: 中
title: "PWA：manifest、service worker、订阅 UI"
dependsOn: ["203"]
blocks: ["208"]
reqs: "REQ-F-015"
allowedPaths: ["apps/web/src/pwa/**", "apps/web/public/manifest.webmanifest"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-015
- 来源方案：ADR-014；ADR-008（PWA）；DEC-057（不接 IM 也能在手机收到审批/完成/失败/阻塞）

## 2. 目标
Web 可安装为 PWA（manifest + service worker），用户在设置中一键开启推送（权限请求、订阅登记、minPriority 选择），收到推送点击后跳转到对应会话/审批；iOS 给出“添加到主屏幕”指引并记录真机实测结果。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-014-PWA与WebPush.md
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-008-前端.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-015、U-07、REQ-NF-011）
- 契约：
  - packages/contracts/api/relay.openapi.json：`GET /api/v1/push/vapid-public-key`、`POST /api/v1/push-subscriptions`
  - packages/contracts/ux/ux-states.json：screen `notifications_settings`（6 态）
  - packages/contracts/errors/error-codes.json：`FORBIDDEN`、`RATE_LIMITED`
- 前置任务：TASK-203
- 前置状态：TASK-203 已合并。

## 4. 输出
- apps/web/public/manifest.webmanifest（name、short_name、start_url、display standalone、theme/background、lang zh-CN、icons 引用）
- apps/web/src/pwa/（service worker 源码：push → showNotification、notificationclick → 打开/聚焦目标 URL；注册逻辑；订阅 UI 组件 `notifications_settings`；iOS 指引组件）
- apps/web/src/pwa/__tests__/
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-204/`（见 §8）

## 5. Execution Steps
1. [ ] manifest：按 W3C Web App Manifest 编写；icons 文件路径若不在允许路径（public/icons/）则报缺陷并暂引用现有资源。
2. [ ] service worker：只处理 push 与 notificationclick，不缓存 API 响应（避免泄露与陈旧数据）；可选缓存应用壳静态资源。
3. [ ] SW 作用域：SW 需从站点根路径提供才能控制全站；`apps/web/public/` 下除 manifest 外不在允许路径、`vite.config.ts` 也不在 → 先实现源码与构建产物命名约定，按阻塞条件处理。
4. [ ] 订阅 UI：用户点击后才请求通知权限 → 拉 VAPID 公钥 → `pushManager.subscribe` → POST 订阅；选择 minPriority；实现 6 态；权限被拒时显示恢复说明。
5. [ ] iOS：检测非独立显示模式的 iOS Safari 显示“添加到主屏幕后才能接收推送”指引（依据 ADR-014，部分确认）。
6. [ ] 测试：SW 处理器单测（模拟 push/notificationclick 事件）；Playwright（Chromium）验证 manifest 可解析、SW 注册成功、订阅流程在 mock PushManager 下 POST 正确；真机：Android Chrome 与 iOS（16.4+）各实测一次推送到达，记录到 EVD（无设备则写“未实测”）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] manifest 通过解析校验（Playwright 读取 `link[rel=manifest]` 并断言必填字段）。
- [ ] SW 注册成功且 push 事件触发 `showNotification`、点击打开正确 URL（单测）。
- [ ] 订阅 UI 6 态可断言；只在用户手势后请求权限（测试）。
- [ ] 真机记录：Android Chrome 推送到达结果 + iOS 16.4+ 主屏 PWA 推送结果（各 1 条，含系统版本；未测写“未实测”）。
- [ ] `pnpm --filter ./apps/web build` 成功。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-204/
pnpm --filter ./apps/web exec vitest run src/pwa --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-204/vitest.txt
pnpm --filter ./apps/web build | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-204/build.txt
pnpm exec playwright test --grep @pwa --reporter=list | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-204/playwright-pwa.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-204/
- `vitest.txt`、`build.txt`、`playwright-pwa.txt`
- `device-tests.md`（Android/iOS 真机结果、系统版本、截图；U-07 结论与证据标签）

## 9. 允许修改
- `apps/web/src/pwa/**`
- `apps/web/public/manifest.webmanifest`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-204/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-204/` 除外，见 ownership-matrix §4）
- apps/web/vite.config.ts、apps/web/index.html、apps/web/src/app/**（不在本卡路径）
- apps/web/public/ 下除 manifest.webmanifest 外文件

## 11. 依赖与阻塞
- Depends on：TASK-203
- Blocks：TASK-208
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - SW 文件需放在 `apps/web/public/`（或改 vite.config.ts 输出到根）才能获得全站作用域，均不在允许路径 → 标 blocked，请主 Agent 扩展 allowedPaths（`apps/web/public/sw.js`、`apps/web/public/icons/**`）或派 Guard/App 小任务。
  - manifest 的 `<link rel=manifest>` 需在 `apps/web/index.html` 中声明（不在允许路径）→ 同上。
  - Playwright `@pwa` 用例需放在 tests/e2e（QA 所有，不在本卡路径）：若无现成 QA 用例，改为在 EVD 记录手动步骤并报缺陷。

## 12. 建议执行档位
sonnect　理由：前端标准 API（Manifest、Service Worker、Push API）实现，可逆。

## 13. 升级条件
- iOS 实测证明 ADR-014 前提不成立（主屏 PWA 也收不到推送）→ opus 修订 ADR-014 回退策略。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 证据不足：iOS Web Push（U-07），须真机。
- 风险：Playwright 无法驱动真实推送服务，只能 mock PushManager。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-204/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-204.md`）
