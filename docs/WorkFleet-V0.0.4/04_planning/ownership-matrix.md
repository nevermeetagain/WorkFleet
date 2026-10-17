---
id: WF-OWNERSHIP
type: plan
title: 所有权矩阵
status: active
version: V0.0.4
created: 2026-10-17
---

# 所有权矩阵（Agent × 路径）

## 1. 规则
- 同时最多 3 个写入 Agent（波次表已遵守）。
- Agent-Contract 与 Agent-Guard 不与实现并行改（TASK-002/014 在 S0 前段完成后冻结；之后改契约 = 新任务 + ADR + fable/opus 券）。
- 跨所有权修改 = blocked：提交 ADR，不“先写了再说”。
- **偏离规划指令 §8.1 的一处**：§8.1 把 `infrastructure/persistence` 划给 Agent-Data。本项目 v1 的全部表已在迁移 0001 冻结，后续任务只写各自模块的仓储实现，故仓储随模块归属实现任务；**迁移文件仍只归 Agent-Data**。理由：避免每个模块任务都拆出一个 Data 子任务造成串行等待。代价：仓储风格可能不一致 → 由 TASK-003 提供仓储基类与 lint 规则约束。用户可推翻。

## 1.1 补充规则（评审闭环，ADR-015 同期）
1. **依赖声明**：实现任务可在**本应用**的 `apps/<app>/package.json` 的 `dependencies/devDependencies` 增加条目，并提交 `pnpm-lock.yaml`（归类为 Generated，冲突以 `pnpm install` 重新生成解决）；脚本段与根 `package.json` 仍归 Agent-Guard。新增第三方库必须同时在 `THIRD_PARTY_NOTICES` 追加一行（该文件为“仅追加”共享文件，冲突按行合并）。
2. **测试目录**：每个任务可写 `apps/<app>/tests/**/<本模块名>/**` 与模块内 `__tests__/`、`__fixtures__/`。
3. **扩展点与自动注册**：采用 TASK-001/004/007/009 定义的自动注册约定（模块 `register()`、`registerCommand`、`registerBlockRenderer`、适配器目录自动发现、页面路由按 `pages/<name>/index.ts` 自动发现、i18n 按 `features/<name>/i18n/*.json` 自动合并），后续任务不改 bootstrap、路由表与全局 i18n 文件。
4. **证据目录**：每个任务都可写 `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-<自身编号>/`。
5. **接线缺口**：卡内只列 `application/**` 的任务（141/182/201/202/203/205/206），其 `interfaces/**` 与帧分发入口同属该任务（同模块目录），视为允许修改。
6. **同 Agent 串行**：TASK-123→121、124→122 是排班依赖（同一 Agent-Channel 产能），非技术依赖。

