# 06 参考项目深度分析：Orca（并行 Agent 舰队开发环境 ADE）

> 证据基线：GitHub 仓库主页实时抓取（2026-10-17，最新提交即当日）｜ 用户指定参考项目 #4

---

## 1. 项目档案

| 项 | 值 | 证据 |
|---|----|----|
| 仓库 | https://github.com/stablyai/orca | 【已确认】 |
| 定位 | "Orca is the ADE (Agent Development Environment) for working with a fleet of parallel agents. Run any coding agent with your own subscription. Available on desktop, mobile and remote runtime." | 【已确认】README |
| 规模 | **94.5k★ / 600 贡献者 / 14,721 commits / 976 releases**（v1.4.227，2026-10-16 发布）；当日仍在提交 | 【已确认】 |
| 许可 | MIT | 【已确认】 |
| 形态 | Electron + React + Vite（TypeScript 95.1%）+ shadcn 组件体系；pnpm monorepo；Swift 少量（macOS 集成）；oxlint/oxfmt（Rust 工具链）；`orca.yaml` 配置 | 【已确认】 |
| 出品方 | Stably AI（YC 孵化） | 【已确认】 |

## 2. 技术架构与执行逻辑穿透

### 2.1 核心能力矩阵【已确认 README + 提交记录】

1. **并行 worktree 舰队**：每个 agent 独占一个 git worktree（隔离代码状态）；"**fan one prompt across five agents**"——一条提示词扇出给 5 个 agent 并行执行（用户场景 3"主项目+子项目统一开发"的输入端形态）。
2. **移动伴侣（iOS App Store / Android APK）**：手机上监控并"steer"agent；**agent 完成时推送通知**；手机上发后续指令（follow-up）；"Resume in New CLI from a phone chat tab"——手机聊天标签页里恢复/新开会话（2026-10 提交）。桌面-手机经 cloud relay（`cloud/` 目录，中继架构）配对。
3. **终端分屏**：Ghostty 级 WebGL 终端多路并行。
4. **Design Mode**：Chromium 窗口内点击元素 → HTML/CSS/截图自动进 agent 提示词（可视化反馈闭环）。
5. **集成**：GitHub、Linear、Jira（agent 可读票）、GitLab MR review。
6. **SSH worktrees**：agent 跑在远程机器（多设备/服务器算力）。
7. **账号切换器 + 用量追踪**：Claude/Codex 用量、限额重置时间、**账号热切换**（多订阅复用）。
8. **Orca CLI**：`orca worktree create / snapshot / click / fill`——**让 agent 驱动 Orca 本身**（agent 的工具化 IDE）。
9. **通知与未读状态**：聚合所有 agent 的注意力管理。
10. **Computer Use**：桌面操作能力。

### 2.2 ACP 相关工程【已确认，来自提交记录】
- 提交："feat(acp): a managed runtime installs only when asked, with progress"——**ACP 托管运行时按需安装**；
- `orcad`（Orca 守护进程）承担会话/运行时管理；
- 支持的 agent 名单极广：Claude Code、Codex、Grok、Cursor、GitHub Copilot、Muse、DeepSeek Harness、ZCode、OpenCode、MiMo Code、Amp、OpenClaude、Antigravity、Pi、oh-my-pi、Hermes Agent、Devin、Goose、Auggie 等，**外加任意 CLI agent**。

### 2.3 架构推断（标注【部分确认】）
Electron 主进程管理 agent 子进程池（ACP/CLI），React 渲染终端/差异视图，`orcad` 守护进程 + cloud relay 实现移动端远程。子进程管理细节（重连、会话持久化位置）未见公开文档，标注【证据不足：需读源码验证】。

## 3. 15 维度全方位评估

