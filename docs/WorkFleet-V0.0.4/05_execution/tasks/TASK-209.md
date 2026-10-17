# TASK-209：安装与部署：三平台节点安装/自启、中转 systemd + Caddy 脚本

```yaml
id: TASK-209
slice: S10
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Guard
tier: sonnect
size: 大
title: "安装与部署：三平台节点安装/自启、中转 systemd + Caddy 脚本"
dependsOn: ["014"]
blocks: ["210"]
reqs: "REQ-F-001"
allowedPaths: ["infra/**", "scripts/setup/**", "scripts/release/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S10
- 来源需求：REQ-F-001
- 来源方案：ADR-001（两侧部署）；ADR-003；TR-04/TR-05；REQ-C-003/005；DEC-051（中转公网仅 443）

## 2. 目标
提供三平台本机节点安装与开机自启（单实例）脚本、中转 Ubuntu 部署（systemd 单元 + Caddy 443 TLS 反代到 127.0.0.1:5101 + 防火墙只开 443）脚本与发布打包脚本；脚本在 CI 静态校验通过，并在三平台真机各安装一次留证。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/architecture.md §3（部署单元与端口）
  - docs/WorkFleet-V0.0.4/03_solution/technical-requirements.md（TR-04、TR-05）
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-001、REQ-C-003、REQ-C-005、§8 前置：域名与 TLS）
- 契约：
  - （无 packages/contracts 运行时契约；端口契约来自 architecture §3：5100 本机控制台、5101 中转内部、5102 Webhook、5103 MCP、5104 metrics）
  - packages/contracts/api/relay.openapi.json：`GET /api/v1/health`（部署后健康检查）
  - packages/contracts/api/node-local.openapi.json：`GET /local/v1/status`（安装后自检）
- 前置任务：TASK-014
- 前置状态：TASK-014 CI 守卫已合并；节点与中转可执行入口（TASK-004/007）已存在。

## 4. 输出
- infra/systemd/workfleet-relay.service（专用用户、`Restart=on-failure`、只监听 127.0.0.1:5101、数据目录权限）
- infra/caddy/Caddyfile（443 自动 TLS，反代 `/api/v1/*`、`/api/v1/stream` 与 `/api/v1/node-gateway` 的 WebSocket 升级到 127.0.0.1:5101）
- infra/node-autostart/（macOS LaunchAgent plist、Linux systemd --user 单元、Windows 登录时启动任务定义）
- scripts/setup/install-relay.sh、scripts/setup/install-node.sh（macOS/Linux）、scripts/setup/install-node.ps1（Windows）、对应 uninstall
- scripts/release/（构建节点与中转发布包、校验和）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/`（见 §8）

## 5. Execution Steps
1. [ ] 节点自启方式：按“每用户、登录后启动”设计（钥匙串需用户会话）——macOS LaunchAgent、Linux `systemd --user`、Windows 任务计划“登录时运行”（推断，需实测）；单实例由节点自身锁保证，脚本只负责注册。
2. [ ] 节点分发形态（Node SEA 单文件 / 携带 Node 运行时的压缩包 / 安装器）**证据不足**：先实现“携带 Node 22 运行时 + 应用目录”的压缩包方案（better-sqlite3 预编译按平台选择），把其他方案的评估写入 EVD。
3. [ ] 中转：install-relay.sh 创建 `workfleet` 系统用户、数据目录 0700、主密钥文件 0600、安装 systemd 单元与 Caddyfile、`ufw` 只放行 443（SSH 运维端口另行说明，不与“只开 443”冲突的处理写入 EVD）。
4. [ ] Caddy：WebSocket 透传、`/api/v1/node-gateway` 长连接超时 ≥ 心跳 60 s；仅 HTTPS。
5. [ ] CI 静态校验：`shellcheck`、`systemd-analyze verify`、`caddy validate`、macOS `plutil -lint`、PowerShell `Invoke-ScriptAnalyzer`；Ubuntu 容器内执行 install-relay.sh 冒烟（`/api/v1/health` 200）。
6. [ ] 真机：Windows 11、macOS 14、Ubuntu 24.04 各安装节点一次 → 重启电脑 → 中转控制台显示“在线”（截图）；中转在 Ubuntu 真机/VM 部署一次 → 外部 `nmap` 仅 443（及说明的 SSH）。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 全部脚本静态校验通过（shellcheck/systemd-analyze/caddy validate/plutil/PSScriptAnalyzer 输出 0 错误）。
- [ ] Ubuntu 容器内 install-relay.sh 冒烟后 `curl -k https://localhost/api/v1/health` 返回 200，127.0.0.1:5101 以外无监听。
- [ ] 三平台真机安装 + 重启后节点自动上线（截图 + 中转设备列表“在线”），重复启动第二实例被拒。
- [ ] uninstall 后自启项与服务被移除（脚本自检）。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/
shellcheck scripts/setup/*.sh scripts/release/*.sh | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/shellcheck.txt
systemd-analyze verify infra/systemd/workfleet-relay.service | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/systemd.txt
caddy validate --config infra/caddy/Caddyfile --adapter caddyfile | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/caddy.txt
pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path scripts/setup/install-node.ps1 -Severity Error" | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/psscriptanalyzer.txt
docker run --rm -v "$PWD":/src -w /src ubuntu:24.04 bash scripts/setup/install-relay.sh --smoke-test | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/relay-smoke.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/
- 静态校验输出 5 份（见验证命令）
- `relay-smoke.txt`
- `devices/`（Win11、macOS 14、Ubuntu 24.04 安装与重启后在线截图、系统版本）
- `port-scan.txt`（中转外部 nmap 结果）
- `packaging-options.md`（分发形态评估，证据标签）

## 9. 允许修改
- `infra/**`
- `scripts/setup/**`
- `scripts/release/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-209/` 除外，见 ownership-matrix §4）
- apps/**（可执行入口、单实例锁不在本卡）
- .github/**（CI 接入由 Guard 另行修改 workflow 段；若同为 Guard 本人执行仍需单独提交）

## 11. 依赖与阻塞
- Depends on：TASK-014
- Blocks：TASK-210
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 依赖图中本卡只依赖 TASK-014，但真机安装需要可运行的节点与中转（S0–S9 产物）：真机验收部分在依赖满足前标 blocked，静态校验部分可先交付。
  - Windows 登录自启 + 无管理员权限的可行方案实测失败 → 交 opus/用户裁决（服务化会失去用户钥匙串访问）。
  - macOS 未签名/未公证的可执行文件被 Gatekeeper 阻止：签名证书属外部依赖（证据不足）→ 报用户。

## 12. 建议执行档位
sonnect　理由：标准部署脚本与配置，静态可校验，可逆。

## 13. 升级条件
- 分发形态或自启方式需要做出影响安全模型的取舍（如以系统服务运行节点）→ opus。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
大　是否小于 2 小时：否　三平台 + 中转 + 打包 + 真机，约 2 天。

## 15. 风险与假设
- 证据不足：节点分发形态、macOS 签名/公证要求、Windows 登录任务在无管理员权限下的行为。
- 假设：中转运维 SSH 端口不计入“公网只开 443”（需用户确认，写入 EVD）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-209/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-209.md`）
