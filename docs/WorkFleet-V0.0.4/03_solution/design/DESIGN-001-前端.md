---
id: DESIGN-001
type: design
title: 前端详细设计（apps/web：一份 SPA，relay / node 两个构建目标）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "WF-ARCH §3/§5/§6.4"
  - "ADR-008"
  - "ADR-014"
  - "ADR-012"
  - "ADR-011"
  - "DEC-010"
  - "DEC-056"
  - "DEC-057"
  - "REQ-F-015"
  - "REQ-F-016"
  - "REQ-F-018"
  - "REQ-F-020"
  - "REQ-NF-011"
  - "packages/contracts/api/relay.openapi.json"
  - "packages/contracts/api/node-local.openapi.json"
  - "packages/contracts/ux/ux-states.json"
  - "packages/contracts/errors/error-codes.json"
  - "packages/contracts/identity/permissions.json"
  - "PROJECT-STRUCTURE-SPEC §10/§11"
  - "ownership-matrix.md（Agent-App 路径）"
---

# DESIGN-001 前端

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断。本文所有“设计值”（如预算数值、轮询间隔）均为规划者给出，可在实现任务中按实测调整，但改动需回写本文。

## 1. 范围与原则
| 原则 | 内容 | 依据 |
|---|---|---|
| 一份代码两个目标 | `relay`：多用户控制台 + 对话 + PWA，部署在中转 443；`node`：本机控制台（中转连接、适配器探测、模型配置与 Key、总控、分身、doctor），由节点 127.0.0.1:5100 提供 | WF-ARCH §3、ADR-008 |
| 契约唯一 | 所有请求/响应类型从 `@workfleet/contracts/generated` 导入；前端不手写 DTO | ADR-002 |
| Schema 驱动表单 | 输入适配器 `configSchema`、渠道 `configSchema` 由 `@rjsf/core` 渲染，新增渠道/智能体零前端代码 | DEC-010、REQ-NF-008 |
| 六态必实现 | `ux-states.json` 中每个 screen 实现 6 态，根节点带 `data-ux-state` | 契约 ⑥ |
| 依赖方向 | `pages → features → components/ui → lib`；`features` 之间只经对方 `index.ts` | WF-ARCH §5、PROJECT-STRUCTURE-SPEC §3.2 |
| Key 不进中转目标 | 模型 Key 输入框只存在于 `targets/node/**`；relay 构建产物中出现 `apiKey` 字段即 CI 失败 | DEC-044、permissions.json forbiddenPaths |

## 2. 技术栈（ADR-008 已定，此处给出用法）
| 关注点 | 选型 | 用法约束 |
|---|---|---|
| 框架 | React 19 + TypeScript strict | 只用函数组件；不用 Server Components |
| 构建 | Vite | `vite build --mode relay` / `--mode node`；见 §8 |
| 路由 | React Router（数据路由 `createBrowserRouter`） | 路由表在 `app/router.relay.tsx` / `app/router.node.tsx`，只引用 `pages/` |
| 服务端状态 | TanStack Query | 所有 GET；mutation 成功后按 §6.1 失效 |
| 客户端状态 | Zustand | 仅全局 UI 态与实时连接态（§6.2） |
| UI 原语 | Radix + shadcn/ui（源码拷入 `components/ui`）+ Tailwind 4 | `components/ui` 不得 import `features/` |
| 表单 | `@rjsf/core` + `@rjsf/validator-ajv8`（Apache-2.0，ADR-008） | 自定义 widgets 映射到 shadcn 组件；见 §7 |
| i18n | `i18next` + `react-i18next`（许可待 TASK-009 核实） | 见 §11 |
| PWA | 手写 service worker（`src/pwa/sw.ts`，Vite 单独入口） | 不引入 Workbox 以控制体积（推断，可推翻）；见 §9 |

## 3. 页面清单与路由

