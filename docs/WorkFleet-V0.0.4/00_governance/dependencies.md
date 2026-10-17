---
id: WF-DEPENDENCIES
type: dependency
title: 外部依赖登记册
status: active
version: V0.0.4
created: 2026-10-17
owner: 规划 Agent
sources: [ADR-004/005/007/008/009/010/013/014, REQ-C-001/002, packages/contracts/adapters/input-adapters.v1.json, docs/WorkFleet-V0.0.3/08_knowledge/fact-baseline.md, docs/WorkFleet-V0.0.2/30-协议与端点/03-输出端接入矩阵.md]
---

# 外部依赖登记册

> 规则
> - **版本**：当前仓库无 `package.json`、无锁文件（见 `08_knowledge/fact-baseline.md`），因此下表除注明的快照外，**版本一律“待锁定”**，由 TASK-001（脚手架）/ TASK-002（契约）/ TASK-021（ACP SDK）首次写入锁文件后回填。
> - **许可**：“常见许可”列是规划者对上游项目的已知认识，**未在本仓库逐一核对**，标 `待核实`；合并任何依赖前必须核对其 LICENSE 文件并登记到 THIRD_PARTY_NOTICES（REQ-C-002、ADR-010）。只有在本仓库或 V0.0.2/V0.0.3 文档中有出处的才标 `已确认`。
> - 与“风险”“假设”的区别见文档体系 §42。

## 1. 运行时与基础设施
| ID | 依赖 | 用于 | 版本 | 许可 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| DEP-01 | Node.js 22 LTS | 中转与节点运行时 | 22.x（具体小版本待锁定） | MIT 系（待核实） | REQ-C-001、ADR-004 | `node:sqlite` 在 Node 22 标实验，不采用（ADR-009，证据不足） |
| DEP-02 | TypeScript 5（strict） | 全仓语言 | 5.x 待锁定 | Apache-2.0（待核实） | ADR-004、DEC-032 | — |
| DEP-03 | pnpm workspaces | Monorepo 管理 | 待锁定 | MIT（待核实） | ADR-004 | Makefile 为统一入口 |
| DEP-04 | SQLite（WAL） | relay.db / node.db | 随 better-sqlite3 内置版本 | 公有领域（待核实） | ADR-003、DEC-004 | FTS 中文用 trigram（DEC-015） |
| DEP-05 | Ubuntu 22.04+/24.04 | 中转主机 | — | — | DEC-041、architecture §3 | 暂定部署香港（DEC-040） |
| DEP-06 | Caddy 或 Nginx | 中转 443 TLS 反代 | 待定 | Apache-2.0 / BSD-2（待核实） | architecture §3、TASK-209 | 需域名与证书（PRD §8） |
| DEP-07 | systemd / launchd / Windows 自启机制 | 中转与节点常驻 | 系统自带 | — | DEC-041 | — |
| DEP-08 | OS 钥匙串：Windows DPAPI、macOS Keychain、Linux libsecret | 模型 Key、主密钥 | 系统自带 | — | DEC-041、TASK-161 | 无钥匙串时加密文件回退（R-09） |

## 2. 后端库（ADR-009 等）
| ID | 依赖 | 用于 | 版本 | 常见许可 | 依据 |
|---|---|---|---|---|---|
| DEP-10 | Fastify 5 | 中转/节点 HTTP | 5.x 待锁定 | MIT（待核实） | ADR-009 |
| DEP-11 | ws | 节点 WSS 通道、Web 流 | 待锁定 | MIT（待核实） | ADR-009、ADR-005 |
| DEP-12 | better-sqlite3 | SQLite 驱动 | 待锁定 | MIT（待核实） | ADR-009（三平台预编译为假设 A-13） |
| DEP-13 | Kysely | 查询构建与方言抽象 | 待锁定 | MIT（待核实） | ADR-009、ADR-003 |
| DEP-14 | pino | 结构化日志（trace_id） | 待锁定 | MIT（待核实） | ADR-009、REQ-NF-007 |
| DEP-15 | ajv | JSON Schema 运行时校验 | 待锁定 | MIT（待核实） | ADR-002/009 |
| DEP-16 | json-schema-to-typescript | 契约 → TS 类型生成 | 待锁定 | MIT（待核实） | ADR-002 |
| DEP-17 | argon2（argon2id 实现） | 密码哈希 | 待锁定 | 待核实 | architecture §4.1 identity |
| DEP-18 | web-push（VAPID）或等价实现 | PWA 推送 | 待选型 | 待核实 | ADR-014、TASK-203 |

