---
id: WF-GLOSSARY
type: glossary
title: 术语表（一个概念一个名字）
status: active
version: V0.0.4
---

# 术语表

| 术语（中文） | 代码/契约名 | 定义 | 不要叫 |
|---|---|---|---|
| 本机节点 | node / `apps/node` | 运行在用户电脑上的常驻进程，拉起并驱动智能体 | 客户端、agent 端、网关 |
| 云中转 | relay / `apps/relay` | 服务器上的服务，持有 IM 连接、账号、路由、审计、Web 控制台 | 服务端、云网关、hub |
| 组织 | tenant | 数据隔离单位（个人或公司） | 租户空间、workspace |
| 成员 / 角色 | membership / role(admin/operator/viewer) | 用户在组织中的身份 | 权限组 |
| 设备 | device | 一个已配对的本机节点实例 | 机器、主机 |
| 配对码 | pairing code | 8 位一次性码，节点用它换设备令牌 | 绑定码（易与 /bind 混淆） |
| 中转连接 | relay link | 节点到某个中转的连接（可多个） | 通道 |
| 项目 | project | 一级组织对象，可有主/子层级（≤3） | 仓库、空间 |
| 智能体 | agent | 一个输入端实例（ACP 智能体、Coze、Webhook、总控） | 机器人、bot（bot 专指 IM 侧） |
| 别名 | alias | 智能体在组织内唯一的短名（如 z1、cc1） | 昵称 |
| 适配器（输入） | input adapter / InputAdapterSpec | 描述如何启动与对话某类智能体的一行表配置 | 插件 |
| 渠道 | channel | 一个输出端实例（某个微信授权、某个飞书应用） | 输出端（可作为口语）、IM 账号 |
| 渠道能力 | capabilities | 渠道声明的可编辑、卡片、按钮、配额等 | 特性 |
| 接收人 | recipient | 渠道上的一个对话对象（私聊、群、频道） | 用户（易与 user 混淆） |
| 识别我的账号 | /bind | 把 IM 接收人与 WorkFleet 用户关联并授权 | 扫码绑定 |
| 绑定 | route | 来源智能体 × 目标接收人 × 模式 × 过滤 | 路由规则、订阅 |
| 模式 | mode | management 管理 / notification 通知 / team 团队 / supervisor 总控 | — |
| 焦点 | focus | 某接收人当前的默认目标智能体（/use 设置） | 当前会话 |
| 会话 | conversation | 稳定 id + generation + displayId + 原生 session id | 对话（口语可用）、线程 |
| 代 | generation | /clear 后 +1 的会话代数 | 版本 |
| 消息 | message | 账本中的一条（append-only） | 记录 |
| 投递 | delivery | 一条消息发往一个接收人的一次尝试序列（outbox） | 推送 |
| 审批 | approval | 智能体权限请求或总控上报，需人决策 | 确认 |
| 暂存 | held | 目标有待审批时新消息的等待状态 | 挂起 |
| 汇总屏障 | barrier | 等 N 个来源或超时后发一条汇总 | 聚合器 |
| 过滤规则 | filter rule | 接收人 × 业务线 × 字段的过滤与脱敏 | 权限（专指 RBAC） |
| 审计 | audit entry | 不可改写的操作/出站记录 | 日志（专指运行日志） |
| 总控 | supervisor | 本机节点上的“职业经理人”自有智能体 | 经理 Agent、主控 |
| 把关分级 | verdict(reply/merge/escalate/drop) | 总控对每条输出的处理决定 | 过滤 |
| 会议 | meeting | 总控组织的多智能体结构化讨论 | 群聊 |
| 模型配置 | model profile | 用户自管的提供方/模型/Key 引用/参数/上限 | 模型账号 |
| 分身数据 | twin event | 用户指令与时间线记录（只在节点） | 画像、记忆 |
| 写租约 | write lease | 同一目录同一时刻一个写入者 | 文件锁 |
| 急停 | emergency stop | /stop all 冻结全部智能体与出站 | 暂停 |
| 帧 | frame / envelope | 中转↔节点 WSS 上的一条协议消息 | 包、事件（事件专指进程内领域事件） |
| 优先级 | priority p0–p3 | p0 立即、p1 高、p2 普通、p3 摘要 | 级别 |