### 3.1 relay 目标
| 路由 | 页面组件（pages/） | ux screen | 主要 API（relay.openapi） | 所需权限 | 切片/任务 |
|---|---|---|---|---|---|
| `/login` | `auth/LoginPage` | login | `POST /auth/login` | public | S0/TASK-009 |
| `/register` | `auth/RegisterPage` | register | `POST /auth/register` | public | S0/TASK-009 |
| `/invite/:token` | `auth/InviteAcceptPage` | （缺，见 §13） | （缺端点，见 §13） | public | S7/TASK-145 |
| `/` | 重定向：无设备 → `/devices/pair`；否则 → `/chat` | — | `GET /me`、`GET /devices` | — | S0 |
| `/onboarding` | `onboarding/WizardPage`（P1/P2 画像向导） | （缺） | channels/routes/agents 组合 | agent.write 等 | S10/TASK-208 |
| `/devices` | `devices/DeviceListPage` | device_list | `GET /devices`、`POST /devices/{id}/primary|revoke|rotate-token` | device.read | S0/TASK-009 |
| `/devices/pair` | `devices/PairDevicePage` | device_pairing | `POST /devices/pairing-codes` | device.pair | S0/TASK-009 |
| `/projects` | `projects/ProjectTreePage` | project_tree | `GET/POST/PATCH /projects`、`GET /projects/{id}/overview` | project.read | S3/TASK-065 |
| `/agents` | `agents/AgentListPage` | agent_list | `GET /agents` | agent.read | S1/TASK-027 |
| `/agents/new`、`/agents/:agentId` | `agents/AgentFormPage` | agent_form | `GET /adapters/input`、`POST/PATCH/DELETE /agents` | agent.write | S1/TASK-027 |
| `/channels` | `channels/ChannelListPage` | channel_list | `GET /channels`、`DELETE`、`POST /test` | channel.read | S2/TASK-046 |
| `/channels/new`、`/channels/:channelId` | `channels/ChannelFormPage` | channel_form | `GET /adapters/channel`、`POST /channels`、`POST /{id}/credential` | channel.write / channel.bind_credential | S2 |
| `/channels/:channelId/wechat-qr` | `channels/WechatQrPage` | channel_bind_wechat_qr | `POST /{id}/qr-login`、`GET /{id}/qr-login/{loginId}` | channel.bind_credential | S2/TASK-046 |
| `/recipients` | `recipients/RecipientListPage`（含“输入 6 位识别码”框） | recipient_list | `GET /recipients`、`POST /{id}/authorize`、`POST /recipients/bind-confirm`、`PATCH` | recipient.read | S2 |
| `/routes` | `routes/RouteListPage` | route_list | `GET /routes` | route.read | S2 |
| `/routes/new`、`/routes/:routeId` | `routes/RouteEditorPage`（左编辑、右 dry-run） | route_editor_dry_run | `POST/PATCH/DELETE /routes`、`POST /routes/dry-run` | route.write / route.dry_run | S2/S5 |
| `/barriers` | `routes/BarrierListPage` | （缺） | `GET/POST /barriers` | route.read | S5/TASK-104 |
| `/chat`、`/chat/:conversationId` | `chat/ChatPage` | chat | conversations、messages、clear、cancel、`/stream` | conversation.read（发送需 agent.prompt） | S0/S1 |
| `/history` | `history/HistoryPage` | conversation_history | `GET /history/search` | history.search | S1/TASK-027 |
| `/approvals` | `approvals/ApprovalInboxPage` | approval_inbox | `GET /approvals`、`POST /approvals/{id}/decide` | conversation.read（决策需 approval.decide_*） | S1/TASK-029 |
| `/audit` | `audit/AuditLogPage` | audit_log | `GET /audit` | audit.read | S7 |
| `/audit/deliveries` | `audit/DeliveryListPage`（含死信重放） | （缺） | `GET /deliveries`、`POST /deliveries/{id}/replay` | audit.read / channel.write | S7 |
| `/members` | `members/MembersPage` | members | `GET /members`、invitations、PATCH/DELETE | tenant.read | S7 |
| `/filters` | `members/FilterRulesPage`（文件归属 features/filters） | filter_rules | `GET/POST/PATCH/DELETE /filter-rules` | filter.read | S7 |
| `/settings/notifications` | `settings/NotificationsPage` | notifications_settings | `GET /push/vapid-public-key`、`POST /push-subscriptions` | notification.subscribe | S10 |
| `/settings/config` | `settings/ConfigIoPage` | （缺） | `GET /config/export`、`POST /config/import` | config.export / config.import | S10 |
| 全局横幅 | `components/layout/EmergencyBanner` | emergency_banner | `POST /emergency/stop-all|resume` | emergency.* | S10 |
| `*` | `error/NotFoundPage` | — | — | — | S0 |