| 维度 | 评分(5) | 评述 |
|-----|--------|------|
| 需求契合 | 3.5 | 命中 I1/I2(会话管理/resume)、I6(注意力/通知)、I8(多账号多设备)、F3 管理模式的"输入侧"；无 IM 通道（其移动端是自有 App 而非微信/飞书） |
| 前端 | 5 | Electron+React+shadcn，桌面+移动双端 |
| 后端 | 4.5 | orcad 守护 + relay；细节闭源度低但文档薄 |
| 数据 | 4 | worktree 快照、会话、用量 |
| 交互 | 5 | 终端分屏/Design Mode/手机 steer——业界最强 agent UX 之一 |
| 逻辑 | 4.5 | ACP 托管运行时 + 按需安装 |
| 组件 | 4.5 | pnpm monorepo 工程化 |
| 复用 | 3.5 | MIT；但它是 IDE 形态，拆出"通知/会话管理"模块需理解其内核 |
| 拓展 | 5 | 任意 CLI agent + 插件式 runtime |
| 性能 | 4.5 | WebGL 终端、并行 worktree |
| 配置 | 4 | orca.yaml |
| 知识库 | 2 | 无记忆系统（依赖 agent 自身） |
| 响应 | 4.5 | 流式终端 + 通知 |
| 存储 | 3.5 | 本地优先 |
| 资源 | 3 | Electron 重量级，桌面常态驻 |

## 4. 与用户需求的三点关键映射

1. **"多对一管理"的输入侧完整答案**：6 工具并发 → Orca 统一呈现/通知/steer，正是用户场景 1（三项目六工具）的现上半成品——**只差把"Orca 自有 App"换成"微信/飞书"**。
2. **移动伴侣的替代性启示**：Orca 证明了"agent 完成→推送→手机跟进→恢复会话"闭环的产品价值；AideanFleet 等于把这个闭环搬进用户已有 IM（符合"输出代表扫码后接收信息的通信工具"定义）。
3. **worktree 隔离 + prompt 扇出**：团队模式中"一个需求多 agent 并行"的工程基础（与 pentagi 的会议式分工互补：Orca 是并行执行面，pentagi 是决策编排面）。

## 5. 苏格拉底追问与钢人论证

**Q：直接用 Orca 手机 App 当输出端，不就不需要 AideanFleet 了？**
支持：免费、体验好、通知/审批/恢复全有。
反对（幸存）：① 输出端被锁定为 Orca 自有 App——用户明确要求**微信/飞书/QQ/钉钉**等既有通信工具（账号通用、无需装新 App、家人同事可达）；② Orca 无 1:N 通知模式（订阅群发）、无 M:N 按产品线分组；③ 无知识库/身份 loop/总控。
裁决：Orca 与 AideanFelt **并行不悖**：Orca 是"输入端工作台"，AideanFleet 是"通道路由层"。Orca 的 CLI/通知模型值得对齐，甚至可作为 AideanFleet 的一个特殊"输入端"（IDE 型 agent 宿主）【设计裁决】。

**Q：94.5k★ 的 Electron 应用有多少可复用？**
UI 工程可参考；但 AideanFleet 核心是服务端路由（无窗口），Electron 层复用价值低。真正可借的是：ACP 运行时按需安装策略、orcad 守护进程模式、relay 配对协议思路、账号热切换 UI 模式【部分确认，需读源码】。

## 6. 需要补充的功能点与参考方案

| 缺口 | 参考项目 | 补充方案 |
|-----|---------|---------|
| IM 输出通道 | WeClaw / OpenClaw feishu 插件 / LangBot | AideanFleet 通道层 |
| 1:N / M:N 路由 | LangBot 管道 | 路由规则引擎 |
| 知识库/记忆 | Hindsight | 记忆服务 |
| 总控编排 | pentagi / Paperclip | 报告 12 |
| 微信/飞书卡片审批 | Omnara（移动审批形态） | 审批按钮组件 |

## 7. 结论

Orca 证明了"**多 agent 舰队 + 移动监控/转向/恢复**"的产品形态与工程可行性（94.5k★、当日仍活跃）。它解决的是输入端工作台问题；AideanFleet 要解决的是**输出通道路由问题**——两者互补。可移植资产：ACP 运行时管理策略、通知聚合、账号热切换、worktree 扇出。定位：**形态验证参照 + 输入侧长期共存伙伴**。
