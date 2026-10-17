# 05 参考项目深度分析：pentagi（多智能体自主渗透测试平台）

> 证据基线：GitHub 仓库主页实时抓取（2026-10-17，含完整 README/DB schema/提交记录）｜ 用户指定参考项目 #3

---

## 1. 项目档案

| 项 | 值 | 证据 |
|---|----|----|
| 仓库 | https://github.com/vxcontrol/pentagi | 【已确认】 |
| 定位 | 开源自托管**多智能体系统**，面向自主渗透测试："用自然语言描述目标与意图，一队专业化 AI agent 规划、在隔离 Docker 沙箱内跑 20+ 专业工具、记忆所学、交付报告" | 【已确认】README |
| 规模 | 30.8k★ / 4.7k forks；活跃（2026 仍有持续提交与讨论） | 【已确认】 |
| 自我定位彩蛋 | 官方 issue 承认：这是"恰好内置了渗透测试提示词的**通用自主 agent 框架**" | 【已确认】issue #297 方向性讨论（快照） |

**对本研究的关键性**：正因为它是"通用多智能体编排 + 记忆 + 报告"框架，其对**总控模式（E6-E9）**的参考价值远超其安全领域外壳。

## 2. 技术架构穿透

### 2.1 总体栈
- **执行面**：隔离 Docker 沙箱（支持 host network 模式）；20+ Kali 系工具（nmap、Metasploit、sqlmap…）。
- **模型面**：10+ 云 LLM 供应商 / 自有 OpenAI 兼容网关 / 本地 Ollama / vLLM（含 GLM 系列中文接入文档，Zhipu 渠道）【已确认】。
- **记忆面（双引擎）**：
  - 主记忆：**PostgreSQL + pgvector**——结果与成功方法持久化，供后续流程复用；
  - 知识图谱：**Neo4j + Graphiti**（时序知识图谱）——异步从 agent 交互中抽取结构化知识（实体/关系/证据/时序上下文），vxcontrol 定制 fork 增加渗透专用实体与边类型；向 agent 暴露 `graphiti_search` 工具；**与 pgvector 互补而非替代**【已确认】README 原文。
- **观测面**：Langfuse（LLM 可观测，ClickHouse + MinIO + Redis 组件）。
- **接口面**：REST + GraphQL 双 API；自动生成。

### 2.2 多智能体编排（总控模式的第一手参考）
**Agent 角色**【已确认】：
- **Orchestrator（编排者）**：接收用户目标，产生任务流；
- **Adviser（顾问）**：planning 模式下充当 planner；
- **Researcher / Developer / Executor**：子任务执行的三类专家（SubTask.agent_type 枚举即此三者）；
- **Enricher（上下文充实器）**：分析完整执行上下文供 planner 使用；
- **Assistant（助手）**：面向用户交互。

**两阶段流**：primary flow（用户目标 → 分解）+ secondary flow（Orchestrator 调度子 agent 执行、聚合、防卡死——"防止 agent 在单一方法上死磕"）【已确认】。

**智能任务规划（Intelligent Task Planning，Beta）**——这是**总控模式"职业经理人"行为的最接近开源实现**：
1. Planner（planning 模式的 Adviser）在专家开工前生成 **3-7 个具体可执行步骤**；
2. Enricher 分析全量执行上下文形成知情计划；
3. 原始请求包裹进 **`<task_assignment>` 结构**（执行计划 + 指令）下达；
4. **范围管理**：防止 scope creep，agent 只聚焦当前子任务；
5. 计划强调关键动作、潜在陷阱、验证点；
6. 开关：`AGENT_PLANNING_STEP_ENABLED`（默认关）。
**官方实测代价**：执行时间与 token 用量 **2-3 倍**，换来结果质量 **2 倍**（Qwen3.5-27B-FP8 测试）【已确认】。
适用：<32B 参数模型、复杂工作流。

### 2.3 数据模型（README DB schema 节选）
```
Task(id, name, goal, status, ...)
SubTask(id→Task, name, description, status[queued/running/completed/failed],
        agent_type[researcher/developer/executor], context JSON)
Action(id→SubTask, type[command/search/analyze/...], status, parameters, result)
Artifact(id→Action, type[file/report/log], path, metadata)
Memory(id→Action, type[observation/conclusion], embedding vector, content)
```
→ **五级链路 Task→SubTask→Action→Artifact→Memory** 是总控模式任务数据模型的现成模板：任务/子任务带执行 agent 类型与 JSON 上下文、动作级留痕、产物归档、观察记忆向量化。

