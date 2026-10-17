---
id: DESIGN-011
type: design
title: 配置详细设计（启动级配置全表、业务配置入库与 YAML 导出、doctor、.env.example）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - "DEC-014"
  - "DEC-016"
  - "DEC-020"
  - "DEC-030"
  - "DEC-041"
  - "DEC-044"
  - "DEC-051"
  - "ADR-003"
  - "ADR-005"
  - "ADR-006"
  - "ADR-014"
  - "REQ-F-034"
  - "REQ-F-035"
  - "REQ-C-003"
  - "REQ-NF-004"
  - "WF-ARCH §3（端口段 5100–5200）"
  - "PROJECT-STRUCTURE-SPEC §5.1/§13"
  - "packages/contracts/api/relay.openapi.json（/config/export、/config/import）"
  - "packages/contracts/api/node-local.openapi.json（/local/v1/doctor）"
  - "packages/contracts/identity/{session-claims,device-token-claims}.schema.json"
  - "packages/contracts/resources/resources.json"
  - "DESIGN-002/003/005/010"
---

# DESIGN-011 配置

## 1. 两层配置（DEC-014）
| 层 | 内容 | 存放 | 修改方式 | 是否含密钥 |
|---|---|---|---|---|
| 启动级 | 端口、数据目录、密钥文件位置、日志、限速、超时等进程参数 | 环境变量 > 配置文件（YAML）> 代码默认值 | 改文件/环境后重启 | 只放**密钥文件路径**，不放密钥本身 |
| 业务级 | 项目、智能体、渠道、接收人、绑定、过滤规则、通知偏好（中转）；模型配置、总控设置（节点） | 数据库 | 控制台 UI/API；中转可导出/导入 YAML（REQ-F-034） | 渠道凭据加密入库、模型 Key 在钥匙串；导出永不含密钥 |
- 读取实现：`core/config/schema.ts` 用 JSON Schema（ajv）定义全部启动项及默认值；`load.ts` 合并顺序 env > 文件 > 默认，校验失败打印字段与原因并以退出码 78 退出。配置在进程内只读（不热更新，v1）。
- 命名：环境变量 `WF_` 前缀、大写下划线；YAML 键为 camelCase 嵌套（例 `server.port`），映射表即下文。

