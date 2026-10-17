# 03 参考项目深度分析：WechatClawbot（微信 ClawBot 拓展版）

> 证据基线：GitHub 仓库主页实时抓取（2026-10-17）｜ 用户指定参考项目 #1
> 附：同生态最接近项目 WeClaw（fastclaw-ai/weclaw）对照分析

---

## 1. 项目档案

| 项 | 值 | 证据 |
|---|----|----|
| 仓库 | https://github.com/CodingHeader/WechatClawbot | 【已确认】 |
| 定位 | "微信ClawBot拓展版"——多用户微信 ClawBot 模块 | 【已确认】README |
| 规模 | 0 star / 0 fork / 0 watcher；约 10 次提交；最后提交 2026-09-04 | 【已确认】 |
| 语言构成 | Python 96.8% / JavaScript 3% / Dockerfile 0.2% | 【已确认】 |
| 发布 | 无 Release、无外部贡献者（个人项目） | 【已确认】 |

**规模判断**：这是一个**个人级、早期、无人验证**的项目，但其设计恰好是用户痛点的最小实现（扫码绑定持久化 + 定时通知 + 会话摘要）。价值在于**机制参考**而非生产复用。

## 2. 技术架构穿透

### 2.1 核心链路（README 自述执行逻辑）
```
微信扫码 → iLink 平台长轮询收消息 → AI 问答（litellm/Coze）→ 回发微信
                                  └→ 业务系统经 HTTP API 主动通知 → 微信
```

- **协议层**：对接微信官方 **iLink HTTP API（ilinkai.weixin.qq.com）**——即官方 ClawBot 插件背后的通道【已确认】。这意味着：合规（官方通道）、但能力受 iLink 接口约束（媒体类型、频率）【待确认具体配额】。
- **扫码绑定**：QR 码自动刷新；同一微信用户重复扫码会**自动顶替旧 bot**（解决"绑完这个绑那个"的账号震荡问题——用户痛点的直接解法）【已确认】。
- **后端**：Python 3.10+ / FastAPI / SQLite。
- **AI 层**：litellm 多模型网关；**Coze 作为可插拔后端**（`COZE_API_URL` + `COZE_AUTH_TOKEN`，注意是 AUTH_TOKEN 而非 Coze PAT）——AI 应答与通道彻底解耦【已确认】。

### 2.2 会话与上下文管理
- 每（微信用户 × bot）隔离会话；
- **滑动窗口 20 轮 + 溢出自动摘要**：超出窗口的历史压缩为摘要续接——这是 IM 场景对 LLM 上下文限制的标准工程解法，值得直接复用【已确认】；
- 指令：`/help`、`/clear`（新开对话，对应需求 E2 的单端实现）、`/status`【已确认】。

### 2.3 定时通知（对应需求 E1 的雏形）
- `NOTIFY_JOBS`：**cron 语法定时任务**，到点调用业务接口或模板生成通知推送到微信【已确认】。
- 局限：cron 语义不含"工作日/休息日/节假日"感知——需求 E1 需自行补足（报告 11 的节假日表设计）。

### 2.4 对外 HTTP API（管理面雏形）
- `/accounts`（绑定管理）、`/notify`（主动推送）、`/sessions`（会话查询）；
- Bearer Token 鉴权【已确认】——对应需求 F2 后台配置管理的最小形态。

### 2.5 MCP 服务（亮点）
- 仓库内含 `mcp-npm/`：一个 **npm 分发的 MCP server**，让 Claude/Cursor 等 MCP 客户端可以反过来控制本模块（扫码登录、查状态、发通知、看会话）【已确认】。
- 战略含义：**输入端 agent 可通过 MCP 把"微信通知"当工具用**——这是"agent → 输出端"方向的另一条可行通路（与 ACP 客户端方向互补）。

### 2.6 工程质量
- Docker 化部署；pytest + respx（HTTP mock）单元测试【已确认】。

## 3. 15 维度全方位评估

| 维度 | 评分(5) | 评述 |
|-----|--------|------|
| 需求契合 | 3.5 | 命中 F7(微信)、E1 雏形、E2(/clear)、E3(sessions API)、F6；缺 F1/F4/F5 路由 |
| 前端 | 1 | 无 UI，纯 API/CLI |
| 后端 | 3.5 | FastAPI + SQLite，结构清晰但单人维护 |
| 数据 | 2.5 | SQLite 单文件；无向量/图存储 |
| 交互 | 3 | /help /clear /status + 扫码即用 |
| 逻辑 | 3.5 | 长轮询 + 会话滑窗摘要 + 顶替绑定，机制正确 |
| 组件 | 3 | AI 层/通道层/MCP 层解耦良好 |
| 复用 | 4 | 代码小而直白，Python 生态易吸收 |
| 拓展 | 3 | AI 后端可插拔；但输出通道硬编码微信 |
| 性能 | 2.5 | 长轮询 + SQLite，个人规模够用，无并发设计 |
| 配置 | 3 | env + NOTIFY_JOBS，缺热加载 |
| 知识库 | 1 | 无 |
| 响应 | 3 | 同步问答；无流式 |
| 存储 | 2.5 | SQLite（凭证、会话、任务） |
| 资源 | 4 | 轻量，容器即起 |

