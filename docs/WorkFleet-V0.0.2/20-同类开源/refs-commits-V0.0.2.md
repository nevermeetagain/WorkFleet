# 20-同类开源 · refs-commits-V0.0.2（本轮快照与版本刷新）

> 执行：2026-10-17 09:49 CST（= 01:49 UTC），综合架构师。方法：`git ls-remote https://github.com/<repo> HEAD`（全部成功）+ GitHub REST API（`/repos`、`/releases`、`/compare/<V0.0.1 SHA>...<本轮 SHA>`、`/contents`）+ PyPI JSON。**只刷新 SHA/版本/许可证/活跃度，不重做深度分析**（按任务要求）；深度分析正文仍基于 V0.0.1 SHA，凡本轮发现的实质变化在对应文件头部以【V0.0.2更新】标注。
> 证据等级（`01-需求分解与分析规划/03 §4.1`）：ls-remote/API/compare = E2–E3（元数据/提交标题级），未读本轮新增代码 diff → 涉及代码行为的结论维持 V0.0.1 的 E4（旧 SHA）。

## 1. 同类开源入围项目

| 项目 | V0.0.1 SHA（2026-10-16） | **V0.0.2 HEAD（2026-10-17 01:49 UTC）** | 新增提交 | 最新发布 | Stars（API） | 许可证（API / LICENSE 文件） | 实质变化 | 标签 |
|---|---|---|---|---|---|---|---|---|
| chenhg5/cc-connect | `7da94a4` | `2dec7173bdd44ec598c3c7e5c7ff00407acfdedf`（2026-10-16 16:57 CST，Merge #1917） | 9（7 文件） | v1.5.1-beta.3（2026-09-29，预发布） | 15,972 | API `null`；根目录 `/contents` 仍**无 LICENSE 文件** | 仅 codex 历史读取修复、idle 重置计数修复；**许可证缺陷未修复**；路由/广播/微信模型无变化 | 已确认（元数据+提交标题） |
| openclaw/openclaw | `3dc6e49` | `acd27635ccdc31f7970907524531f101c2d48fd1` | **894**（compare 仅返回最后 250 条） | v2026.10.4（正式）/ v2026.10.10-beta.1 | 392,202 | MIT | 最后 250 条以 cron/runtime 性能与 ACP 读取测试为主；钉钉、订阅广播是否新增 **未全量核查**（`证据不足`） | 部分确认 |
| iOfficeAI/AionUi | `c140550` | `c140550d04e44f3d6f8a9830b40ae56e4689a977` | 0 | — | 33,583 | Apache-2.0 | 无变化 | 已确认 |
| iOfficeAI/AionCore | `503a871` | `503a87199eb978790ca77675b39c84b241535bf3` | 0 | — | 122 | Apache-2.0 | 无变化 | 已确认 |
| AstrBotDevs/AstrBot | `9441402` | `de898afe7588e1f153beec06e24f03f6ddeae2e4` | 3 | v4.29.0（2026-10-14） | 42,016 | AGPL-3.0 | Discord @everyone 修复、dashboard 移动端、会话隔离先于管线注册；无 ACP 输入 | 已确认（提交标题） |
| openclaw/acpx | `3df6a48` | `0d874f9a98de2a82ed8c5a4746053bd0a46052c3` | 2 | **v0.19.6**（2026-10-17 00:39 CST） | 3,352 | MIT | 仅发布流程；版本号提升到 0.19.6（V0.0.1 未记录版本；Paperclip 依赖 0.13.1） | 已确认 |

## 2. 协议与适配器