### 2.4 安全与部署
- installer 需 root 或 docker 组（明示 docker.sock 风险与 rootless 建议）；一机一实例（compose 固定容器/网络名）；默认管理员首登改密；worker 节点隔离。

## 3. 15 维度全方位评估

| 维度 | 评分(5) | 评述 |
|-----|--------|------|
| 需求契合 | 2.5 | 命中 E6/E7/E8 总控编排内核、I12 预算/观测；无任何 IM 通道与多对多路由 |
| 前端 | 4 | 自带 Web UI（任务流/终端观测） |
| 后端 | 5 | 微服务 + worker 隔离，工程强度高 |
| 数据 | 5 | 五级任务链 + 双记忆引擎，教科书级 |
| 交互 | 3 | Web + API；无 IM 入口 |
| 逻辑 | 5 | 两阶段流 + planner + 防卡死 + agent 终端输出观测 |
| 组件 | 4.5 | Langfuse/Graphiti/PG 向量等全部可拆卸组合 |
| 复用 | 3 | 安全域假设深（沙箱、Kali 工具链），抽出编排内核需手术 |
| 拓展 | 4 | 供应商无关（OpenAI 兼容网关）、agent 类型可扩 |
| 性能 | 4 | 沙箱并行 + 异步图谱；规划步 2-3x 开销是特性不是缺陷 |
| 配置 | 4.5 | 环境变量细粒度（AGENT_PLANNING_STEP_ENABLED 等） |
| 知识库 | 4.5 | pgvector + Graphiti 双引擎 = 显性知识 + 时序关系网 |
| 响应 | 3.5 | 流式日志/终端观测；IM 流式需另建 |
| 存储 | 5 | PG(向量)+Neo4j(图)+MinIO(对象) 全谱系 |
| 资源 | 2.5 | 全栈重（多数据库 + 沙箱），个人设备负担大 |

## 4. 苏格拉底追问与钢人论证

**Q：安全域项目对"微信聊天路由"有什么可移植性？**
反方：工具链、沙箱、攻击路径全是领域包袱，直接复用会拖死轻量部署。
正方（幸存）：**编排内核与数据模型是领域无关的**——Orchestrator/Adviser 双角色 = 总控的"经理/顾问"；`<task_assignment>` 结构 = 总控的任务下达格式；防卡死循环 = 会议机制安全阀；五级数据链 = 任务审计模型。这些都以设计模式形态移植，不搬代码。
裁决：**机制移植，代码不移植**（且需查其许可证对借鉴的约束【待确认：本次抓取未含 license 字段】）。

**Q：pgvector + Graphiti 双引擎是否过度设计？**
对渗透域合理（主机/服务/漏洞天然图结构）。对 WorkFleet：MVP 用 Hindsight（一站式记忆）即可；团队模式做"项目-任务-agent"关系推理时再评估加图库。避免一步到位的过度工程【设计裁决】。

**Q：2-3x token 开销换 2x 质量，用户能接受吗？**
这正是总控模式的成本结构。对策（结合 Paperclip）：预算硬停 + 小模型走规划步（pentagi 明示 planner 对 <32B 模型收益最大）+ 可开关（默认只在复杂任务启用会议）。把成本决策权交给配置【设计建议】。

## 5. 需要补充的功能点与参考方案

| 缺口 | 参考项目 | 补充方案 |
|-----|---------|---------|
| IM 输入/输出通道 | WeClaw / LangBot | WorkFleet 通道层 |
| 轻量部署（个人设备） | WeClaw（单二进制） | 编排内核独立成库，沙箱/图库全部可选依赖 |
| 中文 IM 媒体管道 | WeClaw | 通道适配器 |
| 定时任务 | Paperclip Routines | 心跳队列轻量版 |
| 记忆系统现代化 | Hindsight（retain/recall/reflect） | 替换 pgvector 裸用 |

## 6. 结论

pentagi 提供**总控模式的编排参考实现**：角色分工（Orchestrator/Adviser/专家）、两阶段流、`<task_assignment>` 下达结构、防卡死、五级任务数据链、双记忆引擎。代价结构（2-3x token）已量化。定位：**总控模式设计蓝本（报告 12 的主要依据之一）**，不作为底座（域包袱 + 部署重量 + 许可待确认）。
