---
id: DESIGN-008
type: design
title: 复用详细设计（直接依赖、可移植代码、只借设计、THIRD_PARTY_NOTICES、DEC-009）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "DEC-009"
  - "DEC-033"
  - "DEC-015"
  - "ADR-004"
  - "ADR-007"
  - "ADR-008"
  - "ADR-009"
  - "ADR-010"
  - "ADR-013"
  - "ADR-014"
  - "REQ-C-002"
  - "MUST NOT #6"
  - "V0.0.3/analysis-18-dimensions §8"
  - "V0.0.2/10-参考项目/11（WCB 许可）"
  - "12（Paperclip MIT）"
  - "13（PentAGI MIT+EULA）"
  - "14（Orca MIT）"
  - "16（BettaFish GPL-2.0）"
  - "packages/contracts/adapters/input-adapters.v1.json"
---

# DESIGN-008 复用

## 1. 总则（DEC-009、DEC-033、REQ-C-002）
| 级别 | 定义 | 允许的动作 | 本项目对象 |
|---|---|---|---|
| A 直接依赖 | 作为 npm 包/外部程序使用，不拷贝源码 | `package.json` 声明、锁版本；许可写入 THIRD_PARTY_NOTICES | 运行栈、渠道 SDK、ACP SDK/桥、外部智能体 CLI |
| B 可移植代码 | 许可宽松（MIT/Apache-2.0/BSD），可拷贝并修改 | 保留原版权与许可文本；文件头标注来源；THIRD_PARTY_NOTICES 收录 | Orca（MIT）、Paperclip（MIT） |
| C 只借设计 | 许可不兼容或不明，**零代码/零提示词原文拷贝**（clean-room） | 只依据本仓文档中的行为规格实现 | PentAGI（MIT+EULA 张力）、BettaFish（GPL-2.0）、WechatClawbot（无 LICENSE）、AstrBot（AGPL） |
| 禁止 | AGPL/GPL/EULA 代码进入仓库 | — | MUST NOT #6 |
仓库许可：Apache-2.0（DEC-033）。

## 2. 直接依赖清单
> “许可”列：**已确认** = 本仓文档已核对；**待核实** = 规划者的一般认知，必须在对应任务中用 `pnpm licenses list` 与包内 LICENSE 文件核实后写入 THIRD_PARTY_NOTICES。任何一项核实结果与本表不符且不在允许清单（§5）内，立即替换，不阻塞其他模块（ADR-010）。