## 2. 启动级配置全表
### 2.1 云中转（`apps/relay`，配置文件默认 `/etc/workfleet/relay.yaml`）
| 名称（YAML） | 环境变量 | 默认值 | 说明 | 依据 |
|---|---|---|---|---|
| configFile | `WF_CONFIG_FILE` | `/etc/workfleet/relay.yaml` | 配置文件路径（不存在则只用 env+默认） | DEC-014 |
| server.host | `WF_RELAY_HOST` | `127.0.0.1` | 内部监听地址；doctor 对非回环值告警 | DEC-051 |
| server.port | `WF_RELAY_PORT` | `5101` | 内部监听端口（仅反代可达） | WF-ARCH §3 |
| server.publicUrl | `WF_PUBLIC_URL` | （必填） | 对外 https 地址；用于 claim 返回的 `wsUrl`、Web Push、Cookie 域 | relay.openapi claim |
| server.trustProxy | `WF_TRUST_PROXY` | `loopback` | 信任 X-Forwarded-* 的来源 | — |
| server.shutdownGraceSec | `WF_SHUTDOWN_GRACE_SEC` | `10` | 优雅关停等待 | DESIGN-002 §2 |
| data.dir | `WF_DATA_DIR` | `/var/lib/workfleet` | `relay.db`、`attachments/`、`backup/`、`relay.lock` | WF-ARCH §3 |
| data.sqliteCacheMb | `WF_SQLITE_CACHE_MB` | `64` | SQLite 页缓存 | DESIGN-010 §4 |
| security.masterKeyFile | `WF_MASTER_KEY_FILE` | `/etc/workfleet/master.key` | 32 字节随机主密钥（base64），文件权限必须 0600，缺失拒绝启动；用于渠道凭据、context_token 加密 | DEC-004 |
| security.cookieSecure | `WF_COOKIE_SECURE` | `true` | 会话 Cookie Secure 标志（本地开发可设 false） | session-claims |
| security.sessionTtlDays | `WF_SESSION_TTL_DAYS` | `14` | 滑动过期 | session-claims（14 天） |
| security.registration | `WF_REGISTRATION` | `closed` | `open`/`closed`；用户表为空时始终允许注册首个用户（成为其 personal 组织 admin）。默认关闭以符合“安全默认” | DEC-030（设计选择） |
| log.level | `WF_LOG_LEVEL` | `info` | pino 级别 | — |
| log.format | `WF_LOG_FORMAT` | `json` | `json`/`pretty` | — |
| metrics.enabled | `WF_METRICS_ENABLED` | `true` | `/metrics` 只接受无 `X-Forwarded-For` 的回环请求 | DESIGN-002 W-8 |
| web.distDir | `WF_WEB_DIST` | `<安装目录>/web/relay` | Web relay 目标静态资源 | DESIGN-001 §8 |
| limits.httpPerMinPerIp | `WF_HTTP_RATE_PER_MIN` | `600` | 一般端点 | DESIGN-002 §6 |
| limits.authPerMinPerIp | `WF_AUTH_RATE_PER_MIN` | `10` | `auth/*`、`devices/claim` | 同上 |
| limits.tenantSendPerSec | `WF_TENANT_SEND_RATE` | `50` | 租户级出站令牌桶 | DESIGN-010 §5 |
| limits.inboundPerMinPerRecipient | `WF_INBOUND_RATE_PER_MIN` | `30` | 入站防刷 | DESIGN-010 §5 |
| attachments.maxMb | `WF_ATTACHMENT_MAX_MB` | `25` | 上限（契约 ≤25 MiB，只能调小） | resources.json |
| attachments.retentionDays | `WF_ATTACHMENT_RETENTION_DAYS` | `90` | 全局默认（7–365） | resources.json |
| approvals.timeoutSec | `WF_APPROVAL_TIMEOUT_SEC` | `900` | 审批超时自动拒绝 | DESIGN-005 §3.3（契约未规定时长） |
| recipients.bindCodeTtlSec | `WF_BIND_CODE_TTL_SEC` | `600` | /bind 6 位码有效期 | DESIGN-005 §8.2 |
| barriers.defaultTimeoutSec | `WF_BARRIER_DEFAULT_TIMEOUT_SEC` | `1800` | 创建屏障未指定时的默认（契约范围 10–86400） | barrier.schema |
| delivery.batchSize | `WF_DELIVERY_BATCH` | `50` | 每轮取件/每事务插入上限 | DEC-013 |
| delivery.mergeWindowSec | `WF_MERGE_WINDOW_SEC` | `3600` | p3 合并窗口 | DEC-017、V0.0.2 §1.5 |
| delivery.mergeMaxItems | `WF_MERGE_MAX_ITEMS` | `5` | 窗口内累计条数触发摘要 | 同上 |
| gateway.maxInflightFrames | `WF_GATEWAY_MAX_INFLIGHT` | `512` | 每设备未 ack 窗口 | DESIGN-010 §6 |
| push.vapidPublicKey | `WF_VAPID_PUBLIC_KEY` | （空=禁用 Web Push） | VAPID 公钥 | ADR-014 |
| push.vapidPrivateKeyFile | `WF_VAPID_PRIVATE_KEY_FILE` | `/etc/workfleet/vapid.key` | 私钥文件（0600） | ADR-014 |
| push.vapidSubject | `WF_VAPID_SUBJECT` | （必填若启用） | `mailto:` 或 https URL | ADR-014 |
- **不可配置**（契约固定）：配对码 8 位 / 10 分钟 / 一次性（device-token-claims）；心跳 20 s、60 s 判定离线、单帧 ≤1 MiB（ADR-005、welcome.heartbeatSec const 20）；协议版本 1。

