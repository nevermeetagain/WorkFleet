# 05 · acpx 深度分析（ACP 输入端驱动组件）

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/openclaw/acpx |
| 分析版本 | `3df6a484c52748a1d3a00b6f606a24cbe4367cb9`（2026-10-16 03:03 CST） |
| 本地路径 | `/workspace/work/refs/acpx` |
| Stars / 语言 / 许可证 | 3,352 / TypeScript（Node ≥ 22.13）/ MIT（`package.json:14`） |
| 定位 | 无头 ACP 客户端（CLI + 库），pre-1.0，接口仍在演进（`README.md` 的 NOTE） |

> 入围原因：需求写明"最好走 ACP"。acpx 是目前最完整的 **ACP 客户端运行时 + Agent 注册表**，可以作为 AideanFleet 输入层的"驱动"。它不是网关，加权分低是正常的。

---

## 1. 5W1H

- **What**：用统一命令 `acpx <agent> …` 驱动任意 ACP Agent，提供持久会话、一次性 exec、权限策略、NDJSON 事件输出和 flows 工作流（`README.md`）。
- **Why**：屏蔽各 Coding CLI 之间的差异，"Agents talking to agents"。
- **Where/When**：本机运行，会话状态位于 `~/.acpx/`（`README.md` 的 Sessions 一节）。
- **Who**：注册表位于 `src/agent-registry.ts:53-131`，包括 pi、openclaw（`openclaw acp`）、codex（`@agentclientprotocol/codex-acp`）、claude（`@agentclientprotocol/claude-agent-acp`）、gemini（`gemini --acp`）、cursor（`cursor-agent acp`）、copilot、antigravity、devin、droid、iflow、junie、kilocode、kimi、kiro、opencode、qoder、qwen、trae、grok-build 等 30 多种。
- **How**：spawn 子进程 → stdio NDJSON JSON-RPC（`src/acp/ndjson-stream.ts`、`jsonrpc.ts`）→ `client.ts`（`loadSession` 在 `:1230`，`resumeSession` 在 `:1275`）→ session 持久化、journal、event-log → 队列 owner 通过 IPC 串行处理同一会话的多个提交者（`src/session/queue/*`）。
- **What if**：如果 AideanFleet 选 TS / Node 技术栈，可以直接 `import "acpx/runtime"`（`package.json:30-37` 的 exports 包含 `./runtime`、`./flows`、`./agent-registry`），省掉自写 ACP 客户端；如果选 Go，可改用 cc-connect 的 `agent/acp`。

## 2. 代码证据

| 模块 | 证据 | 说明 |
|---|---|---|
| Agent 注册表 | `src/agent-registry.ts:64` openclaw；`:65-76` codex；`:77-93` claude；`:95-96` gemini / cursor；`:262` 默认 codex | 带适配器包的版本范围和 npx 回退 |
| 会话恢复 | `src/acp/client.ts:1230` loadSession、`:1275` resumeSession | 对应"按 session/resume ID 查询或恢复" |
| 会话持久化 | `src/session/{persistence,journal,event-log,export,import,conversation-retention}.ts` | 会话可以导出、导入，有保留策略 |
| 并发队列 | `src/session/queue/{ipc-server,lease-store,owner-turn-controller,request-limit}.ts` | 同一会话多个提交者时排队，turn 有归属 |
| 权限 | `src/permissions.ts:28-30` deny-all / approve-reads / approve-all | 可以接入 IM 审批（需自写 permission-prompt 回调） |
| 工作流 | `src/flows/{graph,runtime,decision,store}.ts`、`executors/shell*.ts` | ACP turn + 确定性步骤 + 决策 + checkpoint，可作为"总控"的底层执行器 |
| 进程管理 | `src/process-liveness.ts`、`src/acp/process-descendants.ts` | 能清理子孙进程 |
| 被 OpenClaw 采用 | OpenClaw `extensions/acpx` | 已在生产级项目中使用 |

## 3. 需求匹配

| 需求 | 匹配 | 得分 | 说明 |
|---|---|---|---|
| IN | ● | 14 | 覆盖面最广；Zcode `证据不足`；Coze 不是 ACP |
| OUT | ○ | 0 | |
| M1–M3 | ○ | 0 | 不是路由组件 |
| UI | ○ | 0 | |
| CR | ○ | 0 | 只有 `timer-duration.ts` 用于超时 |
| NS | ● | 4 | `sessions new` / `--name` |
| HI | ● | 4 | 会话历史与导出 |
| KB | ○ | 0 | |
| M4 | ◐ | 2 | flows 可以表达"先会议、再分派"的确定性流程 |
| LP | ○ | 0 | |
| **合计** | | **≈24%（组件定位）** | |

四个场景：都不能单独满足；它只是场景 1、3 的输入驱动层。

## 4. 全维度

| 维度 | 评估 |
|---|---|
| 前端 | 无 |
| 后端 | Node 库 / CLI |
| 数据 | `~/.acpx` 下的会话 JSON、journal、事件日志 |
| 交互 | CLI；`--format json` 输出 NDJSON 事件，便于网关消费 |
| 逻辑 | 会话队列、turn 归属、取消 |
| 组件 | runtime / flows / agent-registry 三个可独立 import 的入口 |
| 复用 | **高**：TS 网关直接依赖它；Go 网关可移植注册表与会话语义 |
| 拓展 | 自定义 Agent：`--agent '<command>'`，注册表可配置 |
| 性能 | 每个 Agent 会话一个子进程；IPC 队列 |
| 配置 | 全局和项目级 JSON，命令行 flag 优先 |
| 知识库 / 响应 / 存储 / 资源 | 无 / 流式事件 / 本地文件 / 取决于 Agent 进程 |
| 安全 | 权限模式、`--cwd` 文件系统边界 |
| 许可证 | MIT |

## 5. 双向钢人

- 支持"用 acpx 做输入层"：覆盖最广，OpenClaw 官方在用，MIT，可以作为库引入。
- 反对：pre-1.0，接口会变；Node ≥ 22.13；如果网关用 Go，则要跨语言调用（启动 CLI 进程并解析 NDJSON，多一层进程）。
- 判断：**TS 栈首选；Go 栈改用 cc-connect `agent/acp` 并参照 acpx 注册表补全 Agent 列表**。

## 6. 最终判断

- 定位为**组件**，不参与"底座"评比。输入层可以直接复用或借鉴。
- 下一步：在 PoC 中对比 acpx runtime 与 cc-connect agent/acp 的会话恢复、权限中继和取消语义。
