# @workfleet/contracts — 契约唯一源（ADR-002）

> 本目录是中转、本机节点、Web 三方唯一共享的语言。改动只能由 Agent-Contract 在专门任务中进行（见 docs/WorkFleet-V0.0.4/04_planning/ownership-matrix.md），并需 ADR。

| 契约 | 文件 | 说明 |
|---|---|---|
| ① API | `api/relay.openapi.json`、`api/node-local.openapi.json` | OpenAPI 3.1，只编目端点；请求/响应 schema 引用 `schemas/` |
| ② Errors | `errors/error-codes.json`、`schemas/common/error.schema.json` | 错误码、HTTP 映射、可重试、前端展示 |
| ③ Identity | `identity/permissions.json`、`identity/*.schema.json` | 角色、动作、权限矩阵、禁止路径、会话与设备令牌声明 |
| ④ Resources | `resources/resources.json` | 附件上传/下载/签名 URL/生命周期/ACL |
| ⑤ Events | `protocol/envelope.schema.json`、`protocol/frames/*.schema.json`、`events/domain-events.json` | 中转↔节点帧与进程内领域事件 |
| ⑥ UX States | `ux/ux-states.json` | 每个核心界面的 empty/loading/error/no_permission/success/offline |
| 实体 | `schemas/entities/*.schema.json` | 跨端数据结构 |
| 适配器 | `adapters/*.json` | 输入适配器 spec、渠道能力、v1 清单 |
| 指令 | `commands/im-commands.json` | IM 与 Web 指令集 |

规则：JSON Schema 2020-12；`$id` 前缀 `https://workfleet.dev/contracts/v1/`；ID/时间/金额格式见 `schemas/common/` 与 ADR-012。TASK-002 实现：`pnpm contracts:gen` 生成 `generated/` 下 TS 类型与 ajv 校验器；`pnpm contracts:test` 校验全部 schema 合法、$ref 可解析、示例通过、生成物无漂移。

本地校验（规划阶段已执行）：52 个 schema 全部通过 Draft 2020-12 元校验，$ref 全部可解析，envelope 正/反例校验符合预期。
