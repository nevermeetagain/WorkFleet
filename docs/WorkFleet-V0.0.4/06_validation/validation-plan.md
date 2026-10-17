---
id: WF-VALIDATION-PLAN
type: validation
title: 验证计划
status: active
version: V0.0.4
created: 2026-10-17
sources: [docs/项目完整文档体系.txt §24–26/§40, ADR-011, DEC-029, REQ-NF-001…011, 04_planning/current-plan.md §11–12, 05_execution/task-index.md]
---

# 验证计划

## 1. 原则
1. **Task 完成 ≠ 已验证**：Task 回答“做了什么”，Validation 回答“是否真的满足”，Evidence 回答“用什么证明”（文档体系 §24）。
2. **独立验证者只输出三值**：`PASS` / `FAIL` / `UNKNOWN`，每个验收条目一个结论 + 证据指针 + 一句理由。不输出“基本通过”“大致可以”。
   - `PASS`：按验证命令复现，结果与验收条目逐字一致。
   - `FAIL`：复现结果不一致，或任一 Done 条件不满足（`current-plan.md §11`）。
   - `UNKNOWN`：无法判定（环境缺失、依赖不可用、证据不足、需真机而无设备）；必须写缺什么、谁能补。
   - 文档体系 §25 的 PARTIAL 记 FAIL（附已过条目），BLOCKED 记 UNKNOWN（`document-standard.md §5.3`）。
3. **防自证循环**：验证者不参与被验任务实现，不修被验代码；规则全文见 `current-plan.md §12`。
4. **CI 不依赖真实 IM 与智能体**（DEC-029、REQ-NF-009）；真实平台只在“真机冒烟”层验证，结果单独留证。

## 2. 验证层级
| 层 | 验证什么 | 工具 / 替身 | 运行位置 | 触发 | 主要任务 |
|---|---|---|---|---|---|
| L1 契约测试 | `packages/contracts` 的 schema 自洽、示例通过校验、生成物无漂移；API 实现的请求/响应符合 OpenAPI；帧符合 `protocol/` | ajv、json-schema-to-typescript、由 schema 生成的契约测试 | CI（ubuntu） | 每个 PR | TASK-002、TASK-014；各 API 任务 |
| L2 单元测试 | 领域规则（路由选路、模式约束、屏障、过滤脱敏、把关分级、写租约、费用估算等） | 测试框架（TASK-001 选定）；Clock/Id 可注入 | CI 三平台矩阵 | 每个 PR | 各实现任务 |
| L3 集成测试 | 模块经公开 API 协作；中转 + SQLite；节点 + FakeAgent；中转 + FakeChannel；两中转隔离；渠道一致性套件 | testkit（FakeAgent / FakeChannel / FakeRelay，TASK-008） | CI（ubuntu，必要时三平台） | 每个 PR | TASK-067、TASK-126、TASK-146 |
| L4 E2E | 用户主路径：浏览器 → 真中转 → 真节点 → FakeAgent / FakeChannel 方言 | Playwright | CI（ubuntu） | 每个 PR（切片 E2E）；合并主干后全量回归 | TASK-013/030/048/067/105/166/184、TASK-210 |
| L5 三平台 | 节点安装、自启、单实例、钥匙串、进程树清理、GBK 输出、CRLF、长路径（>260） | GitHub Actions windows/macos/ubuntu runner；安装脚本 | CI 矩阵 + 发布前手工 | 每个 PR（单测）/ 里程碑（安装） | TASK-014、TASK-161、TASK-209 |
| L6 真机冒烟 | 真实 IM（扫码、收发、审批、限额）、真实 ACP 智能体、iOS/Android PWA 推送、跨境链路 | 真账号、真设备；人工操作 + 录屏 | 用户本人 / 验证者设备 | 对应任务完成时；M2、M4、M5、M6、M10 退出前 | TASK-022/041/081–087/101/121–124/203/204、TASK-210 |

## 3. 非功能需求的验证归属
| 需求 | 层 | 方法 | 任务 |
|---|---|---|---|
| REQ-NF-001 响应时延 | L4 + L6 | trace_id 时间戳分位数（`04_planning/baseline-metrics.md` BM-01/02） | TASK-210 |
| REQ-NF-002 并发与资源 | L3 + L4 | 8 并发会话负载、空闲 15 分钟回收、控制面内存采样 | TASK-210 |
| REQ-NF-003 可靠性 | L3 + L4 | 断线 / 重启注入；比对丢失与重复外发 = 0 | TASK-013、TASK-067、TASK-210 |
| REQ-NF-004 安全 | L1 + L3 | 端口绑定检查、越权矩阵逐格、gitleaks、提示注入来源标记、Key 不出节点（grep 中转库与日志） | TASK-014、TASK-146、TASK-166 |
| REQ-NF-005 隐私 | L4 | 控制台明示文案存在；分身数据只在 node.db；导出/删除 | TASK-145 |
| REQ-NF-006 可移植 | L5 | 三平台矩阵 + Windows 专项用例 | TASK-014、TASK-209 |
| REQ-NF-007 可观测 | L3 | 日志 trace_id 贯穿 web→relay→node→agent；/metrics 文本；死信可查可重放 | TASK-045、TASK-143 |
| REQ-NF-008 可扩展 | L3 | 新增适配器只改适配器目录 + 注册一行（diff 审查）；渠道一致性套件 | TASK-126、TASK-087 |
| REQ-NF-009 可测试 | L1 | CI 中无真实 IM/智能体网络调用（出站网络断言） | TASK-014 |
| REQ-NF-010 成本 | L4 | 预算耗尽注入 → 降级为规则把关并通知 | TASK-166 |
| REQ-NF-011 可用性与语言 | L6 | 4G 节流下首屏可交互 ≤3 s；文案集中于 i18n | TASK-210 |