## 4. 对照项目：WeClaw（fastclaw-ai/weclaw）——本生态最接近需求的实现

| 项 | WeClaw 值 | 证据 |
|---|----------|------|
| 定位 | "Connect to any agents with WeChat ClawBot"——微信 ↔ 任意 AI Agent 桥 | 【已确认】README |
| 规模 | 1.7k★；Go 语言单二进制；最近提交 2026-10（活跃） | 【已确认】 |
| Agent 接入 | **三模式**：ACP（常驻子进程，JSON-RPC over stdio，复用进程与会话，最快）/ CLI（每条消息起新进程，支持 `--resume`）/ HTTP（OpenAI 兼容接口）；**ACP 优先于 CLI 自动选择** | 【已确认】README 原文表格 |
| 自动发现 | 首启自动探测本机已装 agent（Claude、Codex、Gemini 等） | 【已确认】 |
| 路由命令 | `/codex` `/cc` `/claude` `/cwd` `/new` `/info`；别名 `/cc claude`、`/cx codex`、`/cs cursor`、`/km kimi`、`/gm gemini`、`/ocd opencode`、`/oc openclaw`；自定义别名；默认 agent 持久化 | 【已确认】 |
| 会话 | `/new` 清会话；session 过期告警（近期修复"session expiry warnings"） | 【已确认】 |
| 媒体 | 图片/视频/文件/语音（微信 STT）；markdown→纯文本；markdown 图片自动上传微信 CDN（AES-128-ECB 加密上传） | 【已确认】 |
| 主动推送 | CLI + HTTP API（默认 `127.0.0.1:18011`，`WECLAW_API_ADDR` 可配） | 【已确认】 |
| 多账号 | `weclaw login` 增绑多个微信 | 【已确认】 |
| 部署 | Go install / Docker（ACP/CLI agent 需挂载二进制）/ launchd/systemd 常驻；`weclaw update` 自更新 | 【已确认】 |
| 安全 | 提供 `--dangerously-skip-permissions` 类旁路开关（README 明示警告）；ACP 模式下 agent 自行处理权限 | 【已确认】 |

**WeClaw 对用户需求的意义**：它就是"管理模式（多输入端 → 微信 1 输出端）"的现成实现，且是 **ACP 客户端架构的活教材**。缺口同样明显：只有微信一个输出端（无飞书/QQ/钉钉/Telegram）；无通知模式扇出；无团队模式分组；无定时任务、知识库、身份 loop、总控；无 Web 管理台。

## 5. 苏格拉底追问与钢人论证

**Q：WechatClawbot 0 star，凭什么值得分析？**
价值不在社区背书，而在机制原创性：官方 iLink 通道的工程细节（扫码顶替、长轮询、CDN/媒体）与"AI 后端解耦 + MCP 反控"的组合，是中文微信生态里少见的完整公开实现。反方：无人验证 → 可能有未修 bug；已用 README + 提交记录交叉核对机制描述，未逐行读源码——标注【部分确认：机制存在，代码质量未审】。

**Q：WeClaw 能否直接当 WorkFleet 的 Phase 1？**
支持：Go 单二进制、ACP 三模、主动推送 API、多微信账号、活跃维护。反对：license 未在抓取内容中确认【待确认——落地前必查】；输出端单一且其微信实现与官方插件耦合；无多通道路由抽象，二次开发等于换心脏。裁决：作为 Phase 1 的**微信侧通道实现参考/直接部署对象**可行，作为长期核心需评估其许可与架构弹性。

## 6. 需要补充的功能点与参考方案

| 缺口 | 参考项目 | 补充方案 |
|-----|---------|---------|
| 多输出端（飞书/QQ/钉钉/Telegram/Discord） | OpenClaw 通道体系 / LangBot / AstrBot | 抽象 Channel Adapter；飞书可直接用 `@openclaw/feishu` 契约 |
| 通知/团队模式路由 | LangBot（多平台消息管道） | 路由规则引擎（报告 11 §5） |
| 定时任务的工作日/休息日/每月语义 | Paperclip Routines（cron/webhook/API 触发 + 追赶策略） | 节假日表 + 触发语义扩展 |
| 知识库/记忆 | Hindsight | retain/recall/reflect 三操作接入 |
| 身份 loop | Hindsight 知识页自动重写 + agenmod/immortal-skill | 报告 12 §6 |
| Web 管理台 | Paperclip / Omnara dashboard | 报告 11 §7 |
| 审批转发（ACP request_permission → IM） | 无现成中文实现（Omnara 有英文形态） | WorkFleet 原生实现 |

## 7. 结论

- WechatClawbot：**机制样本**（扫码持久化/顶替、滑窗摘要、cron 通知、MCP 反控、Coze 解耦），可直接借鉴设计与部分代码（注意其未声明 license，复用前确认【待确认】）。
- WeClaw：**Phase 1 首选拼装件** + ACP 客户端参考实现；WorkFleet 的微信通道适配可直接对齐其 iLink 工程细节。
- 两者共同证明：**"微信官方 ClawBot 通道 + ACP 客户端多路复用"在 2026-10 已是可运行的成熟组合**，用户需求的技术地基存在。
