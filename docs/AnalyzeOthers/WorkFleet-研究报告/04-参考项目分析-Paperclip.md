# 04 参考项目深度分析：Paperclip（Agent 公司编排平台）

> 证据基线：GitHub 仓库主页实时抓取（2026-10-17）｜ 用户指定参考项目 #2

---

## 1. 项目档案

| 项 | 值 | 证据 |
|---|----|----|
| 仓库 | https://github.com/paperclipai/paperclip | 【已确认】 |
| 定位 | "The open-source app everyone uses to manage AI agents for work"——用"公司"隐喻管理 agent 团队：组织架构图、预算、治理、目标 | 【已确认】README |
| 规模 | **103.2k★ / 17.3k forks / 472 watching**；最新提交 2026-10-16（前一天）；极高活跃 | 【已确认】 |
| 许可 | MIT | 【已确认】 |
| 形态 | Node.js server + React UI（pnpm monorepo：server/ ui/ tools/agent-shim tests/；TypeScript；Vite；vitest；Node 24 强制） | 【已确认】 |
| 名言 | "If OpenClaw is an employee, Paperclip is the company."；"If it can receive a heartbeat, it's hired." | 【已确认】README |

## 2. 技术架构穿透（服务端系统全图）

README"Server systems"章节自述的九大子系统【已确认】：

1. **Identity & Access**：两种部署模式；run 级 JWT（执行凭证与登录凭证分离）。
2. **Org Chart & Agents**：把 agent 组织成公司（汇报关系、目标挂载）。
3. **Work & Task System**：Issue 承载 company/project/goal/parent 链接；**原子 checkout + 执行锁**（防两个 agent 抢同一任务）；一等公民的阻塞依赖（blocker dependencies）；评论/文档/附件/工作产物/标签/收件箱状态；跨工作检索、文档修订审阅、锚定反馈。
4. **Heartbeat Execution（核心）**：**DB 支撑的唤醒队列**——心跳合并（coalescing）、预算检查、workspace 解析、密钥注入、技能加载、适配器调用一气呵成；每次 run 产生日志、用量记录、适配器会话状态；**有界恢复**（bounded recovery）自动处理可恢复失败、上浮需要人工的场景。
5. **Workspaces & Runtime**：项目仓库/工作区；可选隔离执行工作区（git worktree、operator 分支）；运行时服务（dev server、预览 URL）；沙箱供应商扩展（e2b、Cloudflare、Daytona、Modal、Novita、自托管 K8s）。
6. **Budget & Costs**：按 company/agent/project/goal/issue/provider/model 六维 token 与费用追踪；分级预算策略（告警阈值 + 硬停）。
7. **Routines & Schedules**：**cron / webhook / API 三类触发**；并发与追赶（catch-up）策略；**每次例行执行生成一个被追踪的 issue 并唤醒指派 agent**——定时任务与任务系统统一建模。
8. **Plugins**：实例级插件系统——**进程外 worker、能力门控的宿主服务、作业调度、工具暴露、UI 贡献**（动态 UI 解析器）；"不改 fork 就能扩展 Paperclip"。
9. **Secrets & Storage / Activity & Events / Company Portability**：按 agent 授权的秘密管理；活动日志与行为归因；`companies.sh` 整公司导入导出（组织模板可移植）。

**适配器层**：OpenClaw、Claude Code、Codex、Cursor+Cloud、Gemini CLI、OpenCode、Pi、Hermes+Gateway、Grok Build、Kimi Code 均为受管 agent；外部适配器插件体系（adapter-plugin，2026-04 引入）；实验性 Runner（沙箱执行 + agent-shim + Pi 1.0 集成）。

**治理**：Board 审批流、执行策略（审查/审批阶段）、决策追踪、预算硬停、agent 暂停/恢复/终止；连接应用（GitHub、Notion、Railway、MCP servers）经**工具网关**，每个 action 可配置 Allowed / Ask-first / Off。

**连接器（实验性）**：Slack、Discord、Telegram、AgentMail 的 chat/email 连接器【已确认】——注意：**无微信/飞书/QQ/钉钉中国通道**。

**可观测**：Sentry（opt-in）、OpenTelemetry、Honeycomb CI 性能剖析。

## 3. 15 维度全方位评估

