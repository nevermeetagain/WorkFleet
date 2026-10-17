---
id: WF-MILESTONES
type: milestone
title: 里程碑（M0…M10 ↔ 切片 S0…S10）
status: active
version: V0.0.4
created: 2026-10-17
sources: [04_planning/slices.md, 04_planning/dag.md, 05_execution/task-index.md, 02_requirements/product-requirements.md]
---

# 里程碑

> - 一个里程碑 = 一个垂直切片完成（文档体系 §13）。可演示行为以 `slices.md` 为准，任务以 `05_execution/task-index.md` 为准。
> - **不写日期**：工期与人力未裁定（U-08 / A-07）。
> - **通用退出条件**（每个里程碑都必须满足，下文不再重复）：
>   1. 该切片全部任务状态为 done（Done 定义见 `current-plan.md §11`）；
>   2. 该切片 E2E/集成任务由独立验证者判定 **PASS**，VAL 与 EVD 齐全（`06_validation/`）；
>   3. 按 `slices.md` 的演示脚本从干净环境复现一遍，录屏或截图入 EVD；
>   4. `make guard` 与 CI 三平台矩阵在合并提交上通过；
>   5. `00_governance/risks.md` 中与本切片相关的风险已复核、假设状态已更新；
>   6. 未修改冻结契约（`packages/contracts/**`、`database/migrations/**`），或修改已走“新任务 + ADR”。

| 里程碑 | 切片 | 目标（可演示行为） | 包含需求 | 专属退出条件 | 关联方案 | 关联任务 |
|---|---|---|---|---|---|---|
| **M0 步行骨架** | S0 | 注册 → 生成配对码 → 本机节点配对上线 → Web 发消息 → FakeAgent 回声显示；错误统一格式；一张表一次迁移 | REQ-F-001、REQ-F-002、REQ-F-015（部分）；REQ-F-003（权限拦截器）；REQ-NF-004/006/009；REQ-C-001/007 | TASK-013 E2E PASS（真中转 + 真节点 + FakeAgent）；TASK-014 守卫在 PR 上生效（故意违规的样例被拦截）；契约生成物无漂移 | ADR-001/002/003/004/005/006/009/011/012 | TASK-001…014 |
| **M1 真实 ACP + Web 对话** | S1 | 在 Web 与真 Claude Code 多轮对话；`/clear`、`/history`、审批一次文件写入 | REQ-F-007、REQ-F-018、REQ-F-019、REQ-F-020、REQ-F-015 | TASK-030 PASS；Claude Code/Codex/Cursor 夹具 + 真机冒烟记录（EVD-022）；ACP SDK 版本锁定（A-04） | ADR-007/008 | TASK-021…030 |
| **M2 微信管理模式** | S2 | 控制台扫码一次；微信里 `@z1`/`@cc1` 分发、引用回复溯源、`Y1` 审批、额度不足提示续期 | REQ-F-009、REQ-F-016、REQ-F-017、REQ-F-020、REQ-NF-001/003 | TASK-048 PASS；TASK-041 真机结论写明 U-02/U-04（A-01/A-03 状态更新为 confirmed/refuted）；R-01 复核 | ADR-010 | TASK-041…048 |
| **M3 项目·多设备·多中转·写保护** | S3 | 两台电脑、个人 + 公司两个中转、主/子项目树；同目录第二个写入者被拒或分到 worktree | REQ-F-004、REQ-F-005、REQ-F-006、REQ-F-032 | TASK-067 PASS（两中转隔离、两设备路由、写冲突三类用例） | ADR-001/005 | TASK-061…067 |
| **M4 输入广度** | S4 | 13 个 ACP 智能体 + Coze + Webhook 冒烟矩阵全部有结论 | REQ-F-007、REQ-F-008、REQ-NF-008 | TASK-087 矩阵：每个智能体“通过”或“失败 + 原因”（ZCode、Copilot 允许实验失败）；EVD-087 汇总 | ADR-007 | TASK-081…087 |
| **M5 飞书 + 团队/通知 + 汇总屏障** | S5 | 场景 2：三个来源汇总后分别发给老板与数据部；通知模式两人回话分会话 | REQ-F-010、REQ-F-016、REQ-F-017、REQ-F-021 | TASK-105 PASS；飞书卡片回调方式结论（A-12） | ADR-010 | TASK-101…105 |
| **M6 其余四个 IM + 健康告警** | S6 | QQ/钉钉/Telegram/Discord 收发与审批；渠道断开 60 秒内 p0 告警到备用渠道 | REQ-F-011、REQ-F-012、REQ-F-013、REQ-F-014、REQ-F-030、REQ-NF-008 | TASK-126 渠道一致性套件对全部适配器 PASS；QQ 配额结论（R-06） | ADR-010 | TASK-121…126 |
| **M7 多用户·权限·审计·分身** | S7 | 老板只看汇总字段、数据部看明细；审计查到每条出站；本机分身页可导出 | REQ-F-003、REQ-F-027、REQ-F-028、REQ-F-029、REQ-NF-004/005 | TASK-146 安全审查 PASS（越权矩阵逐格、密钥扫描、提示注入标记） | ADR-006 | TASK-141…146 |
| **M8 模型配置 + 总控把关** | S8 | 配模型与日上限；总控对每条输出分级；超限降级；`/boss` 对话不打断任务 | REQ-F-022、REQ-F-023、REQ-F-026、REQ-NF-010 | TASK-166 PASS；中转库与日志中 grep 不到模型 Key（REQ-F-026）；opus 券超额已获批或已按替代方案执行（R-15） | ADR-013 | TASK-161…166 |
| **M9 总控会议 + 导入任务** | S9 | 三个智能体开会出纪要与分派；导入任务卡目录直接分派 | REQ-F-024、REQ-F-025 | TASK-184 PASS；会议四类事件可回放 | ADR-013 | TASK-181…184 |
| **M10 体验与运维（v1 验收）** | S10 | 急停 5 秒内生效；PWA 推送；doctor；恢复密钥；画像向导；三平台安装包 | REQ-F-001、REQ-F-015、REQ-F-031、REQ-F-033、REQ-F-034、REQ-F-035；REQ-NF-001/002/011 | M0…M9 均已退出；TASK-210 v1 验收回归 PASS **且基线指标首次测量完成**（`baseline-metrics.md`）；TASK-211 文档同步完成；`07_release/` 出 REL 记录 | ADR-014 | TASK-201…211 |

