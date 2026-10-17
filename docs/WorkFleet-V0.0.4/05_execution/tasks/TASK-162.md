# TASK-162：provider 薄客户端：OpenAI 兼容 + Anthropic（流式、工具、usage）

```yaml
id: TASK-162
slice: S8
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-Node
tier: sonnect
size: 中
title: "provider 薄客户端：OpenAI 兼容 + Anthropic（流式、工具、usage）"
dependsOn: ["161"]
blocks: ["163"]
reqs: "REQ-F-026"
allowedPaths: ["apps/node/src/modules/models/infrastructure/providers/**"]
```

> 冻结字段（id/slice/owner/tier/size/title/dependsOn/blocks/reqs/allowedPaths）照抄 `05_execution/tasks.v1.json`，执行者不得修改；如需变更走规划变更。模板 `05_execution/task-template.md`。

## 1. 归属
- 所属切片：S8
- 来源需求：REQ-F-026
- 来源方案：ADR-013（自写薄客户端：OpenAI 兼容 + Anthropic Messages；chat + 工具 + 流式 + usage）

## 2. 目标
提供统一 `ModelProvider` 接口的两个实现（OpenAI 兼容 Chat Completions、Anthropic Messages），支持流式、工具调用、usage 回传、超时/重试，并提供录制/回放用的 `ReplayProvider`，使上层在 CI 中无网络可测。

## 3. 输入
- 文档：
  - docs/WorkFleet-V0.0.4/03_solution/decisions/ADR-013-总控的模型调用.md
  - docs/WorkFleet-V0.0.4/02_requirements/product-requirements.md（REQ-F-026）
  - docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md（DEC-044：费用按返回 usage × 单价）
- 契约：
  - packages/contracts/schemas/entities/model-profile.schema.json（provider 枚举 `openai_compatible`/`anthropic`、baseUrl、model、params.temperature/maxTokens/timeoutSec/retries）
  - packages/contracts/errors/error-codes.json：`MODEL_PROVIDER_ERROR`（502，retryable）
  - （无线协议契约：提供方 HTTP API 属外部依赖，以其官方文档为准；实现前在 EVD 记录所读文档 URL 与读取日期）
- 前置任务：TASK-161
- 前置状态：TASK-161 已合并（KeyStore 可按 keyRef 取 Key、recordUsage 可用）。