| 对象 | V0.0.1 记录 | **V0.0.2 刷新** | 实质变化 | 标签 |
|---|---|---|---|---|
| ACP 规范 agentclientprotocol/agent-client-protocol | `9bec5b0`；CHANGELOG v1.11.0（2026-10-09）、schema v2.0.0-alpha.8 | HEAD `e7dac67ac64ec7cf69079b3bb6eff46a21e026b3`（+10 提交）；**发布 v1.12.0 + schema-v1.26.0 + schema-v2.0.0-alpha.9（2026-10-16 18:03 CST）** | v1.12.0 新增：unstable client system prompt schema、v2 `_meta` 顶层 upsert；修复：移除 unstable next-edit-suggestions；大量 v2 澄清（取消语义、replay ID、foreground work）。**v1 稳定方法集未见破坏性变更**；v2 仍 alpha | 已确认（release note 原文） |
| claude-agent-acp | `872e93f`，0.91.0 | HEAD `dbf386d8d35d2bc30f17f11f15d1a4305c9d391f`；**v0.93.0（2026-10-17 03:19 CST）**，中间 v0.92.0（2026-10-16 20:39 CST） | ① 升级 ACP SDK 至 1.9.0 并采纳 v2 澄清（#1366）；② 适配器重启后恢复已 resume 的子代理（#1364）；③ 新增 `/remote-control` 命令（#1197，Claude 自有远程控制，非 IM）；④ fork 会话在 `session/fork` 响应前不进列表（#1368）。**一天两个小版本，版本漂移风险坐实** | 已确认（release note） |
| codex-acp | Registry 2.2.2（本地克隆 0.16.0 不一致） | HEAD `59974c7d173e4fd6ef9498fc1e91779606c2404d`；最新发布 **v2.2.2（2026-10-10）** | 与 Registry 一致；V0.0.1 的本地 0.16.0 为旧仓快照，**冲突以 v2.2.2 为准**（已由发布页证实） | 已确认 |
| python-sdk（PyPI `agent-client-protocol`） | 0.12.1 稳定、1.0.0rc3 预发布（V0.0.2 `01` E12 搜索摘录） | GitHub HEAD `bdb9ac7054fb2df76a922b60b356c3c65f8a8a64`；PyPI：**0.12.1（2026-08-16）为最新稳定**；1.0.0rc1/rc2/rc3（2026-09-11 / 09-21 / 10-12） | 由 E1（搜索摘录）升级为 E3（PyPI JSON 原文）。注意：TS 侧适配器已用 ACP SDK 1.9.0，**Python 稳定版仍 0.12.x，1.0 尚在 rc** → R-070 风险维持 | 已确认 |
| ZCode 官方仓 zai-org/ZCode | v3.15.1（2026-10-10，来自 V0.0.1 `30/02 §5`） | HEAD `aac4755666d09fdcd70272fcf063c077a639015f`（2026-10-10 18:59 CST，“feat: update to v3.15.1”）；`package.json` version 3.15.1；tag v3.15.1；**GitHub Release 对象最新为 v3.14.3（2026-09-24）**；**LICENSE = Apache-2.0**（文件原文）；7,891★ | **身份核实**：官方仓确为 `zai-org/ZCode`（A-21 由“部分确认”升为“已确认（仓库身份）”）；README 全文 grep `acp`/`app-server` **无命中** → “官方不提供 ACP”的结论维持（部分确认：仅 README 层面，未读 `packages/rpc`/`apps/zcode-cli` 源码）；目录含 `packages/rpc`、`apps/zcode-cli`、`packages/zcode-server-cli`，可作为后续 PoC-11 的源码入口 | 已确认（仓库/许可）/ 部分确认（无 ACP） |

## 3. 参考项目（10-参考项目 已在各自报告中刷新，此处仅索引）

| 项目 | V0.0.2 SHA | 来源 |
|---|---|---|
| WechatClawbot | `4ec3bbe8`（无新提交） | `10-参考项目/11 §0` |
| Paperclip | `0528cc7e`（+27） | `10-参考项目/12` |
| PentAGI | `843dfeb`（无新提交） | `10-参考项目/13` |
| Orca | `fd1c6a5`（+330） | `10-参考项目/14` |
| Hindsight | `5331da2`（+52，v1.0.0） | `10-参考项目/15` |
| BettaFish | `b67928f`（首次分析） | `10-参考项目/16` |
| 用户仓 AideanFleet | `a9a24ed`（无新提交，v0.4.0） | `01-需求分解与分析规划/01 §0.1 E1` |

## 4. 复现命令

```bash
for r in chenhg5/cc-connect openclaw/openclaw iOfficeAI/AionUi iOfficeAI/AionCore AstrBotDevs/AstrBot openclaw/acpx \
         agentclientprotocol/agent-client-protocol agentclientprotocol/claude-agent-acp agentclientprotocol/codex-acp \
         agentclientprotocol/python-sdk zai-org/ZCode; do git ls-remote https://github.com/$r HEAD; done
curl -s https://api.github.com/repos/<repo>/releases?per_page=3
curl -s https://api.github.com/repos/<repo>/compare/<V0.0.1-SHA>...<HEAD>
curl -s https://api.github.com/repos/chenhg5/cc-connect/contents/        # 检查 LICENSE 文件
curl -s https://pypi.org/pypi/agent-client-protocol/json
curl -s https://raw.githubusercontent.com/zai-org/ZCode/main/{README.md,LICENSE,package.json}
```

## 5. 对结论的影响（汇总）

1. cc-connect 仍无 LICENSE → G1 许可证闸门继续命中（A′ 回退的前提仍未满足）。`已确认`
2. claude-agent-acp 两天三版、已采纳 ACP SDK 1.9.0/v2 澄清 → 必须**锁精确版本 + 冒烟测试**（R-051 风险维持并升级为“已发生”）。`已确认`
3. Python ACP SDK 稳定版 0.12.1 vs TS 侧 1.9.0 → Python 侧存在**版本代差**，C2′（Node 旁车）的触发概率上调（判断）。`部分确认`
4. ZCode 官方仓身份与 Apache-2.0 许可确认；官方 ACP 仍未见 → R-205 维持 P2/实验。`部分确认`
5. 其余入围项目无影响选型的变化。`已确认`（提交标题级）