> `pages/settings/**` 与 `pages/onboarding/**` 不在 ownership-matrix 的 Agent-App 路径中（矩阵列出了 `features/onboarding/**` 但未列 `pages/onboarding`、`pages/settings`），见 §13。

### 3.2 node 目标（本机控制台）
| 路由 | 页面（`src/targets/node/pages/`） | ux screen | API（node-local.openapi） |
|---|---|---|---|
| `/` | `StatusPage`（版本、中转连接、资源） | node_local_doctor 的子集 | `GET /local/v1/status` |
| `/relay-links` | `RelayLinksPage`（新增中转：URL + 配对码） | （缺） | `GET/POST/DELETE /local/v1/relay-links` |
| `/agents` | `LocalAgentsPage`（探测结果 + 本机智能体运行态） | node_local_agents | `GET /local/v1/adapters/detect`、`GET /local/v1/status`（agents 字段） |
| `/models` | `models/ModelProfilesPage`、`models/ModelProfileForm` | node_local_models | `/local/v1/model-profiles*`、`/usage` |
| `/supervisor` | `supervisor/SupervisorPage`（模型选择、规则、降级状态、导入任务） | （缺） | `GET/PUT /local/v1/supervisor`、`POST /supervisor/import-tasks` |
| `/meetings` | `supervisor/MeetingsPage`（回放） | （缺） | （缺端点，见 §13） |
| `/twin` | `twin/TwinPage`（查看/修改/删除/导出） | node_local_twin | `/local/v1/twin/*` |
| `/doctor` | `DoctorPage` | node_local_doctor | `GET /local/v1/doctor` |
| `/recovery` | `RecoveryKeyPage` | （缺） | `POST /local/v1/recovery-key/export|import` |