## 3. 前端库（ADR-008）
| ID | 依赖 | 用于 | 版本 | 常见许可 | 依据 |
|---|---|---|---|---|---|
| DEP-20 | React 19 | UI | 19.x 待锁定 | MIT（待核实） | ADR-008、REQ-C-001 |
| DEP-21 | Vite | 构建（relay / node 两个目标） | 待锁定 | MIT（待核实） | ADR-008 |
| DEP-22 | TanStack Query | 服务端状态 | 待锁定 | MIT（待核实） | ADR-008 |
| DEP-23 | Zustand | 客户端状态 | 待锁定 | MIT（待核实） | ADR-008 |
| DEP-24 | Radix UI / shadcn/ui | 组件 | 待锁定 | MIT（待核实） | ADR-008 |
| DEP-25 | Tailwind CSS 4 | 样式 | 4.x 待锁定 | MIT（待核实） | ADR-008 |
| DEP-26 | @rjsf（react-jsonschema-form） | 适配器 configSchema 表单 | 待锁定 | Apache-2.0（ADR-008 所述，仍待核实） | ADR-008、DEC-010 |

## 4. 测试与守卫（ADR-011）
| ID | 依赖 | 用于 | 版本 | 常见许可 | 依据 |
|---|---|---|---|---|---|
| DEP-30 | Playwright | E2E | 待锁定 | Apache-2.0（待核实） | TASK-013 |
| DEP-31 | dependency-cruiser | 依赖方向守卫 | 待锁定 | MIT（待核实） | ADR-011 |
| DEP-32 | ESLint（`no-restricted-imports`） | 模块边界 | 待锁定 | MIT（待核实） | ADR-011 |
| DEP-33 | gitleaks | 密钥扫描 | 待锁定 | MIT（待核实） | ADR-011、REQ-NF-004 |
| DEP-34 | GitHub Actions（ubuntu/windows/macos runner） | 三平台 CI 矩阵 | — | 服务条款 | ADR-011、REQ-NF-006 |

## 5. 协议与智能体（输入端，ADR-007、DEC-055）
| ID | 依赖 | 接入方式（规划值，待实测） | 版本 / 状态 | 许可 | 依据 |
|---|---|---|---|---|---|
| DEP-40 | ACP（Agent Client Protocol）官方 TypeScript SDK | 节点 ACP Host | V0.0.3 快照：TS SDK 1.9.0、Python SDK 0.12.1（已确认于快照日）；包名与当前版本待 TASK-021 实测（U-05） | 待核实 | V0.0.3 F-07；ADR-007 |
| DEP-41 | ACP 官方 Registry（agentclientprotocol.com/overview/agents） | 通用适配器的智能体清单来源 | 2026-10-17 读取（DEC-055） | — | DEC-055、ADR-007 |
| DEP-42 | Claude Code（`@zed-industries/claude-agent-acp`） | `npx -y @zed-industries/claude-agent-acp` | 待实测 | 待核实 | input-adapters.v1.json |
| DEP-43 | Codex（`@zed-industries/codex-acp`） | `npx -y @zed-industries/codex-acp` | 待实测 | 待核实 | 同上 |
| DEP-44 | Cursor | `agent acp` | 已确认支持 ACP（V0.0.3 F-08） | 商业软件条款 | 同上 |
| DEP-45 | Gemini CLI | `gemini --experimental-acp` | 待实测 | 待核实 | 同上 |
| DEP-46 | GitHub Copilot CLI | `copilot --acp` | 官方 public preview（R-05） | 商业服务条款 | 同上 |
| DEP-47 | Qwen Code / Kimi CLI / OpenCode / Goose / Cline / Qoder CLI | 见 input-adapters.v1.json 各条 launch | 均待实测 | 均待核实 | 同上；TASK-081/082 |
| DEP-48 | OpenClaw | `openclaw acp`（可 `--url wss://…` 连远端 Gateway） | 已确认存在（V0.0.3 F-16） | 待核实 | TASK-083 |
| DEP-49 | ZCode | `zcode-acp-server`（社区，自述非官方，Apache-2.0）或 `zcode app-server --stdio`（私有、未文档化） | 实验（R-02） | 社区桥 Apache-2.0（V0.0.3 F-19 记载，待复核）；ZCode 本体条款未核 | DEC-038、TASK-084 |
| DEP-50 | Coze HTTP API | 非 ACP 输入（REQ-F-008） | 待实测 | 平台条款 | TASK-085 |