### 2.2 本机节点（`apps/node`，配置文件默认 `<dataDir>/node.yaml`）
| 名称（YAML） | 环境变量 | 默认值 | 说明 | 依据 |
|---|---|---|---|---|
| data.dir | `WF_NODE_DATA_DIR` | Windows `%LOCALAPPDATA%\WorkFleet`；macOS `~/Library/Application Support/WorkFleet`；Linux `${XDG_DATA_HOME:-~/.local/share}/workfleet` | `node.db`、`transcripts/`、`worktrees/`、`tmp/`、`run/`、`node.lock`、`local-token` | DEC-041 |
| configFile | `WF_NODE_CONFIG_FILE` | `<dataDir>/node.yaml` | — | DEC-014 |
| bind | `WF_NODE_BIND` | `127.0.0.1` | **只允许回环地址**（`127.0.0.1`/`::1`），其他值校验失败拒绝启动 | REQ-NF-004、DEC-030 |
| ports.console | `WF_NODE_CONSOLE_PORT` | `5100` | 本机控制台 + node-local API | DEC-016 |
| ports.webhook | `WF_NODE_WEBHOOK_PORT` | `5102` | Webhook 输入 | 同上 |
| ports.mcp | `WF_NODE_MCP_PORT` | `5103` | MCP 推送工具 | 同上 |
| ports.metrics | `WF_NODE_METRICS_PORT` | `5104` | `/metrics` | 同上 |
| sessions.max | `WF_NODE_MAX_SESSIONS` | `8` | 并发执行会话上限（≥8 为验收下限） | REQ-NF-002 |
| sessions.idleReclaimSec | `WF_NODE_IDLE_RECLAIM_SEC` | `900` | 空闲回收（受 loadSession 约束） | REQ-NF-002、DESIGN-003 §5.4 |
| sessions.queueLimit | `WF_NODE_QUEUE_LIMIT` | `50` | 每会话排队上限 | DESIGN-003 §5.1 |
| acp.initTimeoutSec | `WF_NODE_ACP_INIT_TIMEOUT_SEC` | `30` | initialize/session.new 超时 | DESIGN-003 §6.3 |
| acp.statusIntervalSec | `WF_NODE_STATUS_INTERVAL_SEC` | `30` | 状态卡最小间隔 | DESIGN-003 §4.1 |
| acp.extraSpecsDir | `WF_NODE_EXTRA_SPECS_DIR` | `<dataDir>/specs` | 本地覆盖/追加 InputAdapterSpec（JSON，须过契约 schema） | ADR-007 |
| leases.staleSec | `WF_NODE_LEASE_STALE_SEC` | `300` | 写租约心跳失效 | DESIGN-003 §10.1 |
| leases.worktreeDir | `WF_NODE_WORKTREE_DIR` | `<dataDir>/worktrees` | 自动 worktree 位置 | REQ-F-032 |
| keychain.backend | `WF_NODE_KEYCHAIN_BACKEND` | `auto` | `auto`/`dpapi`/`keychain`/`libsecret`/`file`；`auto` 按平台选择，无可用后端时降级 `file` 并 doctor 告警 | DEC-020、DEC-041 |
| keychain.filePassphraseFile | `WF_NODE_KEYCHAIN_PASSPHRASE_FILE` | （空） | `file` 后端的口令文件（0600）；为空时首次启动生成并提示导出恢复密钥 | REQ-F-035 |
| relay.reconnectMaxSec | `WF_NODE_RECONNECT_MAX_SEC` | `60` | 断线重连退避上限 | DESIGN-003 §9 |
| relay.httpsProxy | `WF_NODE_HTTPS_PROXY` | （空，读取 `HTTPS_PROXY`） | 公司网络出站代理；ws 客户端需显式使用代理 agent（实现细节待 TASK-007 实测） | ADR-005（443 穿透代理） |
| mcp.enabled | `WF_NODE_MCP_ENABLED` | `true` | 是否在 session/new 注入 WorkFleet MCP | DEC-022 |
| log.level | `WF_NODE_LOG_LEVEL` | `info` | — | — |
| log.dir | `WF_NODE_LOG_DIR` | Windows `<dataDir>\logs`；macOS `~/Library/Logs/WorkFleet`；Linux `<dataDir>/logs` | 按天滚动，保留 14 天（设计值） | — |
- 中转连接（URL、令牌）不是启动级配置：经 `workfleet-node pair <url> <配对码>` 或本机控制台写入 `relay_links` 与钥匙串（DEC-048）。

