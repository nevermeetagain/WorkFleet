---
id: WF-V0.0.3-FACTS
type: baseline
title: WorkFleet V0.0.3 事实基线
status: active
version: V0.0.3
created: 2026-10-17
---

# 01 · 事实基线

## 1. 分析快照
```yaml
date: 2026-10-17 (Asia/Shanghai)
repo: nevermeetagain/WorkFleet
branch: main
commit: df09998d333a40a6adbd385e20c6d268a7402e74
tracked_files: 116（全部位于 docs/，另有 .gitignore）
code: 无（无 README / LICENSE / AGENTS.md / packages / database）
visibility: public
```

## 2. 已确认事实
| # | 事实 | 证据 | 标签 |
|---|---|---|---|
| F-01 | WorkFleet 是独立新仓，与旧内部项目无代码关系 | GitHub API；`git log` | 已确认 |
| F-02 | 仓库公开且无 LICENSE（法律上默认保留所有权利） | GitHub 仓库页 | 已确认 |
| F-03 | 用户指定端口段 5100–5200；仓内 grep 0 命中，旧文档仍写 3100–3200 | `grep -rn 51[0-9][0-9]` | 已确认 |
| F-04 | 需求 150 条（R）全部未实现 | 无代码 | 已确认 |
| F-05 | 六个参考项目 SHA：WechatClawbot `4ec3bbe8`、Paperclip `0528cc7e`、PentAGI `843dfeb`、Orca `fd1c6a5`、Hindsight `5331da2`、BettaFish `b67928f` | `V0.0.2/40-综合/02` 头部 | 已确认 |
| F-06 | 许可：Paperclip/Orca/Hindsight MIT；PentAGI MIT+EULA（文本自相矛盾）；BettaFish GPL-2.0+禁止商用；WechatClawbot 无 LICENSE | `V0.0.2/40-综合/02 §9` | 已确认 |
| F-07 | ACP TypeScript SDK 1.9.0、Python SDK 0.12.1 | `V0.0.2/40-综合/04:15` | 已确认（快照日） |
| F-08 | Cursor 支持 `agent acp` | https://cursor.com/docs/cli/acp | 已确认 |
| F-09 | 飞书长连接仅企业自建应用；卡片回调 3 秒；同用户/同群 5 QPS；卡片 ≤30KB、14 天内可更新 | `V0.0.2/30-协议与端点/03:68-81` | 已确认（上线前复核） |
| F-10 | 微信 ClawBot 每入站约 10 条回复额度；不适合大规模群发 | `V0.0.2/30/03:53`、`40-综合/08` | 部分确认（未真机） |
| F-11 | OpenClaw 钉钉有官方外部插件（DingTalk-Real-AI，MIT）；飞书/微信/QQ 均有官方维护的 OpenClaw 渠道插件 | GitHub；`wsz987/dsh-channels` 致谢 | 已确认（许可逐个待核） |
| F-12 | OpenHarness（HKUDS，MIT）ohmo 渠道为 Telegram/Slack/Discord/飞书；DeepSeek Harness + dsh-channels 覆盖微信/QQ/钉钉/飞书/Telegram，均为“单 Agent 对多 IM” | 各 README | 部分确认（仅 README） |

## 3. 被事实推翻或失效的旧结论
| 旧结论 | 出处 | 处置 |
|---|---|---|
| C2“同仓自建”82 分领先 | `V0.0.2/40-综合/04:10,158` | 失效：领先 15 分来自“复用现有资产”，新仓归零；新仓下 C1/C2 同为 78.8（`04:166`） |
| A-10 同仓、A-45 闭源 | `V0.0.2/40-综合/10:19,31` | 与 F-01、F-02 相反，重开为 Q-02 |
| A-47 Python 主栈 | `10:32` | 理由“与旧内部项目一致”消失，重开为 Q-01（已定 TS，DEC-032） |
| 旧内部项目体检类 PoC-0、G37、G38、K-47~49、R-086 | 原文已移除（DEC-036） | 作废 |
| 总控复用旧内部项目内核（D4） | 原文已移除（DEC-036） | 作废，会议协议本身保留 |
| 端口 3100–3200 映射 | `05:231-245` | 平移到 5100–5200，见 DEC-016 |