## 6. IM 平台（输出端，ADR-010、DEC-054）
| ID | 平台 | 接入方式（ADR-010） | 关键限额 / 约束（出处） | SDK 许可 | 依据 |
|---|---|---|---|---|---|
| DEP-60 | 微信 ClawBot（iLink） | HTTP 长轮询 `getupdates` + `sendmessage`，clean-room 自写 | context_token 24h、约 10 条主动消息/次入站（部分确认）；Bot 与扫码者 1:1；不可群发（`V0.0.2/30/03:14,22,52-53`） | 自写，无第三方 SDK | REQ-F-009、REQ-C-008 |
| DEP-61 | 飞书 / Lark | 官方 Node SDK 长连接；feishu.cn 与 larksuite.com 双域 | 长连接仅企业自建应用；卡片回调 3 秒；同用户/同群 5 QPS；卡片 ≤30KB（V0.0.3 F-09，上线前复核）；长连接集群模式随机投递（F-15） | 官方 SDK 许可待核实 | REQ-F-010 |
| DEP-62 | QQ 官方机器人 | 开放平台 WebSocket，自写客户端 | 主动配额文档冲突（R-06）；用户可关闭主动消息 | 自写 | REQ-F-011 |
| DEP-63 | 钉钉 | 官方 Stream SDK | 企业内（`V0.0.2/30/03:23`） | 官方 SDK 许可待核实 | REQ-F-012 |
| DEP-64 | Telegram | Bot API `getUpdates`，自写或 MIT 库 | 外部订阅者首选（DEC-046 推论） | 待核实 | REQ-F-013 |
| DEP-65 | Discord | Gateway，Apache-2.0 库（ADR-010） | DM 条件未核（`V0.0.2/30/03:198`） | Apache-2.0（ADR-010 所述，待核实具体库） | REQ-F-014 |
| DEP-66 | Web Push 服务（浏览器厂商推送网关） | VAPID | iOS 16.4+ 且需添加到主屏（A-06） | — | ADR-014 |

## 7. 模型提供方（仅总控，本机调用）
| ID | 依赖 | 用于 | 约束 | 依据 |
|---|---|---|---|---|
| DEP-70 | OpenAI 兼容接口 / Anthropic Messages 接口 | 总控把关、会议（自写薄客户端） | Key 只存节点钥匙串，不上中转（DEC-044）；费用 = usage × 用户填写单价（部分确认） | ADR-013、REQ-F-026 |

## 8. 内部依赖（仓库内）
| ID | 依赖 | 说明 |
|---|---|---|
| DEP-80 | `packages/contracts/`（唯一契约源） | 所有实现任务依赖 TASK-002 冻结后的生成物（`04_planning/dag.md §5` 契约链） |
| DEP-81 | `database/migrations/{relay,node}/0001_init.sql` | v1 迁移冻结，只新增文件 |
| DEP-82 | `packages/testkit`（FakeAgent/FakeChannel/FakeRelay） | CI 不依赖真实 IM 与智能体（DEC-029、REQ-NF-009） |

## 9. 明确不依赖
- 不引入 LangChain 等大型 LLM 框架（ADR-013）。
- 不拷贝 AGPL（AstrBot）、EULA（PentAGI）、GPL-2.0+禁商用（BettaFish）、无 LICENSE（WechatClawbot）项目代码（DEC-009、V0.0.3 F-06）。
- v1 不启用 Hindsight（DEC-015）；不依赖 PostgreSQL/Redis/Docker（V0.0.3 fact-baseline §4 已否决重栈；ADR-003）。

## 10. 变更记录
| 日期 | 变更 |
|---|---|
| 2026-10-17 | 初版；全部版本待锁定、许可待核实 |