## 4. 目录树（apps/web，文件级到 feature 内部约定）
```text
apps/web/
├── index.html                         # relay 入口 HTML
├── index.node.html                    # node 入口 HTML（同一 main，不同 target 常量）
├── public/
│   ├── manifest.webmanifest           # 仅 relay 目标拷贝（ADR-014）
│   └── icons/{192,512,maskable-512}.png
├── vite.config.ts                     # 依据 mode 切换 input / define / outDir（§6）
└── src/
    ├── main.tsx                       # 唯一入口：读取 __WF_TARGET__，挂载 <App/>
    ├── app/
    │   ├── App.tsx
    │   ├── providers.tsx              # QueryClientProvider、I18nextProvider、Tooltip、Toaster、StreamProvider
    │   ├── query-client.ts            # 默认 staleTime 30s、retry 依据 error.retryable（§6.1）
    │   ├── router.relay.tsx           # 只引用 pages/*
    │   ├── router.node.tsx            # 只引用 targets/node/pages/*
    │   └── guards.tsx                 # RequireAuth / RequirePermission(action) / RequireDevice
    ├── pages/                         # 只组合 features，无业务逻辑（§3.1 列表）
    │   ├── auth/ devices/ projects/ agents/ channels/ recipients/ routes/
    │   ├── chat/ history/ approvals/ audit/ members/ settings/ onboarding/ error/
    ├── features/
    │   ├── auth/            {components/LoginForm,RegisterForm, hooks/useMe,useLogin, api/auth.api.ts, index.ts}
    │   ├── devices/         {components/DeviceTable,PairingCodeCard, hooks/useDevices, api/, primary/, index.ts}
    │   ├── projects/        {components/ProjectTree,ProjectOverview, hooks/useProjectTree, api/, utils/buildTree.ts}
    │   ├── agents/          {components/AgentTable,AgentForm,AdapterPicker,StatusDot, hooks/, api/}
    │   ├── channels/        {components/ChannelTable,ChannelForm,WechatQr,HealthBadge,CapabilityList, hooks/useQrLogin, api/}
    │   ├── recipients/      {components/RecipientTable,BindCodeInput,QuietHoursEditor, api/}
    │   ├── routes/          {components/RouteForm,ModePicker,DryRunPanel,TargetPicker, modes/{management,notification,team,supervisor}.ts, api/}
    │   ├── barriers/        {components/BarrierForm,BarrierStatus, api/}
    │   ├── chat/            {components/ConversationList,MessageList,MessageItem,Composer,ApprovalCard,StatusCard,OfflineNotice,
    │   │                     commands/{parse.ts,suggest.ts}（只做输入提示；解析以服务端为准）, hooks/useConversation,useSend, store/chat.store.ts}
    │   ├── history/         {components/SearchBox,ResultList,TranscriptView, api/}
    │   ├── approvals/       {components/ApprovalInbox,DecideButtons, api/}
    │   ├── audit/           {components/AuditTable,DeliveryTable,ReplayButton, api/}
    │   ├── members/         {components/MemberTable,InviteDialog,ScopePicker, api/}
    │   ├── filters/         {components/FilterRuleForm,FieldMaskPreview, api/}
    │   ├── onboarding/      {components/WizardP1,WizardP2, utils/defaults.ts}
    │   ├── meetings/ tasks/ （node 目标使用，见 targets/node）
    │   └── local-*/         （node 目标专用 feature：local-relay-links、local-agents、local-doctor）
    ├── targets/node/
    │   ├── pages/  models/  supervisor/  twin/   # 仅 node 构建可达；relay 构建引用即 guard 失败
    ├── components/
    │   ├── ui/              # shadcn 原子组件（Button、Dialog、Table、Form、Skeleton、Toast、Badge…）
    │   ├── layout/          # AppShell、Sidebar、Header、EmergencyBanner、OfflineBanner、TenantSwitcher
    │   ├── ux/              # UxState（六态容器）、ErrorPanel（traceId 复制）、NoPermission、EmptyState
    │   └── schema-form/     # SchemaForm（rjsf 包装）+ widgets/（Text、Select、Secret、Path、Switch）
    ├── data-access/
    │   ├── client.ts        # fetch 包装：credentials:'include'、X-CSRF-Token、Idempotency-Key、错误解析为 ApiError
    │   ├── endpoints.ts     # 由 openapi 生成的路径常量（禁止手写字符串路径）
    │   ├── stream.ts        # /api/v1/stream WebSocket 客户端（重连、心跳、事件分发到 Query 缓存）
    │   └── local-client.ts  # node 目标：/local/v1，本机令牌 Cookie
    ├── stores/app.store.ts  # 全局：主题、语言、当前 tenant、侧栏
    ├── lib/{hooks/,utils/format.ts（时间/金额 micros）, utils/ids.ts}
    ├── constants/{routes.ts, query-keys.ts}
    ├── i18n/{index.ts, locales/zh-CN/*.json, locales/en-US/*.json}
    ├── pwa/{sw.ts, register.ts, push.ts}
    └── styles/{globals.css, tokens.css}
```