## 3. 业务配置入库与 YAML 导出
### 3.1 导出范围（`GET /api/v1/config/export`，需 `config.export`）
包含：组织名、项目树、智能体（别名、项目、设备名、适配器、工作目录、写模式、非密钥配置）、渠道（kind、名称、非密钥配置）、接收人（渠道、平台 id、范围、显示名、授权、静默时段）、绑定、过滤规则、通知偏好（待契约，§5 C-3）。
不包含：任何凭据、令牌、Cookie、Push 订阅密钥、模型配置（模型在节点，DEC-044）、消息与审计。
### 3.2 格式示例
```yaml
# WorkFleet business config export
apiVersion: workfleet.dev/config/v1
exportedAt: 2026-10-17T10:00:00.000Z
tenant:
  name: 个人
  kind: personal
projects:
  - slug: proj-a
    name: 项目A
  - slug: proj-a-web
    name: 项目A·前端
    parent: proj-a
agents:
  - alias: cc1
    project: proj-a
    device: 笔记本            # 按设备名匹配；导入时设备须已配对
    adapterId: claude-code
    workdir: D:\code\proj-a
    writeMode: write
    config: {}
  - alias: z1
    project: proj-a-web
    device: 笔记本
    adapterId: zcode
    workdir: D:\code\proj-a\web
    writeMode: write
channels:
  - name: 我的微信
    kind: wechat_clawbot
    config: {}
    credential: { required: true, note: 导入后需在控制台重新扫码 }   # 永不导出凭据
  - name: 公司飞书
    kind: feishu
    config: { domain: feishu.cn }
    credential: { required: true }
recipients:
  - channel: 我的微信
    platformId: "wxid_xxxx"
    scope: direct
    displayName: 我
    authorized: true
    quietHours: { start: "23:00", end: "07:00", tz: Asia/Shanghai }
filterRules:
  - name: 老板只看汇总
    match: { recipients: [{ channel: 公司飞书, platformId: "ou_boss" }], businessLines: [sales] }
    action: allow_fields
    fields: [summary, revenue]
    maskStyle: partial
routes:
  - name: 微信管理
    project: proj-a
    mode: management
    sources: [cc1, z1]
    targets: [{ channel: 我的微信, platformId: "wxid_xxxx" }]
    defaultSource: cc1
    filterRules: []
    priorityFloor: p3
    enabled: true
```
### 3.3 导入（`POST /api/v1/config/import`，需 `config.import`）
- 先 `confirm=false`：解析 → 用契约实体 schema 校验 → 按**自然键**与现有数据比对（项目 slug、智能体 alias、渠道 name、接收人 (channel, platformId, scope)、绑定 name、规则 name）→ 返回 `diff[]`：`{op: 'create'|'update'|'unchanged'|'conflict', type, key, fields?, reason?}`（diff 项结构契约未定义，§5 C-2）。
- `confirm=true`：单事务写入；遇到 `conflict`（例如设备名不存在、别名被他用、Bot 身份冲突）整体回滚并返回 diff；成功后审计 `config.imported`。
- 不删除导入文件中缺失的对象（只增改），避免误删（设计选择）。