## 依赖关系（里程碑级）
```text
M0 → M1 ─┬→ M4
         └→ M2 ─┬→ M3 → M8 ─┬→ M9
                ├→ M5 ─┐    └→ M10
                └→ M6 ─┼──────→ M10
           M3、M5、M2 ─┴→ M7
```
由 `dag.md` 任务边归纳（跨切片边举例）：M4 只依赖 M1（TASK-081…084 ← TASK-022，TASK-085/086 ← TASK-021）；M3 依赖 M2（TASK-062 ← TASK-044）与 M1（TASK-063 ← TASK-023）；M7 依赖 M3（TASK-141 ← TASK-061、TASK-144 ← TASK-063）、M5（TASK-142 ← TASK-102、TASK-145 ← TASK-104）、M2（TASK-143 ← TASK-045）；M10 依赖 M6（TASK-203/207 ← TASK-125）与 M8（TASK-206 ← TASK-161）。

**发现的不一致（未改 dag，交规划 Agent 处理）**：TASK-210（v1 验收回归）在 `dag.md` 中的入边只有 TASK-202/206/208/209，没有 M4（TASK-087）、M7（TASK-146）、M9（TASK-184）的收尾任务。按本表“M10 = v1 验收”的含义，M10 的退出条件要求 M0…M9 全部已退出；建议在 dag 中为 TASK-210 补上这三条边。

## 变更记录
| 日期 | 变更 |
|---|---|
| 2026-10-17 | 初版 |
