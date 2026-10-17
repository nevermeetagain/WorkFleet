---
id: WF-PROJECT-MAP
type: project-map
title: 项目地图（目标代码结构 + 文档追溯链）
status: active
version: V0.0.4
created: 2026-10-17
---

# Project Map

## 1. 目标仓库结构（按 PROJECT-STRUCTURE-SPEC；当前仅 docs/、packages/contracts、database/migrations 存在）
```text
WorkFleet/
├── apps/
│   ├── relay/                 云中转（Fastify + ws）       → DESIGN-002
│   │   └── src/{bootstrap,core,shared,modules/{identity,tenancy,devices,projects,agents-registry,channels,recipients,commands,routing,conversations,delivery,approvals,orchestration,permissions-filter,audit,notifications,node-gateway,system}}
│   ├── node/                  本机节点                       → DESIGN-003
│   │   └── src/{bootstrap,core/{db,secrets},shared,modules/{relay-link,agents,sessions,workspace-guard,models,supervisor,meetings,twin,local-console,system}}
│   └── web/                   SPA（relay / node 两个构建目标）→ DESIGN-001
│       └── src/{app,pages,features,components/{ui,layout},data-access,stores,lib,types,constants,styles,i18n,pwa,targets/node}
├── packages/
│   ├── contracts/             契约唯一源 ★（已存在）
│   └── testkit/               FakeAgent / FakeChannel / FakeRelay
├── database/migrations/{relay,node}/   0001 + 0002（已存在，冻结）
├── tests/{integration,e2e}/
├── infra/{docker,deployment,ci}/   scripts/{setup,database,release,maintenance}/
├── docs/WorkFleet-V0.0.x/     版本文档（DEC-042）
├── .local/                    临时（gitignore）
└── README.md AGENTS.md CHANGELOG.md LICENSE THIRD_PARTY_NOTICES Makefile .gitignore .editorconfig .env.example package.json pnpm-workspace.yaml
```

## 2. 文档关联关系
### 核心追溯链
```text
REQ-INBOX-001/002/003 ─→ product-requirements（REQ-F/NF/C）─→ ADR-001…015 / DESIGN-001…022 / 契约 ─→ SOL-001
        └→ slices S0–S10 ─→ TASK-001…211 ─→ EVD-xxx ─→ VAL-xxx ─→ 07_release
```
### 关键关联
- 需求 → 契约：`03_solution/contracts/README.md` §3
- 需求 → 任务：`05_execution/task-index.md` “来源需求”列
- 任务 → 证据：各卡 §8 `06_validation/evidence/EVD-<id>/`
- 决策历史：V0.0.3 `decision-log.md`（DEC-001…057）→ 本版 ADR；被取代项见 `09_archive/superseded/README.md`

## 3. 当前状态总览
| 区域 | 状态 |
|---|---|
| 需求基线 | approved（36 REQ-F、11 REQ-NF、9 REQ-C） |
| 契约 | frozen（CR-001 后） |
| 数据模型 | frozen（0001+0002） |
| 任务 | 84 张 todo；第一刀 TASK-001 |
| 代码 | 无 |

## 4. 更新规则
目录结构变化、新增模块或新增文档类别时更新本文件（TASK-211 负责 v1 收尾同步）。