## 4. doctor 检查项（REQ-F-034）
输出统一结构：`{ id, title, status: 'ok'|'warn'|'fail', detail, fix }`；CLI 以表格打印、`--json` 输出 JSON；节点同时由 `GET /local/v1/doctor` 提供。
### 4.1 节点 `workfleet-node doctor`
| id | 检查 | fail/warn 条件 | 修复建议 |
|---|---|---|---|
| node.version | Node 运行时 ≥ 22 | <22 fail | 升级安装包 |
| node.lock | 单实例锁状态 | 被另一存活实例持有 → warn（显示 pid） | — |
| node.ports | 5100/5102/5103/5104 可绑定或已由本实例占用；绑定地址为回环 | 被其他进程占用 fail | 释放端口或改 `WF_NODE_*_PORT`（须在 5100–5200） |
| node.datadir | 数据目录可写、剩余空间 ≥1 GB | 不可写 fail；<1 GB warn | — |
| node.sqlite | SQLite ≥3.40、FTS5 trigram 可用、`PRAGMA integrity_check` 抽检 | 任一失败 fail | — |
| node.keychain | 后端可用：写入/读取/删除测试条目 | 失败 fail；降级 file 后端 warn | 安装 libsecret / 允许钥匙串访问 |
| node.recovery | 是否已导出恢复密钥 | 未导出 warn | 本机控制台“恢复密钥” |
| relay.<label>.dns/tls/ws | 每个中转：DNS 解析、TLS 证书有效、WSS 握手、`welcome` 协议版本 | 任一失败 fail | 检查网络/代理/令牌 |
| relay.<label>.clock | 与 `welcome.serverTime` 偏差 | >60 s warn | 校准系统时间 |
| relay.<label>.token | 设备令牌有效（非吊销） | 401/403 fail | 重新配对 |
| adapter.<id> | 每个已配置智能体：命令可解析、版本 ≥ minVersion（`detect.versionCommand`） | 缺失 fail；版本低 warn；experimental 显示“实验” | 安装/升级对应工具并登录 |
| git | git 可执行（worktree 需要） | 缺失 warn | 安装 git |
| autostart | 自启已启用 | 未启用 warn | `workfleet-node autostart enable` |
| linux.linger | 无图形会话的 Linux：是否启用 linger | 未启用 warn | `loginctl enable-linger <user>` |
| windows.longpaths | Windows 长路径支持设置（只读检测） | 未开启 warn（证据不足：对 Node/git 的实际影响待实测） | 系统设置开启长路径 |
| models.<name> | 模型配置存在且 Key 条目存在（不发请求；`--with-model-test` 才调用 `/test`，会产生费用） | Key 条目缺失 fail | 重新填写 Key |
| emergency | 是否处于急停 | 急停中 warn | 控制台恢复 |
### 4.2 中转 `workfleet-relay doctor`
| id | 检查 | 条件 |
|---|---|---|
| relay.masterkey | 主密钥文件存在、32 字节、权限 0600、属主为服务用户 | 否则 fail |
| relay.bind | 监听地址为回环 | 否则 warn（DEC-051） |
| relay.public | `WF_PUBLIC_URL/api/v1/health` 经 443 可达且证书有效 | 否则 fail |
| relay.sqlite | 版本、FTS5 trigram、integrity 抽检、库大小（>20 GB warn，ADR-003 触发条件） | — |
| relay.datadir | 可写、剩余空间 | — |
| relay.vapid | Web Push 已配置（未配置 warn：PWA 推送不可用） | — |
| relay.channels | 每个渠道健康状态（expired/disconnected → warn） | — |
| relay.registration | `WF_REGISTRATION=open` → warn | — |
| relay.time | 系统时钟与 NTP 同步状态（只读检测，平台差异证据不足） | — |