## 4. 输出
- apps/node/src/modules/models/infrastructure/providers/port.ts（`ModelProvider`：`chat({messages, tools?, stream?}) → AsyncIterable<Delta> & {usage}`）
- apps/node/src/modules/models/infrastructure/providers/openai-compatible/
- apps/node/src/modules/models/infrastructure/providers/anthropic/
- apps/node/src/modules/models/infrastructure/providers/replay/（ReplayProvider + 录制器 `WF_MODEL_RECORD=1`）
- apps/node/src/modules/models/infrastructure/providers/__tests__/ 与 `__fixtures__/`（本地 HTTP 假服务回放 SSE）
- 证据：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/`（见 §8）

## 5. Execution Steps
1. [ ] 阅读两家官方 API 文档（Chat Completions 流式/工具/usage；Anthropic Messages 流式事件、tool_use、usage），在 EVD 记录 URL 与读取日期；不确定的字段（如 OpenAI 兼容服务是否支持流式 usage）标“证据不足”。
2. [ ] 定义 `ModelProvider` 端口与统一消息/工具/usage 类型（与提供方无关），usage 缺失时为 `null` 并带 `estimated:false`。
3. [ ] 实现 openai-compatible：基于 Node 22 内置 fetch，SSE 解析，tool_calls 增量拼接，超时（AbortController，params.timeoutSec）与指数退避重试（params.retries，仅 429/5xx/网络错误）。
4. [ ] 实现 anthropic：Messages API 流式事件解析（文本增量、tool_use 输入 JSON 增量、message_delta usage），同样的超时/重试策略。
5. [ ] 错误映射：提供方 4xx（除 429）→ 不重试的 `MODEL_PROVIDER_ERROR`；鉴权失败信息中不得回显 Key。
6. [ ] 实现 ReplayProvider：按请求指纹（provider+model+messages 哈希）从 JSONL 读取录制响应；`WF_MODEL_RECORD=1` 时代理真实调用并录制（录制文件写入前去除鉴权头）。
7. [ ] 写测试：本地 HTTP 假服务回放两家流式样本（文本、工具调用、usage、429 后成功、超时）；ReplayProvider 命中/未命中（未命中时报清晰错误）。
8. [ ] 可选手动冒烟：用户提供的真实 Key 各调用一次，结果（不含 Key）存 EVD；无 Key 时写“未实测”。

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] 两家实现对录制的流式样本产出相同的统一 Delta 序列与 usage（自动化）。
- [ ] 工具调用：分片到达的工具参数 JSON 被正确拼接并解析（两家各 1 个用例）。
- [ ] 429 → 重试成功；超时 → `MODEL_PROVIDER_ERROR`；401 错误消息不含 Key（测试断言）。
- [ ] ReplayProvider 在断网环境下使全部测试通过；录制文件不含 Authorization / x-api-key 头。
- [ ] `make guard` 通过：providers 只被 models 模块内部与其 index.ts 导出使用。

## 7. 验证命令
```bash
mkdir -p docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/
pnpm --filter ./apps/node exec vitest run src/modules/models/infrastructure/providers --reporter=verbose | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/vitest.txt
pnpm --filter ./apps/node exec tsc --noEmit -p . | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/tsc.txt
make guard | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/guard.txt
( grep -rniE "authorization|x-api-key" apps/node/src/modules/models/infrastructure/providers/__fixtures__ && echo LEAK || echo NO_LEAK ) | tee docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/fixture-scan.txt
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/
- `vitest.txt`、`tsc.txt`、`guard.txt`、`fixture-scan.txt`
- `api-docs-read.md`（读取的官方文档 URL、日期、证据标签）
- `manual-smoke.md`（真实提供方冒烟；无则写“未实测”）

## 9. 允许修改
- `apps/node/src/modules/models/infrastructure/providers/**`
- `docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/**`（证据目录，ownership-matrix §4 对每个任务开放）

## 10. 禁止修改
- packages/contracts/**（契约冻结；发现缺陷只在 EVD 与完成记录中报告，改契约 = 新任务 + ADR + opus/fable 券）
- database/migrations/**（v1 只有 0001，冻结）
- Makefile、.github/**、.dependency-cruiser.cjs、eslint.config.js（Agent-Guard 所有）
- docs/**（本任务证据目录 `06_validation/evidence/EVD-162/` 除外，见 ownership-matrix §4）
- apps/node/src/modules/models/ 下除 infrastructure/providers 外文件（TASK-161）
- 引入 LangChain 等大型 SDK（ADR-013 选 A 自写）

## 11. 依赖与阻塞
- Depends on：TASK-161
- Blocks：TASK-163
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：
  - 目标提供方的流式/工具协议与官方文档不一致且无法用统一端口表达 → blocked，交 opus 仲裁端口设计。

## 12. 建议执行档位
sonnect　理由：ADR-013 已定方案，按官方文档实现 HTTP 客户端与解析器，有录制夹具兜底。

## 13. 升级条件
- 需要改变 `ModelProvider` 端口语义影响 163/164/181 → opus。
- 通用熔断（cost-budget §4）：同一任务连续 2 次验收失败 → 停止改代码 → 重写任务书 / 升级档位 / 标 blocked，禁止第 3 次硬撞。

## 14. 预估规模
中　是否小于 2 小时：否

## 15. 风险与假设
- 证据不足：各“OpenAI 兼容”服务对流式 usage、工具调用的支持程度不一，需逐个实测。
- 假设：Node 22 内置 fetch 满足 SSE 流式读取（推断）。

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 实际执行档位：
- 证据清单：`docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-162/`
- 发现的契约/规划缺陷（只报告不改）：
- 验证者结论：（PASS / FAIL / UNKNOWN；记录于 `docs/WorkFleet-V0.0.4/06_validation/acceptance/VAL-162.md`）