### 2.1 运行栈与工具
| 包 | 用途 | 侧 | 许可 | 核实任务 |
|---|---|---|---|---|
| react / react-dom 19、react-router | 前端 | web | MIT（待核实） | TASK-009 |
| vite | 构建 | web | MIT（待核实） | TASK-009 |
| @tanstack/react-query | 服务端状态 | web | MIT（待核实） | TASK-009 |
| zustand | 客户端状态 | web | MIT（待核实） | TASK-009 |
| @radix-ui/*、shadcn/ui（拷入源码属 B 级，见 §3.3） | UI 原语 | web | MIT（待核实） | TASK-009 |
| tailwindcss 4 | 样式 | web | MIT（待核实） | TASK-009 |
| @rjsf/core、@rjsf/validator-ajv8 | Schema 表单 | web | **Apache-2.0（已确认，ADR-008）** | TASK-027 |
| i18next、react-i18next | i18n | web | MIT（待核实） | TASK-009 |
| fastify 5 | HTTP | relay/node | MIT（待核实） | TASK-004 |
| ws | WebSocket | relay/node | MIT（待核实） | TASK-006/007 |
| better-sqlite3 | SQLite（三平台预编译） | relay/node | MIT（待核实） | TASK-003 |
| kysely | 查询构建 | relay/node | MIT（待核实） | TASK-003 |
| pino | 日志 | relay/node | MIT（待核实） | TASK-004 |
| ajv、ajv-formats | 校验 | 全部 | MIT（待核实） | TASK-002 |
| json-schema-to-typescript | 契约类型生成 | contracts | MIT（待核实） | TASK-002 |
| argon2（node-argon2） | 密码哈希 | relay | MIT（待核实） | TASK-005 |
| ulid（或自写 ULID） | ID | 全部 | MIT（待核实） | TASK-002 |
| yaml | 配置导入导出 | relay/node | ISC（待核实） | TASK-205 |
| web-push | VAPID 推送 | relay | MPL-2.0（待核实；文件级弱 copyleft，作为未修改依赖可与 Apache-2.0 共存，需在 notices 标注；如需修改则改为自写 VAPID） | TASK-203 |
| 钥匙串绑定（候选：自写 DPAPI/Keychain/libsecret 调用，或社区原生绑定库） | 模型 Key、令牌 | node | 证据不足 | TASK-161 |
| vitest、playwright、dependency-cruiser、eslint、gitleaks | 测试与守卫 | dev | 待核实（dev 依赖不随产物分发，仍登记） | TASK-008/014 |

### 2.2 渠道（ADR-010 的选择，许可逐个核实）
| 渠道 | 方案 | 许可 | 任务 |
|---|---|---|---|
| 飞书/Lark | 官方 Node SDK（长连接） | 待核实 | TASK-101 |
| 钉钉 | 官方 Stream SDK | 待核实 | TASK-122 |
| QQ | 官方开放平台 WebSocket，**自写客户端** | 自有 | TASK-121 |
| Telegram | Bot API getUpdates，自写或 MIT 库 | 自写/待核实 | TASK-123 |
| Discord | Gateway，Apache-2.0 库（ADR-010） | 待核实 | TASK-124 |
| 微信 ClawBot | iLink HTTP 长轮询，**clean-room 自写**（WCB 无 LICENSE） | 自有 | TASK-041 |

### 2.3 输入端（外部程序，不随 WorkFleet 分发）
| 对象 | 方式 | 说明 |
|---|---|---|
| ACP 官方 TypeScript SDK | npm 依赖（包名/版本证据不足，ADR-007/U-05） | TASK-021 确认后登记 |
| `@zed-industries/claude-agent-acp`、`@zed-industries/codex-acp` | spec 中 `npx -y` 启动（input-adapters.v1.json），**不打包** | 用户机器上按需下载；许可待核实（V0.0.2/12 记“各包自身许可证据不足”） |
| Cursor `agent acp`、gemini、copilot、qwen、kimi、opencode、goose、cline、qodercli、openclaw | 用户自行安装的 CLI；节点只 spawn | 不构成再分发；WorkFleet 不代登录其账号（PRB §8） |
| ZCode `zcode-acp-server`（社区桥） | 实验；ToS 风险（REQ-C-009、DEC-038） | 只调用，不分发 |
| Hindsight | v1 不启用（DEC-015） | — |

## 3. 可移植代码（B 级）
### 3.1 Orca（MIT，Copyright (c) 2026 Lovecast Inc.；V0.0.2/14 已确认）
| 编号 | 来源（Orca） | WorkFleet 落点 | 方式 | 约束 |
|---|---|---|---|---|
| M1 | ACP JSON-RPC peer（`acp-json-rpc-peer.ts`、`acp-peer-limits.ts`） | `apps/node/src/modules/agents/infrastructure/acp/peer.ts` | 移植并改写（仅依赖 node:stream，V0.0.2/14 §392 已确认） | 不移植 `acp-structured-*`（深度依赖其宿主） |
| M2 | session setup（`acp-session-setup.ts`） | `infrastructure/acp/client.ts` | 移植改写；协议类型改用官方 SDK/Schema 生成（裁决见 V0.0.2/14 §395） | — |
| M3 | launch-spec 表 + Dialect 接口（`acp-launch-specs.ts`、`acp-dialects/acp-dialect.ts`） | `InputAdapterSpec`（契约）+ `AcpDialect`（DESIGN-007 §3） | **重写为契约字段**，保留字段语义（account、authMethod、modelDiscovery、managedRuntime、privateTempDirectory） | 契约是唯一源；代码移植只限 dialect 机制 |
| M4 | 编排 schema 思路、held 策略、单实例锁与陈旧锁回收（`orcad-instance-lock*.ts`）、supervise 重启语义 | DESIGN-003 §2/§8；DESIGN-006 §6 | 以设计移植为主；若拷贝锁代码需保留版权 | — |
### 3.2 Paperclip（MIT，Copyright (c) 2025 Paperclip AI；V0.0.2/12 已确认）
| 编号 | 来源 | 落点 | 方式 |
|---|---|---|---|
| P1 | `ServerAdapterModule`、`AdapterExecutionContext{signal,onLog/onEvent/onUsage}` 接口形状 | `InputAdapter`/`TurnContext`（DESIGN-007 §3） | 精简移植（去掉 workspace/sandbox/budget 耦合字段） |
| P2 | 会话模型（session_display_id + session_generation + 幂等键） | conversations 表与 generation 语义（DESIGN-004） | 模型移植（无代码） |
| P3 | 通道能力矩阵字段（`provider-catalog.ts`） | `channel-capabilities.schema.json`（已在契约） | 字段沿用 |
| P4 | 持久化投递队列、审批唤醒、随时对话不打断 | delivery、approvals、supervisor chat | 思路移植 |
### 3.3 shadcn/ui
- shadcn 组件以“拷贝源码到 `components/ui`”方式使用，属于 B 级：保留其许可声明（待核实为 MIT），在 THIRD_PARTY_NOTICES 收录一次。

### 3.4 移植文件头格式（强制）
```ts
/*
 * Portions of this file are adapted from Orca (https://github.com/stablyai/orca),
 * Copyright (c) 2026 Lovecast Inc., licensed under the MIT License.
 * Source: src/main/acp/acp-json-rpc-peer.ts @ <commit>
 * Modifications Copyright (c) 2026 WorkFleet contributors, licensed under the Apache License 2.0.
 */