## 5. `.env.example`（仓库根，唯一，无密钥；PROJECT-STRUCTURE-SPEC §5.1/§13；归 Agent-Guard 维护）
```dotenv
# ============================================================
# WorkFleet .env.example —— 只列变量名与示例值，绝不写真实密钥
# 优先级：环境变量 > 配置文件(relay.yaml / node.yaml) > 默认值
# 详见 docs/WorkFleet-V0.0.4/03_solution/design/DESIGN-011-配置.md
# ============================================================

# ---------- 云中转 apps/relay ----------
WF_PUBLIC_URL=https://relay.example.com
WF_RELAY_HOST=127.0.0.1
WF_RELAY_PORT=5101
WF_DATA_DIR=/var/lib/workfleet
WF_CONFIG_FILE=/etc/workfleet/relay.yaml
# 32 字节随机主密钥（base64）所在文件，权限 0600；生成：openssl rand -base64 32 > master.key
WF_MASTER_KEY_FILE=/etc/workfleet/master.key
WF_TRUST_PROXY=loopback
WF_COOKIE_SECURE=true
WF_SESSION_TTL_DAYS=14
WF_REGISTRATION=closed
WF_LOG_LEVEL=info
WF_LOG_FORMAT=json
WF_METRICS_ENABLED=true
WF_HTTP_RATE_PER_MIN=600
WF_AUTH_RATE_PER_MIN=10
WF_TENANT_SEND_RATE=50
WF_INBOUND_RATE_PER_MIN=30
WF_ATTACHMENT_MAX_MB=25
WF_ATTACHMENT_RETENTION_DAYS=90
WF_APPROVAL_TIMEOUT_SEC=900
WF_BIND_CODE_TTL_SEC=600
WF_BARRIER_DEFAULT_TIMEOUT_SEC=1800
WF_DELIVERY_BATCH=50
WF_MERGE_WINDOW_SEC=3600
WF_MERGE_MAX_ITEMS=5
WF_GATEWAY_MAX_INFLIGHT=512
# Web Push（留空则禁用）；生成：npx web-push generate-vapid-keys（工具许可见 DESIGN-008）
WF_VAPID_PUBLIC_KEY=
WF_VAPID_PRIVATE_KEY_FILE=/etc/workfleet/vapid.key
WF_VAPID_SUBJECT=mailto:admin@example.com

# ---------- 本机节点 apps/node（只绑 127.0.0.1） ----------
# WF_NODE_DATA_DIR=            # 留空使用平台默认目录
WF_NODE_BIND=127.0.0.1
WF_NODE_CONSOLE_PORT=5100
WF_NODE_WEBHOOK_PORT=5102
WF_NODE_MCP_PORT=5103
WF_NODE_METRICS_PORT=5104
WF_NODE_MAX_SESSIONS=8
WF_NODE_IDLE_RECLAIM_SEC=900
WF_NODE_QUEUE_LIMIT=50
WF_NODE_ACP_INIT_TIMEOUT_SEC=30
WF_NODE_STATUS_INTERVAL_SEC=30
WF_NODE_LEASE_STALE_SEC=300
WF_NODE_KEYCHAIN_BACKEND=auto
# WF_NODE_KEYCHAIN_PASSPHRASE_FILE=
WF_NODE_RECONNECT_MAX_SEC=60
# WF_NODE_HTTPS_PROXY=http://proxy.example.com:8080
WF_NODE_MCP_ENABLED=true
WF_NODE_LOG_LEVEL=info

# ---------- 测试（E2E 端口段 5110–5119 / 5190–5200） ----------
# WF_RELAY_PORT=5110
```

## 6. 与契约的差异 / 待办
| # | 发现 | 处理 |
|---|---|---|
| C-1 | 契约未规定审批超时、/bind 码 TTL、屏障默认超时、合并窗口参数 | 本文给默认值并可配置；建议契约在相关 schema 描述中引用“可配置，默认见 DESIGN-011” |
| C-2 | `/config/import` 响应 `diff` 项为未定义结构的 object；导出 YAML 本身无 schema | §3.3 约定 diff 结构；建议契约新增 `config/export.schema.json`（YAML 结构的 JSON Schema） |
| C-3 | 通知偏好/备用渠道无端点与表，无法入库与导出 | v1 备用渠道按 DESIGN-002 §7.4 固定规则；需契约 + 迁移补齐 |
| C-4 | 节点侧业务配置（模型配置不含 Key、总控规则）无导出端点；REQ-F-034 只要求 YAML 导出（中转端点已有） | v1 不提供节点导出；换机依赖恢复密钥（REQ-F-035） |
| C-5 | 组织级附件保留期（7–365）无存放列与端点 | 只提供全局 `WF_ATTACHMENT_RETENTION_DAYS`；见 DESIGN-004 D-5 |
| C-6 | 中转 metrics 端口未分配 | 复用 5101 的 `/metrics` 并限制回环（DESIGN-002 W-8） |