## 5. 组件分层
| 层 | 允许依赖 | 示例 | 守卫 |
|---|---|---|---|
| `pages/` | features、components/layout | `ChatPage` = `ConversationList` + `MessageList` + `Composer` | ESLint `no-restricted-imports`：禁止 pages → data-access |
| `features/<x>/` | components/*、data-access、lib、contracts/generated、其他 feature 的 `index.ts` | `features/chat` 引用 `features/approvals` 的 `ApprovalCard`（经 index） | dependency-cruiser：禁止 `features/a → features/b/(components|hooks|api)/**` |
| `components/ui|layout|ux|schema-form` | lib | 无业务词汇（不得出现 agent/channel 等字样的 props） | 禁止 → features |
| `data-access/` | lib、contracts | 唯一 fetch/WebSocket 处 | 禁止 → features |
| `lib/` | 无 | 纯函数 | 禁止任何 src 内部依赖 |

## 6. 状态管理
### 6.1 服务端状态（TanStack Query）
- Query key 规范（`constants/query-keys.ts`）：`['me']`、`['devices']`、`['agents', {projectId, deviceId}]`、`['conversations', filter]`、`['messages', conversationId, generation?]`、`['approvals', 'pending']`、`['routes']`、`['channels']`、`['recipients']`、`['audit', filter]`。
- `retry`：读 `ApiError.retryable`（来自 `error.schema.json`），`retryable=false` 不重试；`retryable=true` 最多 2 次，指数 500ms→1500ms；`RATE_LIMITED` 读 `details.retryAfterSec`。
- 消息列表用 `useInfiniteQuery`，游标分页（`page.schema.json`，不用 offset）。
- Mutation 失效表：

| Mutation | 失效 |
|---|---|
| 发送消息 | 乐观追加到 `['messages', id]`（状态 sending），收到 202 的 `message` 后替换；stream 推送 `message.appended` 去重（按 `id`） |
| `/clear` | `['conversations']`、`['messages', id]` |
| 审批 | `['approvals','pending']`、对应消息内 ApprovalCard（本地 patch） |
| 绑定/渠道/接收人增删改 | 对应列表 key |

### 6.2 客户端状态（Zustand）
```ts
// stores/app.store.ts
interface AppState { theme: 'light'|'dark'|'system'; locale: 'zh-CN'|'en-US'; sidebarOpen: boolean; }
// features/chat/store/chat.store.ts
interface ChatState {
  streamStatus: 'connecting'|'open'|'closed'; lastOpenAt: number|null;
  drafts: Record<ConversationId, string>;      // 同步写 IndexedDB（离线草稿，WF-ARCH §3）
  emergency: { stopped: boolean; at: string|null };
}
```
禁止把服务端实体复制进 Zustand（单一事实源 = Query 缓存）。

### 6.3 实时通道（`data-access/stream.ts`）
- 连接 `wss://<relay>/api/v1/stream`（Cookie 鉴权，契约 x-auth=session）；心跳：客户端每 20 s 发 `{"type":"ping"}`，40 s 未收到任何帧即重连（与 ADR-005 的 20 s 心跳同节拍，推断）。
- 重连退避：1 s、2 s、4 s … 上限 30 s，加 ±20% 抖动；重连成功后对所有活跃 `['messages', id]` 执行 `invalidateQueries`（以 REST 补齐断线期间的消息，不依赖 stream 补发）。
- 事件 → 缓存映射（**事件格式契约未定义**，见 §13；以下为临时约定，由 TASK-010 实现时与中转同步固化）：

| 事件 type | data | 前端动作 |
|---|---|---|
| `message.appended` | `message`（message.schema） | `setQueryData(['messages', cid])` 追加/替换 |
| `conversation.updated` | `conversation` | 更新列表项（generation、title、state） |
| `approval.requested` / `approval.decided` | `approval` | 更新收件箱与消息内卡片；requested 时若页面不可见则依赖 Web Push |
| `agent.status` | `{agentId,status,queueDepth}` | 更新 `['agents']` 中状态点 |
| `device.status` | `{deviceId,status,lastSeenAt}` | 更新设备与 OfflineBanner |
| `delivery.updated` | `delivery` | 审计页实时刷新 |
| `emergency.changed` | `{stopped,at}` | 切换全局横幅 |

## 7. Schema 驱动表单（DEC-010）
- `components/schema-form/SchemaForm.tsx`：`<SchemaForm schema uiSchema formData onSubmit errors>`，内部 `@rjsf/core` + `validator-ajv8`，主题 = 自写 shadcn widgets。
- 数据来源：智能体表单 `GET /adapters/input` 每项的 `configSchema`（`input-adapter-spec.schema.json`）；渠道表单 `GET /adapters/channel` 的 `configSchema`。
- 约定的 JSON Schema 扩展（只在 uiSchema 中用，不改契约）：

| 字段特征 | widget | 说明 |
|---|---|---|
| `title` 含“目录”或字段名 `workdir` | `PathWidget`（文本 + 提示“在本机路径”） | 中转无法浏览本机文件系统；只做格式校验 |
| 字段名以 `Ref` 结尾（`keyRef`、`secretRef`） | `SecretRefWidget` | relay 目标只显示“请在本机控制台设置”，不出现明文输入（DEC-044）；node 目标显示密码框并经 node-local API 写钥匙串 |
| `enum` | `SelectWidget` | — |
| `boolean` | `SwitchWidget` | — |
- 服务端错误 `VALIDATION_FAILED.details.fields[]`（error-codes ui 列）映射到 rjsf `extraErrors`。
- 渠道凭据（token/secret）**不在 configSchema 中**，走 `POST /channels/{id}/credential` 单独表单，提交后清空本地状态、不回显（契约摘要“响应不回显”）。

## 8. 两个构建目标
| 项 | relay | node |
|---|---|---|
| Vite mode | `relay` | `node` |
| define | `__WF_TARGET__='relay'` | `__WF_TARGET__='node'` |
| HTML 入口 | `index.html` | `index.node.html` |
| 路由表 | `router.relay.tsx` | `router.node.tsx` |
| 数据访问 | `client.ts`（/api/v1，Cookie+CSRF） | `local-client.ts`（/local/v1，本机令牌 Cookie） |
| 输出目录 | `apps/web/dist/relay` → 中转静态托管 | `apps/web/dist/node` → 打包进节点安装包，由 `local-console` 托管 |
| PWA | 是（manifest + sw） | 否 |
| 可引用 | `src/**` 除 `targets/node/**` | 全部 |
- 守卫：dependency-cruiser 规则 `relay-must-not-import-node-target`；CI 对 `dist/relay` grep `apiKey|keyRef.*value` 必须为空（ADR-011）。
- 跳转：relay 目标设备页“打开本机控制台”按钮只给出 `http://127.0.0.1:5100` 文本链接（浏览器在用户本机打开才有效），不做跨源调用。

## 9. PWA 与 Web Push（ADR-014、DEC-057）
1. `pwa/register.ts`：仅 relay 目标、仅 HTTPS、登录后注册 `/sw.js`（scope `/`）。
2. 订阅流程（`/settings/notifications`）：`GET /push/vapid-public-key` → `Notification.requestPermission()`（必须由用户点击触发）→ `pushManager.subscribe({userVisibleOnly:true, applicationServerKey})` → `POST /push-subscriptions`（endpoint、p256dh、auth；`min_priority` 默认 p1，对应表 `push_subscriptions.min_priority`）。
3. `sw.ts`：`push` 事件显示通知（title=`[项目/别名] 摘要`，`data.url` = `/chat/{conversationId}` 或 `/approvals`）；`notificationclick` 聚焦已有窗口或打开 url。sw **不缓存 API 响应**，只缓存静态资源（版本化文件名，install 时预缓存 `index.html`+入口 chunk），离线时显示 offline 态页面。
4. iOS：仅“添加到主屏幕”且 iOS 16.4+ 支持 Web Push（ADR-014 部分确认，U-07，TASK-203/204 实测）；不满足时设置页显示说明，不显示订阅按钮。
5. 取消订阅：前端 `subscription.unsubscribe()`；中转侧无删除端点（见 §13），依赖中转推送 410 时清理（DESIGN-002 §7.5）。

## 10. UX 六态实现（契约 ⑥）
```tsx
// components/ux/UxState.tsx
type UxStateName = 'empty'|'loading'|'error'|'no_permission'|'success'|'offline';
<UxState screen="chat" state={s} error={apiError} empty={{reason, action}} offline={{lastSeenAt, queued}}>
  {children}
</UxState>   // 根元素 <section data-ux-state={s} data-ux-screen="chat">
```
| 态 | 实现规则（来自 ux-states.json） | 触发 |
|---|---|---|
| empty | 说明为何为空 + 一个主按钮（文案见 DESIGN-005 §9） | Query 成功且列表为空 |
| loading | `useDelayedFlag(isPending, 200)`：<200 ms 不显示骨架 | 首次加载 |
| error | `error-codes.json` 的 `ui` 文案 + traceId 复制按钮 + `retryable` 时显示重试 | ApiError 且非 403 |
| no_permission | 独立组件，说明所需角色（由 `permissions.json` 反查最小角色），不渲染数据 | 403 `FORBIDDEN` 或前端 `can(action)` 为假 |
| success | Toast 2.5 s；列表就地更新 | mutation 成功 |
| offline | 横幅：最后在线时间 + 排队数 | stream 断开 >5 s，或目标设备 `offline`（`DEVICE_OFFLINE`） |
- 权限判断：`useCan(action)` 读取 `GET /me.permissions`；仅用于隐藏/禁用控件，服务端仍是最终裁决（ADR-006）。
- E2E 断言：Playwright 用 `[data-ux-state=…]`（契约 `dataAttribute`）。

## 11. i18n
- 默认 `zh-CN`；`en-US` 只放键骨架（BL-011 v2 补译）。命名空间 = feature 名（`chat.json`、`routes.json`…）+ `common.json` + `errors.json`。
- `errors.json` 以错误码为键（`"DEVICE_OFFLINE": "设备离线，已排队"`），文案初值取 `error-codes.json` 的 `ui` 列；ESLint 规则禁止 JSX 中出现中文字面量（REQ-NF-011“文案集中”）。
- 时间：API 为 RFC 3339 UTC（ADR-012），显示时按浏览器时区格式化；金额 `amountMicros/1e6` + `currency`（仅 node 目标用量页）。

## 12. 包体积预算与可访问性
### 12.1 体积预算（设计值，DESIGN-010 §2 同步）
| 产物 | 预算（gzip） | 依据/手段 |
|---|---|---|
| relay 首屏（登录→聊天）入口 JS | ≤ 180 KB | REQ-NF-011：4G 下首屏可交互 ≤3 s；React+Router+Query+Zustand+Radix 基础 |
| 每个路由懒加载 chunk | ≤ 80 KB | `React.lazy` 按 pages 拆分 |
| `@rjsf` + ajv | 单独 chunk，只在 agent_form/channel_form 加载 | 不进首屏 |
| CSS | ≤ 30 KB | Tailwind 4 按需 |
| node 目标总 JS | ≤ 400 KB | 本机加载，不受 4G 约束 |
- CI：`vite build` 后脚本统计 gzip 大小，超预算即失败（TASK-014 增加，或 TASK-210 首次测量后启用；尚无基线）。

### 12.2 可访问性
- 目标 WCAG 2.1 AA（设计目标，未审计）。Radix 原语提供键盘与焦点管理；所有图标按钮带 `aria-label`（i18n）。
- 消息流容器 `role="log" aria-live="polite"`；审批卡与急停横幅 `aria-live="assertive"`。
- 颜色对比 ≥ 4.5:1（tokens 中定义）；状态点除颜色外附文字（在线/离线/待审批）。
- 尊重 `prefers-reduced-motion`；所有交互可键盘完成（Composer：Enter 发送、Shift+Enter 换行、↑ 编辑草稿）。

## 13. 与契约的差异 / 待办
| # | 发现 | 影响 | 处理（不改契约） |
|---|---|---|---|
| F-1 | `/api/v1/stream` 只声明 101 升级，**事件帧格式未在契约中定义** | 前后端可能各写一套 | §6.3 临时约定；建议 Agent-Contract 新增 `api/stream-events.schema.json` |
| F-2 | 无“接受邀请”端点（`POST /members/invitations` 只返回链接） | `/invite/:token` 页无法实现 | 待契约补 `POST /api/v1/invitations/{token}/accept` |
| F-3 | 有 `TOTP_REQUIRED` 错误码与 `users.totp_secret_enc`，但无 TOTP 绑定/校验端点 | 二次验证弹窗无法实现 | v1 前端不做 TOTP UI，待契约补 |
| F-4 | `ux-states.json` 缺 screen：barriers、deliveries、onboarding、relay_links、supervisor、meetings、tasks、recovery、config_io、invite_accept | 这些页的六态无 E2E 断言名 | 实现时仍做六态，screen 名暂用路由名；待契约补 |
| F-5 | node-local API 无会议/任务看板端点、无本机智能体列表端点（`node_local_agents` 有 screen 无专门端点） | TASK-183 会议回放无数据源 | 暂用 `/local/v1/status` 中 agents 字段（字段结构契约未细化）；待契约补 `/local/v1/meetings*`、`/local/v1/tasks` |
| F-6 | 无删除 Push 订阅端点；无备用渠道/通知偏好设置端点 | notifications_settings 只能“订阅” | 见 DESIGN-002 §7.5 的 410 清理；待契约补 |
| F-7 | ownership-matrix 未列 `pages/settings/**`、`pages/onboarding/**`、`targets/node/pages/**` 中部分路径 | Agent-App 改这些路径属越界 | 由规划方补矩阵，或把这些页并入已列路径 |