```
- `<commit>` 必填（可追溯）；V0.0.2/14 记录的 Orca 分析基线为 `fd1c6a59…`，实际移植时以所读提交为准。

## 4. 只借设计（C 级，clean-room）
| 项目 | 许可状况（本仓已确认） | 借鉴的设计 | 落点 | 执行规则 |
|---|---|---|---|---|
| WechatClawbot | 仓库无 LICENSE（默认保留所有权利）；子包声明 MIT 但指向别处（V0.0.2/11） | iLink 端点行为（get_bot_qrcode、get_qrcode_status、getupdates、sendmessage、getuploadurl…）、context_token 语义、扫码状态机、MCP 推送工具思路 | 微信适配器、DESIGN-003 §10.6 MCP | 实现者只读 V0.0.2/11 的行为描述与 iLink 公开信息，不打开 WCB 源码 |
| PentAGI | MIT 与 EULA 并存且存在张力（V0.0.2/13） | 总控护栏（行为闸、mentor 阈值）、外发前脱敏、Waiting 语义 | supervisor、permissions-filter | 同上；商业使用前法务确认（证据不足） |
| BettaFish | GPL-2.0（V0.0.2/16） | 主持人纪要四段式、纪要注入下一轮、IR 汇报、任务事件流补发 | meetings（DEC-019）、Renderer IR（DEC-024） | 只依据 V0.0.2/16 §385 起的行为规格；不复制提示词原文；评审做相似度检查 |
| AstrBot | AGPL（DEC-009） | 无 | — | 禁止查看源码用于实现 |
clean-room 流程：
1. 设计者（可读参考源码）只产出**行为规格**到 `docs/`（已有 V0.0.2/10–16）。
2. 实现任务卡注明“C 级 clean-room”，实现者不得打开对应仓库源码；PR 模板勾选声明。
3. 评审对照规格，不对照源码；可疑相似片段 → 重写。

## 5. THIRD_PARTY_NOTICES 规则
- 位置：仓库根 `THIRD_PARTY_NOTICES`（DEC-033；注意根目录白名单未列此文件，见 §7 R-1）。
- 内容结构：
```text
WorkFleet includes or depends on the following third-party software.

== Bundled / adapted source (B 级) ==
Orca — MIT — Copyright (c) 2026 Lovecast Inc.
  Files: apps/node/src/modules/agents/infrastructure/acp/peer.ts, …
  <完整 MIT 许可文本>
Paperclip — MIT — Copyright (c) 2025 Paperclip AI
  Files: …
shadcn/ui — <许可> — <版权>

== Runtime dependencies distributed in release artifacts (A 级) ==
<name>@<version> — <license> — <copyright line>   （由脚本从 pnpm licenses list 生成，按包名排序）
```
- 生成：`scripts/release/notices.ts`（TASK-209）从 `pnpm licenses list --prod --json` 生成 A 级段；B 级段手工维护。CI 检查生成结果与提交一致。
- 许可允许清单（CI `make guard` 子项，ADR-011）：MIT、ISC、BSD-2-Clause、BSD-3-Clause、Apache-2.0、0BSD、CC0-1.0；**需人工批准**：MPL-2.0、Python-2.0、BlueOak；**禁止**：GPL-*、AGPL-*、LGPL-*（静态打包时）、SSPL、BUSL、无许可/UNKNOWN。
- 节点安装包与中转发布包都附带 THIRD_PARTY_NOTICES 与 LICENSE。

## 6. 依赖准入流程
1. 任务卡写明新增依赖与理由；优先级：官方 SDK > MIT/Apache 社区库 > 自写（ADR-010）。
2. 检查：许可（§5 清单）、维护活跃度、是否有原生模块（三平台预编译，ADR-009）、体积（前端预算 DESIGN-001 §12）。
3. 锁版本（pnpm-lock）；重大版本升级单独任务。
4. 原生模块（better-sqlite3、钥匙串绑定、Windows Job helper）需在三平台 CI 矩阵通过（ADR-011）。

## 7. 与契约/规范的差异 / 待办
| # | 发现 | 处理 |
|---|---|---|
| R-1 | PROJECT-STRUCTURE-SPEC §5.1 根目录白名单不含 `THIRD_PARTY_NOTICES`，DEC-033 要求放根目录 | 以 DEC-033 为准，Agent-Guard 在根污染检查白名单中加入该文件（TASK-001/014） |
| R-2 | `@zed-industries/*` 桥包与官方 ACP SDK 的许可均未核实 | TASK-021/022 核实；若许可不兼容，改为用户自行安装后由 spec 指向本地命令 |
| R-3 | web-push 为 MPL-2.0（待核实） | 需人工批准；或自写 VAPID（RFC 8291/8292）替代 |
| R-4 | Windows Job Object helper 若自写需原生代码签名 | DESIGN-003 §6.2 方案 A；签名证书与分发策略证据不足（TASK-209） |