## 4. AnalyzeOthers 中已识别的错误（不得采纳）
| 断言 | 出处 | 判定 |
|---|---|---|
| Cursor 无 ACP | `AnalyzeOthers/WorkFleet-研究报告/02:92`、`13:112` | 错误（F-08） |
| Claude Code 走 `@zed-industries/claude-code-acp` | `…/02:84` | 过时，现为 `claude-agent-acp` |
| “ACP 支持 ACP/CLI/HTTP 三种模式” | `Claude-4-6.txt:204` | 混淆：这是 WeClaw 的接入模式 |
| 管理多个 Bot 账号、每个对应一个微信号 | `Claude-4-6.txt:77` | 与“只有一个常用微信”冲突 |
| 扫码失效自动重登录 loop | `Claude-4-6.txt:125` | 不可能（需人工扫码） |
| Paperclip 用 GraphQL | `Claude-4-6.txt:298` | 与代码级证据（Express 5 + Drizzle）不符 |
| Orca 支持 OMP | `Claude-4-6.txt:398` | 无依据 |
| WorkFleet 用 3000/3333 | `…/01:176`、`…/11:146-150` | 错误 |
| 总控默认不全量把关 | `…/12:102,110` | 违背原文“每次输入后都必须经过总控把关” |
| 团队模式入站扇出给组内所有 agent | `…/11:104-107` | 会重复执行，否决 |
| Go + PG + Redis + Neo4j + Docker 重栈 | `Claude-4-6.txt:699-707` | 违背设备端零外部依赖（K-28） |

## 5. 未知项
| # | 未知 | 级别 | 解法 |
|---|---|---|---|
| U-01 | 微信额度是“每入站重置”还是“累加” | BLOCKING（S1 容量） | PoC 真机 |
| U-02 | 主动消息是否需要 context_token | BLOCKING（S1） | PoC 真机 |
| U-03 | 用户设备所在网络（是否需代理访问 Telegram/Discord/海外模型） | BLOCKING（渠道选型） | 问用户 Q-04 |
| U-04 | 用户是否有飞书企业自建应用权限 | BLOCKING（S2） | 问用户 Q-05 |
| U-05 | 各 Agent 订阅并发限流 | NON_BLOCKING | 运行期测量 |
| U-06 | OpenClaw 渠道插件各自许可（腾讯微信插件曾记为 NOASSERTION） | NON_BLOCKING（复用前必须核） | 逐个核 |

## 4. 渠道入口事实（2026-10-17 补充，用于 Q-03 重构）
| 编号 | 事实 | 证据 | 标签 |
|---|---|---|---|
| F-13 | 微信 iLink：同一 `ilink_user_id` 每次扫码生成新 bot 实例，用户消息只路由到最新授权的 bot | WechatClawbot `app.py:131-161`（`_supersede_same_user_accounts` 注释）；`V0.0.2/10-参考项目/01:145` | 部分确认（代码注释，未真机） |
| F-14 | 飞书：一个企业自建应用 = 一个 Bot；同一租户可建多个应用 | `V0.0.2/30-协议与端点/03:79` | 部分确认（推断自应用模型） |
| F-15 | 飞书长连接为集群模式：同一应用多个客户端连接时，每条事件只随机投给其中一个 | `V0.0.2/30-协议与端点/03:72` | 已确认（官方文档） |
| F-16 | OpenClaw 自带飞书/微信等渠道，且提供 `openclaw acp`（ACP over stdio，可 `--url wss://…` 连远端 Gateway） | `V0.0.2/30-协议与端点/02:17,91,94` | 已确认 |
| F-17 | 推论：任何一个 Bot 身份（一个微信授权 / 一个飞书应用）同一时刻只能有一个有效消费者；两个程序抢同一身份，消息会被顶掉或随机分走 | F-13、F-15 | 部分确认（微信侧待真机） |
| F-18 | ZCode 自带 Bot Channel：在“移动端远程控制”弹窗选微信，用手机微信扫码即绑定，之后在微信里直接对话；另有 Remote Control 扫码用手机浏览器控制；代码始终在桌面端运行 | https://www.cnblogs.com/youring2/p/22381155（2026-08-10）；IT之家 2026-08-11 | 部分确认（第三方教程） |
| F-19 | ZCode 无官方 ACP；官方无头协议为 `zcode app-server --stdio`（私有、未文档化）；社区 `zcode-acp-server` 把它桥接为 ACP（Apache-2.0，自述非官方） | `V0.0.2/30-协议与端点/02:18,114-115`；npm.io zcode-acp-server | 已确认（存在性）；ToS 风险待核 |
| U-03 | 飞书机器人能否主动触达租户外用户（场景 4 公司外订阅者） | 非阻塞（v2） | 官方文档核实 |