## 4. 自动化守卫清单（PR 硬门禁）
以下全部通过才允许合并（ADR-011；由 TASK-001/014 落地，`make guard` 为统一入口）。“状态”列反映**当前仓库现状**：尚无任何守卫实现（`08_knowledge/fact-baseline.md`）。

| # | 守卫 | 拦截什么 | 实现 | 来源 | 状态 |
|---|---|---|---|---|---|
| GD-01 | 依赖方向 | `interfaces → application → domain ← infrastructure`、前端 `pages → features → components/ui → lib` 逆向依赖；跨模块深层 import；循环依赖 | dependency-cruiser + ESLint `no-restricted-imports` | architecture §5、ADR-011 | 待 TASK-014 |
| GD-02 | 根目录污染 | 根目录出现白名单外文件；`*.bak` / `*_final*` / `*_old*` / `*_copy*` | 脚本 | `docs/项目完整目录结构.txt` 第六节 | 待 TASK-001/014 |
| GD-03 | 命名规范 | 文件/目录命名、ID 前缀（ADR-012） | 脚本 / lint | ADR-012 | 待 TASK-014 |
| GD-04 | 密钥扫描 | 提交中的密钥、Token、私钥 | gitleaks | REQ-NF-004 | 待 TASK-014 |
| GD-05 | 契约测试 | schema 示例失败；实现与 OpenAPI / 帧 schema 不符 | 由 schema 生成 | ADR-002、REQ-NF-009 | 待 TASK-002/014 |
| GD-06 | 生成物漂移 | 修改 schema 未重新生成，或手改生成物 | `pnpm contracts:gen && git diff --exit-code` | ADR-002 | 待 TASK-002 |
| GD-07 | 冻结路径保护 | 非授权任务修改 `packages/contracts/**`、已存在的 `database/migrations/**` 文件、`Makefile`/`.github/**`/`.dependency-cruiser.cjs` | 路径 diff 脚本 | `ownership-matrix.md §4`、`current-plan.md §11` | 待 TASK-014 |
| GD-08 | 所有权比对 | PR diff 超出任务卡“允许修改” | 路径前缀比对脚本（PR 描述须写任务号） | `ownership-matrix.md §1` | 待 TASK-014 |
| GD-09 | 类型检查与 lint | TS strict 错误、lint 错误 | `tsc --noEmit`、ESLint | ADR-004 | 待 TASK-001 |
| GD-10 | 三平台单测矩阵 | 只在某平台失败的单测 | GitHub Actions ubuntu/windows/macos | ADR-011、REQ-NF-006 | 待 TASK-014 |
| GD-11 | 切片 E2E | 主路径回归 | Playwright（ubuntu） | ADR-011 | 待 TASK-013 起 |
| GD-12 | 无外网依赖 | CI 测试中出现真实 IM / 智能体 / 模型的网络调用 | 测试网络拦截 | DEC-029 | 待 TASK-008/014 |

## 5. 验收流程
```text
任务执行者提交 PR（写明 TASK 号）
  ↓ CI 守卫 GD-01…GD-12 全绿（否则不进入验收）
任务状态 → in_review
  ↓ 独立验证者按任务卡第 6/7 节逐条复现
写 06_validation/acceptance/VAL-<任务号>.md（模板见 acceptance/README.md）
  ↓ 每条 PASS/FAIL/UNKNOWN + EVD 指针
全部 PASS 且 Done 七项满足 → 任务 done；否则退回或 blocked
  ↓ 切片 E2E 任务 PASS + 演示脚本复现 → 里程碑退出（milestones.md）
```

## 6. 真机冒烟清单（L6，需用户本人或有设备的验证者）
| 项 | 关键检查点 | 任务 | 关联假设/风险 |
|---|---|---|---|
| 微信 ClawBot | 扫码一次；`@别名` 分发；引用回复溯源；`Y{n}`；第 N 条主动消息失败点；24h 静默后主动发送；香港中转 RTT 与失败率；重复扫码是否顶掉旧授权 | TASK-041 | A-01/A-03/A-08/A-11；R-01/R-04/R-11 |
| ACP 智能体 13 个 + Coze + Webhook | 启动参数、握手、多轮、权限请求、`loadSession` | TASK-022、TASK-081…087 | A-04/A-05；R-02/R-05/R-10 |
| 飞书/Lark | 双域、长连接、卡片按钮回调路径、卡片更新、5 QPS | TASK-101 | A-12；R-16 |
| QQ / 钉钉 / Telegram / Discord | 收发、审批、主动消息配额 | TASK-121…124 | R-06 |
| PWA 推送 | Android Chrome、iOS 16.4+ 主屏 PWA | TASK-203/204 | A-06；R-12 |
| v1 验收 | 全部核心指标首次测量 | TASK-210 | `baseline-metrics.md` |

## 7. 变更记录
| 日期 | 变更 |
|---|---|
| 2026-10-17 | 初版 |