## 2. 矩阵
| Agent | 允许修改（并集；每张任务卡只取其中一部分） |
|---|---|
| Agent-App | apps/web/index.html<br>apps/web/public/manifest.webmanifest<br>apps/web/src/app/**<br>apps/web/src/components/**<br>apps/web/src/data-access/**<br>apps/web/src/features/agents/**<br>apps/web/src/features/approvals/**<br>apps/web/src/features/audit/**<br>apps/web/src/features/auth/**<br>apps/web/src/features/barriers/**<br>apps/web/src/features/channels/**<br>apps/web/src/features/chat/**<br>apps/web/src/features/chat/commands/**<br>apps/web/src/features/devices/**<br>apps/web/src/features/devices/primary/**<br>apps/web/src/features/filters/**<br>apps/web/src/features/history/**<br>apps/web/src/features/local-*/**<br>apps/web/src/features/meetings/**<br>apps/web/src/features/members/**<br>apps/web/src/features/onboarding/**<br>apps/web/src/features/projects/**<br>apps/web/src/features/recipients/**<br>apps/web/src/features/routes/**<br>apps/web/src/features/routes/modes/**<br>apps/web/src/features/tasks/**<br>apps/web/src/i18n/**<br>apps/web/src/lib/**<br>apps/web/src/pages/agents/**<br>apps/web/src/pages/approvals/**<br>apps/web/src/pages/audit/**<br>apps/web/src/pages/auth/**<br>apps/web/src/pages/channels/**<br>apps/web/src/pages/chat/**<br>apps/web/src/pages/devices/**<br>apps/web/src/pages/history/**<br>apps/web/src/pages/members/**<br>apps/web/src/pages/projects/**<br>apps/web/src/pages/routes/**<br>apps/web/src/pwa/**<br>apps/web/src/styles/**<br>apps/web/src/targets/node/**<br>apps/web/src/targets/node/models/**<br>apps/web/src/targets/node/supervisor/**<br>apps/web/src/targets/node/twin/**<br>apps/web/vite.config.ts |
| Agent-Channel | apps/relay/src/modules/channels/infrastructure/adapters/dingtalk/**<br>apps/relay/src/modules/channels/infrastructure/adapters/discord/**<br>apps/relay/src/modules/channels/infrastructure/adapters/feishu/**<br>apps/relay/src/modules/channels/infrastructure/adapters/qq/**<br>apps/relay/src/modules/channels/infrastructure/adapters/telegram/**<br>apps/relay/src/modules/channels/infrastructure/adapters/wechat-clawbot/**<br>docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-041/** |
| Agent-Contract | packages/contracts/generated/**<br>packages/contracts/package.json<br>packages/contracts/scripts/**<br>packages/contracts/src/**<br>packages/contracts/test/** |
| Agent-Data | apps/node/src/core/db/**<br>apps/relay/src/core/db/**<br>scripts/database/** |
| Agent-Docs | docs/**（不含 06_validation/evidence） |
| Agent-Guard | .dependency-cruiser.cjs<br>.editorconfig<br>.env.example<br>.github/**<br>.gitignore<br>.gitleaks.toml<br>AGENTS.md<br>CHANGELOG.md<br>Makefile<br>Makefile（仅 guard/ci 目标段）<br>README.md<br>apps/*/AGENTS.md<br>apps/*/package.json<br>apps/*/tsconfig.json<br>eslint.config.js<br>infra/**<br>package.json<br>pnpm-workspace.yaml<br>scripts/release/**<br>scripts/setup/**<br>tsconfig.base.json |
| Agent-Node | apps/node/src/bootstrap/**<br>apps/node/src/core/** (除 core/db)<br>apps/node/src/core/secrets/**（扩展 007 的抽象）<br>apps/node/src/core/secrets/**（钥匙串最小抽象：get/set/delete，DPAPI/Keychain/libsecret/加密文件回退；161 扩展）<br>apps/node/src/modules/agents/** (除 adapters/specs、application/echo)<br>apps/node/src/modules/agents/application/echo/**<br>apps/node/src/modules/agents/application/namespace/**<br>apps/node/src/modules/agents/index.ts<br>apps/node/src/modules/agents/infrastructure/coze/**<br>apps/node/src/modules/agents/infrastructure/dialects/zcode/**<br>apps/node/src/modules/agents/infrastructure/specs/**<br>apps/node/src/modules/agents/infrastructure/specs/group-a/**<br>apps/node/src/modules/agents/infrastructure/specs/group-b/**<br>apps/node/src/modules/agents/infrastructure/specs/openclaw/**<br>apps/node/src/modules/agents/infrastructure/webhook/**<br>apps/node/src/modules/meetings/**<br>apps/node/src/modules/models/**<br>apps/node/src/modules/models/infrastructure/providers/**<br>apps/node/src/modules/relay-link/**<br>apps/node/src/modules/sessions/**<br>apps/node/src/modules/supervisor/**<br>apps/node/src/modules/supervisor/application/chat/**<br>apps/node/src/modules/supervisor/application/dispatch/**<br>apps/node/src/modules/supervisor/application/import/**<br>apps/node/src/modules/system/**<br>apps/node/src/modules/system/application/doctor/**<br>apps/node/src/modules/system/application/emergency/**<br>apps/node/src/modules/system/application/recovery/**<br>apps/node/src/modules/twin/**<br>apps/node/src/modules/workspace-guard/**<br>apps/node/tests/**/agents/**<br>apps/node/tests/**/relay-link/**<br>apps/node/tests/**/sessions/**<br>apps/relay/src/modules/audit/application/twin-forward/**<br>docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-022/**<br>packages/testkit/fixtures/acp/openclaw/**<br>packages/testkit/fixtures/acp/zcode/**<br>packages/testkit/fixtures/acp/{claude-code,codex,cursor}/**<br>packages/testkit/fixtures/acp/{gemini-cli,qwen-code,kimi-cli,opencode}/**<br>packages/testkit/fixtures/acp/{goose,cline,qoder-cli,github-copilot}/** |
| Agent-QA | docs/WorkFleet-V0.0.4/06_validation/**<br>docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-087/**<br>packages/testkit/**<br>playwright.config.ts<br>tests/e2e/**<br>tests/e2e/regression/**<br>tests/e2e/s1/**<br>tests/e2e/s2/**<br>tests/e2e/s3/**<br>tests/e2e/s5/**<br>tests/e2e/s8/**<br>tests/e2e/s9/**<br>tests/integration/channels/**<br>tests/integration/s3/**<br>tests/integration/security/**<br>tests/integration/security/gitleaks-rules.toml（规则补充，由 TASK-014 的 .gitleaks.toml 引用） |
| Agent-Relay | apps/relay/src/bootstrap/**<br>apps/relay/src/core/** (除 core/db)<br>apps/relay/src/core/middleware/**<br>apps/relay/src/modules/agents-registry/**<br>apps/relay/src/modules/approvals/**<br>apps/relay/src/modules/approvals/application/text-codes/**<br>apps/relay/src/modules/audit/**<br>apps/relay/src/modules/channels/** (除 infrastructure/adapters/*)<br>apps/relay/src/modules/channels/application/identity-guard/**<br>apps/relay/src/modules/channels/infrastructure/adapters/web/**<br>apps/relay/src/modules/commands/**<br>apps/relay/src/modules/commands/application/approval-codes/**<br>apps/relay/src/modules/conversations/**<br>apps/relay/src/modules/conversations/application/history/**<br>apps/relay/src/modules/conversations/interfaces/http/history*<br>apps/relay/src/modules/delivery/**<br>apps/relay/src/modules/devices/**<br>apps/relay/src/modules/devices/application/primary/**<br>apps/relay/src/modules/identity/**<br>apps/relay/src/modules/node-gateway/**<br>apps/relay/src/modules/notifications/**<br>apps/relay/src/modules/notifications/infrastructure/webpush/**<br>apps/relay/src/modules/orchestration/**<br>apps/relay/src/modules/permissions-filter/**<br>apps/relay/src/modules/projects/**<br>apps/relay/src/modules/recipients/**<br>apps/relay/src/modules/routing/**<br>apps/relay/src/modules/routing/application/device-select/**<br>apps/relay/src/modules/routing/application/modes/**<br>apps/relay/src/modules/system/**<br>apps/relay/src/modules/system/application/config-io/**<br>apps/relay/src/modules/system/application/emergency/**<br>apps/relay/src/modules/tenancy/**<br>apps/relay/src/modules/tenancy/application/invitations/**<br>apps/relay/src/modules/tenancy/application/scope/**<br>apps/relay/tests/**/commands/**<br>apps/relay/tests/**/conversations/**<br>apps/relay/tests/**/devices/**<br>apps/relay/tests/**/identity/**<br>apps/relay/tests/**/node-gateway/**<br>apps/relay/tests/**/tenancy/** |
| Agent-Data（迁移） | database/migrations/**（0001+0002 冻结，仅新增文件） |

## 3. 重叠检查
同层任务的路径两两比较：无重叠。不同层的同路径修改由依赖边保证先后，不构成并行冲突。

## 4. 全局禁止修改（所有实现任务）
- `packages/contracts/**`（除 TASK-002）
- `database/migrations/**`（除 Agent-Data 新增任务）
- `Makefile`、`.github/**`、`.dependency-cruiser.cjs`（除 TASK-001/014/209）
- `docs/**`（除各任务的 `06_validation/evidence/EVD-xxx/` 与 TASK-211）
