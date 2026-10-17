---
id: DESIGN-014
type: design
title: 存储（数据目录布局、加密与钥匙串、附件、转录 JSONL、备份恢复、保留期与清理）
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
sources:
  - DEC-003/004/014/020/037/041/044/049
  - ADR-003、ADR-006、ADR-009、ADR-012
  - REQ-F-026/029/035、REQ-NF-004/005/006
  - packages/contracts/resources/resources.json
  - packages/contracts/schemas/entities/model-profile|relay-link|channel.schema.json
  - packages/contracts/api/node-local.openapi.json（recovery-key/*、twin/export）
  - database/migrations/relay/0001_init.sql、database/migrations/node/0001_init.sql
---

# DESIGN-014：存储

> 证据标签：已确认 / 部分确认 / 证据不足 / 推断 / 待实测。

## 1. 总则
- 两侧均为 SQLite（WAL，单写者）+ 文件目录（ADR-003、DEC-004）。
- 每个进程启动时对每个连接执行：
  `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000; PRAGMA temp_store=MEMORY;`
  （`synchronous=NORMAL` 在 WAL 下掉电可能丢最后若干事务但不损坏库——SQLite 官方语义，已确认；outbox 至少一次 + 幂等键兜底，REQ-NF-003）。
- 单实例锁：数据目录下 `*.lock` 文件（`O_EXCL` 创建，写入 PID+启动时间；启动时若 PID 不存在则回收陈旧锁，DEC-003）。
- 迁移只追加（0001 头注释）；本文提出的表/触发器变更只作为“0002 候选”列在文末。

## 2. 数据目录布局

### 2.1 中转（Ubuntu）
根目录 `WF_RELAY_DATA_DIR`，默认 `/var/lib/workfleet-relay`（属主 `workfleet:workfleet`，权限 0700）：
```text
/var/lib/workfleet-relay/
├── relay.db  relay.db-wal  relay.db-shm
├── relay.lock
├── attachments/{tenantId}/{yyyy}/{mm}/{attachmentId}     # 0600；resources.json storage 约定
├── backups/                                              # 本机临时快照（应再同步到异地，§6）
│   └── relay-20261017T030000Z.db.zst
├── tmp/                                                  # 上传分片、渲染中间物；启动时清空
└── run/metrics.port …                                   # 运行期小文件
/etc/workfleet-relay/
├── relay.env          # 启动级配置（DEC-014）：端口 5101、数据目录、域名、日志级别
└── master.key         # 0400，32 字节随机，Base64；或改用环境变量（§3.1）
日志：stdout → journald（systemd），不落数据目录
```

### 2.2 本机节点（三平台，DEC-041）
| OS | 根目录（`WF_NODE_DATA_DIR` 可覆盖） | 依据 |
|---|---|---|
| Windows | `%LOCALAPPDATA%\WorkFleet\` | 用户级、非漫游（推断：避免域漫游同步大文件） |
| macOS | `~/Library/Application Support/WorkFleet/` | Apple 约定 |
| Linux | `${XDG_DATA_HOME:-~/.local/share}/workfleet/` | XDG |
```text
<root>/
├── node.db  node.db-wal  node.db-shm
├── node.lock
├── transcripts/{relayLinkId}/{conversationId}/{generation}.jsonl   # §5
├── secrets.bundle          # 钥匙串条目的加密镜像（§3.3），用于恢复
├── secrets.fallback        # 仅在无 OS 钥匙串时存在（§3.2 回退）
├── worktrees/{agentAlias}-{ulid}/   # G10 自动 worktree 默认位置（由 DESIGN-003/workspace-guard 最终决定，此处只占位）
├── exports/                # twin 导出、诊断包；24 h 后清理
├── logs/node-YYYYMMDD.log  # pino 文件，按日轮转，保留 14 天
├── run/pids.json           # 子进程 PID/PGID 登记，崩溃后孤儿回收（DESIGN-015 §4.3）
└── tmp/
```
- Windows 长路径（>260）：所有路径操作使用 `\\?\` 前缀或依赖 Node 的长路径支持并在 doctor 中检查 `LongPathsEnabled`（REQ-NF-006，待实测）。
- 目录权限：POSIX 0700；Windows 仅当前用户 ACL（默认 `%LOCALAPPDATA%` 已满足，推断）。

## 3. 加密与密钥

### 3.1 中转主密钥（RMK）
- 来源优先级：`WF_RELAY_MASTER_KEY`（Base64 32 字节）> `/etc/workfleet-relay/master.key`。两者都没有 → 首次启动生成并写入文件（0400），启动日志提示“请离线备份 master.key”。**库内永不存主密钥**（architecture §7）。
- 子密钥派生：`HKDF-SHA256(RMK, salt="workfleet-relay-v1", info=purpose)`，purpose ∈ `channel_credential`、`channel_token`、`totp`、`vapid`。
- 字段加密：AES-256-GCM，12 字节随机 nonce，AAD = `"{table}:{column}:{rowId}"`（防密文挪用到别行）。存储格式（BLOB）：
  ```text
  0x01 | keyVersion(1B) | nonce(12B) | ciphertext | tag(16B)
  ```
- 加密字段（0001）：`channels.credential_enc`、`channel_tokens.token_enc`（微信 context_token，DEC-004）、`users.totp_secret_enc`；VAPID 私钥存 `kv`？——中转 0001 无 kv 表，v1 将 VAPID 密钥对存 `/etc/workfleet-relay/vapid.json`（0400，私钥用 `vapid` 子密钥加密）（差异 #1）。
- 轮换：新 RMK 以 `keyVersion+1` 启用；后台任务逐行重加密（每批 500 行），完成前两版本都可解密；旧密钥配置项 `WF_RELAY_MASTER_KEY_PREV`。
- 哈希（非加密）字段：`web_sessions.id_hash`、`devices.token_hash`/`prev_token_hash`、`invitations.token_hash` 用 SHA-256（ADR-006）；`users.password_hash` 用 argon2id（DESIGN-019 §3）。

### 3.2 节点钥匙串抽象
```ts
// apps/node/src/core/security/secret-store.ts
export type SecretRef = `wf:${'relay-token'|'model-key'|'channel'|'nmk'}:${string}`; // ≤128 字符，契约 keyRef/token_ref
export interface SecretStore {
  readonly backend: 'dpapi_credman' | 'macos_keychain' | 'libsecret' | 'encrypted_file';
  get(ref: SecretRef): Promise<string | null>;
  set(ref: SecretRef, value: string): Promise<void>;   // 覆盖写
  delete(ref: SecretRef): Promise<void>;
  list(prefix: string): Promise<SecretRef[]>;
}
export function openSecretStore(): Promise<SecretStore>; // 按平台探测，失败则回退
```
| 平台 | 后端 | 服务名 / 账户 | 说明 |
|---|---|---|---|
| Windows | 凭据管理器（Generic Credential，DPAPI 保护） | target=`WorkFleet/{ref}` | DEC-020/041；单条凭据大小上限约 2.5 KB（证据不足，待实测，超限则分片或改存 bundle） |
| macOS | Keychain（generic password） | service=`WorkFleet`，account=`{ref}` | DEC-041 |
| Linux | libsecret（Secret Service D-Bus） | schema `dev.workfleet.Secret`，属性 `ref` | 无桌面会话/无 D-Bus 时不可用 |
| 任意（回退） | `secrets.fallback`：AES-256-GCM 加密 JSON | 文件密钥见下 | DEC-041“无则加密文件” |
- 原生绑定库选择（候选 `@napi-rs/keyring` 等）及其许可、三平台预编译：**证据不足**，在实现 TASK 中核实并写入 THIRD_PARTY_NOTICES（ADR-010 同规则）。`keytar` 已归档（部分确认），不选。
- 回退文件密钥：
  - 交互式启动：用户设置口令，`scrypt(N=2^17, r=8, p=1, 32B)` 派生；
  - 无人值守（开机自启、无口令）：随机 32 字节写 `<root>/secrets.fallback.key`（0600）。此模式仅等同“文件权限保护”，`doctor` 输出 **WARN: 弱保护**，本机控制台持续横幅提示。
- 写入流程（模型 Key 示例，详见 DESIGN-022 §3）：`POST /local/v1/model-profiles` → 校验 → `secretStore.set('wf:model-key:{mdlId}', apiKey)` → 回读校验 → 更新 `secrets.bundle` → 入库 `key_ref` → 响应只回 `keyRef`。任一步失败回滚（删除已写条目）。

### 3.3 节点主密钥（NMK）与恢复
- NMK：32 字节随机，首次启动生成，存钥匙串 `wf:nmk:default`。
- 用途：加密 `secrets.bundle`（所有钥匙串条目 `{ref: value}` 的镜像，AES-256-GCM，AAD=`"secrets.bundle:v1"`）。每次 `set/delete` 后原子重写（写 tmp → fsync → rename）。
- **node.db 与转录默认不做应用层加密**，依赖 OS 磁盘加密（BitLocker/FileVault/LUKS），doctor 检测并提示（推断，见差异 #2；理由：WAL 下整库加密需 SQLCipher 类扩展，三平台预编译与许可证据不足）。
- 恢复密钥（REQ-F-035、DEC-020）：
  - 导出 `POST /local/v1/recovery-key/export`：需本机系统认证确认（Windows Hello/凭据 UI、macOS LocalAuthentication、Linux polkit——各平台调用方式**待实测**；不可用时退化为“重新输入本机控制台口令 + 30 秒倒计时确认”）。
  - 格式：`WFRK1-` + Crockford Base32(NMK 32B ‖ CRC32 4B)，每 5 字符一组用 `-` 分隔（共 ~58 字符）；只显示一次，不落盘、不写日志。
  - 导入 `POST /local/v1/recovery-key/import`：新机器先把旧数据目录（或备份包，§6.2）放到位 → 输入恢复密钥 → 校验 CRC → 解 `secrets.bundle` → 逐条写入新机钥匙串 → 生成新 NMK 并重加密 bundle（旧恢复密钥作废，提示重新导出）。
  - 中转连接令牌恢复后**仍需轮换**：节点首次连接成功后调用设备令牌轮换（`POST /api/v1/devices/{id}/rotate-token` 由用户在控制台触发或节点提示），防止旧机残留令牌被滥用（推断）。

## 4. 附件存储（resources.json，已确认契约）
| 项 | 约定 |
|---|---|
| 上传 | `POST /api/v1/attachments`，multipart，≤ 25 MiB，会话或设备令牌；先写 `tmp/`，流式计算 SHA-256，MIME 嗅探（magic bytes）与声明一致且在 `allowedMime` 白名单内才移入正式路径 |
| 路径 | `attachments/{tenantId}/{yyyy}/{mm}/{attachmentId}`（无扩展名，防执行）；库内 `attachments` 只存元数据 |
| 下载 | `GET /api/v1/attachments/{id}` → 302 到 `/files/{id}?exp=&sig=`；`sig = base64url(HMAC-SHA256(k_files, id ‖ exp))`，`exp` = now+300 s；`k_files` 由 RMK HKDF(purpose=`files`) 派生 |
| 响应头 | `Content-Disposition: attachment`、`X-Content-Type-Options: nosniff`、`Content-Security-Policy: sandbox` |
| ACL | 同 tenant 且对所属 conversation 有 `conversation.read`（resources.json） |
| IM 入站附件 | 中转下载到本地再生成 attachmentId，不向节点暴露渠道原始 URL（resources.json `imFetch`） |
| 去重 | 同 tenant 同 sha256 可复用物理文件（推断，v1 不做，避免引用计数复杂度） |

## 5. 转录 JSONL（节点）
- 一个 `(conversationId, generation)` 一个文件：`transcripts/{relayLinkId}/{conversationId}/{generation}.jsonl`；`sessions.transcript_path` 存相对路径。
- 行格式（UTF-8，`\n` 结尾，单行 ≤ 1 MiB，超出则 `text` 截断并 `truncated:true`）：
```json
{"v":1,"lineNo":12,"ts":"2026-10-17T10:00:00.000Z","role":"agent","kind":"message","messageId":"msg_…","text":"…","traceId":"trc_…"}
```
| 字段 | 取值 |
|---|---|
| role | `user`（入站 prompt）、`agent`（聚合后消息）、`thought`、`tool`（工具调用摘要：title/kind/status）、`system`（/clear、cancel、崩溃恢复、load 回放标记） |
| kind | `message`、`tool_call`、`permission`、`stop`（含 stopReason）、`meta`（nativeSessionId 变化等） |
| raw | 可选：原始 ACP `session/update` 的 JSON（默认关闭；`kv_settings.transcripts.raw=true` 开启，用于调试/录制夹具） |
- 写入：每会话一个追加句柄，按行 `write`，每 1 s 或轮次结束 `fsync`（推断）；同一事务写 `transcript_index`（DESIGN-012 §2.2）。
- 崩溃一致性：启动时检查文件末行是否完整 JSON，不完整则截断到最后一个 `\n`，并以 `transcript_index` 最大 `line_no` 为准对齐。
- Windows：始终写 `\n`（不写 CRLF）；读取兼容 `\r\n`（REQ-NF-006）。
- 隐私：转录只在节点（architecture §7）；中转只存会话 id 与消息账本。

## 6. 备份与恢复

### 6.1 中转
| 项 | 设计 |
|---|---|
| 方式 | 在线备份：better-sqlite3 `db.backup(path)`（SQLite Online Backup API，WAL 下不阻塞写者，已确认 SQLite 语义）→ `zstd -10` 压缩 |
| 频率 | 每日 03:00（主机时区，systemd timer 或进程内调度）+ 每次迁移前 |
| 保留 | 本机 `backups/` 7 个日备份 + 4 个周备份（周日）；**异地**同步由运维脚本（`scripts/maintenance/relay-backup.sh`）推到对象存储/另一主机（推断，部署文档给示例） |
| 附件 | `rsync`/对象存储增量同步 `attachments/` |
| 主密钥 | **单独**离线保存，绝不与 db 备份放在同一位置（否则加密等于无效） |
| 恢复演练 | TASK：从备份恢复到空主机，`/api/v1/health` 通过、渠道凭据可解密、节点重连续传无重复外发（REQ-NF-003） |

### 6.2 节点
- `workfleet-node backup --out <file>`（CLI，推断；本机控制台同功能）：打包 `node.db`（Online Backup）+ `transcripts/` + `secrets.bundle` → `.wfbak`（zip + zstd）。**不含 NMK**，恢复需恢复密钥（§3.3）。
- 换机流程：旧机导出恢复密钥 + 备份包 → 新机安装 → `restore` → 输入恢复密钥 → 中转连接重连（hello 带 `lastAckedRelaySeq` 续传，DESIGN-016）→ 建议轮换设备令牌。

## 7. 保留期与清理任务
清理在两侧各由 `system` 模块的 `Janitor` 每日执行（中转 04:00、节点 04:30 或空闲时，主机/用户时区），每批 `DELETE … LIMIT 1000`（SQLite 需 `SQLITE_ENABLE_UPDATE_DELETE_LIMIT`，不保证可用 → 用 `WHERE rowid IN (SELECT rowid … LIMIT 1000)`），批间 `setImmediate` 让出事件循环。

### 7.1 中转
| 数据 | 保留 | 动作 | 依据 |
|---|---|---|---|
| `node_outbox`（已 ack） | 24 h | 删除 | 续传只需未 ack 部分 |
| `node_outbox`（未 ack） | 不删；> 7 天产生 p1 告警 | — | 至少一次 |
| `node_inbox_dedupe` | 7 天 | 删除 | 幂等窗口（DESIGN-016 §5） |
| `idempotency_keys` | 24 h | 删除 | HTTP 幂等 |
| `web_sessions`（过期/吊销） | 30 天 | 删除 | 审计已记录登录 |
| `pairing_codes`（过期/已用） | 1 天 | 删除 | — |
| `invitations`（过期） | 30 天 | 删除 | — |
| `attachments` | 组织配置 7–365 天，默认 90 天；会话删除 → 软删 7 天后物理删 | 软删 → 删文件 → 删行 | resources.json |
| `deliveries`（sent/suppressed） | 90 天 | 删除（审计 `delivery.sent` 已记录去向） | REQ-F-028 由 audit 承载 |
| `deliveries`（dead） | 30 天（控制台可重放窗口） | 删除 | DESIGN-018 §3 |
| `messages` | 默认永久；组织可配 ≥30 天 | 会话软删 7 天后物理删消息（含 FTS 删除，需 0002 触发器） | DESIGN-012 差异 #1 |
| `audit_log` | **永久**（0001 触发器禁止 DELETE） | 不清理 | 见差异 #3 |
| 本机备份 | 7 日 + 4 周 | 删除 | §6.1 |
清理后：`PRAGMA wal_checkpoint(TRUNCATE)`；每月第一个周日在维护窗口执行 `VACUUM`（0001 未设 `auto_vacuum`，库文件不会自动收缩；VACUUM 需约 2 倍磁盘空间，执行前检查剩余空间 ≥ 库大小×1.2，否则跳过并 p2 告警）。

### 7.2 节点
| 数据 | 保留 | 依据 |
|---|---|---|
| `relay_outbox`（已 ack） | 24 h | — |
| `relay_inbox_dedupe` | 7 天 | — |
| `prompt_queue`（finished/cancelled） | 30 天 | 排障 |
| 转录 JSONL + index | 默认永久（用户可在本机控制台按会话删除，或设“N 天后删除”） | 两端记录（REQ-F-019） |
| `twin_events`（deleted_at 非空） | 软删 30 天后物理删（用户“立即彻底删除”则即时） | REQ-F-029、DESIGN-021 |
| `model_usage` | 400 天（覆盖年度对账，推断） | DESIGN-022 |
| `meeting_events`、`supervisor_verdicts` | 永久（本机，量小） | DESIGN-020 |
| `exports/`、`tmp/` | 24 h / 启动清空 | — |
| `logs/` | 14 天 | — |

## 8. 容量估算（推断，待实测）
| 项 | 估算 |
|---|---|
| 中转单条消息（body JSON + plain_text + FTS） | ≈ 3–6 KiB |
| 两人共用，日均 500 条 | ≈ 1 GiB/年 |
| 公司 200 人，日均 2 万条 | ≈ 40 GiB/年 → 触及 ADR-003 “单库 > 20 GB”迁移条件，需按组织配置消息保留期或规划 PostgreSQL（BL-010） |

## 9. 与契约的差异 / 待办
1. 中转 0001 无通用 kv 表存 VAPID 密钥等系统级密文 → v1 用 `/etc/workfleet-relay/vapid.json`；可在 0002 增 `system_kv(key, value_enc, updated_at)`。
2. node.db/转录不做应用层加密（依赖磁盘加密）——与 DEC-020“主密钥存 OS 钥匙串”不冲突，但“恢复节点的加密数据”（REQ-F-035）在本设计中指 `secrets.bundle`；需用户确认此口径。
3. `audit_log` 禁止 DELETE，组织删除/合规清理无法执行 → 需要 ADR：按 tenant 归档导出后由迁移级管理命令清理（临时禁用触发器），或接受永久保留。
4. relay `attachments` 表无 `expires_at`/保留期列，组织级保留期配置（7–365 天）无存放位置（tenants 表无此列）→ 0002 增 `tenants.attachment_retention_days`。
5. node `sessions` 表无 `pid` 列，进程孤儿回收需另存（DESIGN-015 §4.3 用 `run/pids.json`）。
6. resources.json 未规定附件签名 URL 的 HMAC 密钥来源 → 本文约定 RMK HKDF(`files`)。