| 维度 | 评分(5) | 评述 |
|-----|--------|------|
| 需求契合 | 3.0 | 命中 E1(定时+cron/webhook/API)、E6/E7/E8(总控的公司化变体)、I10/I11(用量/审计)；F1 多对多路由不是其模型（它是"任务→agent"而非"agent消息→IM"） |
| 前端 | 5 | React 完整管理台（组织图、预算、治理、技能工作室） |
| 后端 | 5 | Node/TS 大型单体服务，九大子系统边界清晰 |
| 数据 | 5 | 任务/工件/用量/事件全关系建模 |
| 交互 | 4.5 | Web 台 + 实验性聊天连接器 |
| 逻辑 | 5 | 心跳驱动 + 原子任务 + 有界恢复，工程完成度极高 |
| 组件 | 5 | 适配器插件 + 实例级插件双扩展 |
| 复用 | 3.5 | MIT 友好；但体量大（103k★ 量级的工程），适合抽机制而非整装 |
| 拓展 | 5 | 插件可贡献 UI/工具/作业，进程外隔离 |
| 性能 | 4 | 唤醒队列合并 + 沙箱并行；Node 运行时上限存在 |
| 配置 | 5 | 组织/预算/策略全在 Web 台 |
| 知识库 | 3.5 | 文档/附件/技能库；无向量记忆（需配 Hindsight） |
| 响应 | 4 | 心跳节律 + run 流式日志 |
| 存储 | 4.5 | DB 支撑队列、秘密库、工件 |
| 资源 | 3 | 全功能部署重量级（Node 24 + 多服务） |

## 4. 执行逻辑金矿（可直接移植到 WorkFleet 的四个机制）

1. **心跳执行 = 总控模式的调度内核**：DB 唤醒队列（合并风暴）、执行前五连检（预算→workspace→密钥→技能→适配器）、run 全程留痕、有界恢复。WorkFleet 的定时任务（E1）与总控分派（E6）可以完整照抄此模型，把"适配器调用"替换为"ACP session/prompt"。
2. **原子 checkout + 执行锁**：团队模式（M:N）下多个输入端并发领任务不冲突的成熟解。
3. **Routines 统一建模**：定时任务不是独立子系统，而是"生成 issue → 唤醒 agent"的普通任务流——**追赶策略（catch-up）** 解决"停机错过 9 点推送怎么办"（用户场景 4 的健壮性需求）。
4. **预算硬停 + Ask-first 工具网关**：总控模式防失控（无限会议循环）的现成答案；连接器 action 三态（Allowed/Ask/Off）映射到 IM 审批按钮。

## 5. 苏格拉底追问与钢人论证

**Q：Paperclip 这么强，为什么不直接用它当 WorkFleet？**
支持直接用：103k★、MIT、定时/治理/编排/多 agent 全都有。
反对（未被排除）：① **通道错配**——其连接器是 Slack/Discord/Telegram/邮件，无微信 ClawBot/飞书/QQ/钉钉，中国输出端为零【已确认缺失】；② **模型错配**——它的核心抽象是"公司/issue/心跳"，用户的核心抽象是"IM 会话 ↔ agent 会话的路由"，前者改造成后者要在其 Identity/Task 系统上做侵入式二开；③ 部署重量（Node 24 全家桶）与"个人设备上跑"的轻量诉求有张力。
裁决：**不作为底座，作为机制蓝本 + 可选的"总控执行后端"**（WorkFleet 的总控若需要重编排，可经其 API 驱动 Paperclip，而 IM 侧由 WorkFleet 自持）【设计建议】。

**Q：103k★ 会不会是营销虚高、实际不可用？**
反证：976 版本节奏、每日提交、Honeycomb/Sentry/OTel 全套工程化、贡献者众多——是真实活跃的超大型项目【已确认多信号】。但"everyone uses"是营销话术，实际采用率与话语术无关，不影响本报告结论。

## 6. 需要补充的功能点与参考方案

| 缺口 | 参考项目 | 补充方案 |
|-----|---------|---------|
| 中国 IM 输出端（微信/飞书/QQ/钉钉） | WeClaw / `@openclaw/feishu` / LangBot | 外挂 Channel Gateway，或用 Paperclip 插件体系自写连接器 |
| IM 会话 ↔ 任务的双向映射 | WeClaw（chat 命令寻址） | WorkFleet 路由层（报告 11 §5） |
| 记忆/知识库 | Hindsight | per-repo bank + 知识页 |
| ACP 原生接入 | WeClaw / acp-bridge | 适配器加 ACP 模式 |
| 微信媒体管道 | WeClaw（CDN AES 上传） | 通道适配器内实现 |

## 7. 结论

Paperclip 是"**总控模式 + 定时任务 + 治理预算**"三个需求的最强机制来源（心跳队列/原子任务/追赶策略/预算硬停全部现成），但**不是多对多 IM 路由工具**。定位：**机制蓝本（必抄设计） + 可选重型后端（阶段 3 再议）**。MIT 许可允许深度借鉴实现【已确认】。
