---
id: WF-TASK-TEMPLATE
type: template
title: 原子任务卡模板（16 项必填）
status: active
version: V0.0.4
source: 用户规划指令 §6.2；项目完整文档体系 §19
---

# TASK-XXX：<任务名称>

```yaml
id: TASK-XXX
slice: S-N
status: todo            # todo | ready | in_progress | in_review | blocked | done | cancelled
owner: Agent-<Role>
tier: opus              # haiku | sonnect | opus | fable（默认 opus）
size: 中                # 小(<0.5d) | 中(≈1d) | 大(≈2d)；<2h 不单独成卡
```

## 1. 归属
- 所属切片：S-N
- 来源需求：REQ-F-xxx / REQ-NF-xxx / REQ-C-xxx
- 来源方案：ADR-xxx / DESIGN-xxx / DEC-xxx

## 2. 目标
<一句话，可验证>

## 3. 输入
- 文档：<路径>
- 契约：<packages/contracts 中的具体文件与 schema/端点/帧名>
- 前置任务：<TASK-xxx>
- 前置状态：<如“迁移 0001 已合并”>

## 4. 输出
- 新增/修改的文件路径（精确到目录或文件）

## 5. Execution Steps
1. [ ] ...

## 6. 验收标准（≤6 条，可自动化优先）
- [ ] ...

## 7. 验证命令
```bash
<可直接复制执行>
```

## 8. 证据路径
docs/WorkFleet-V0.0.4/06_validation/evidence/EVD-XXX/

## 9. 允许修改
- <path pattern>

## 10. 禁止修改
- packages/contracts/**
- database/migrations/**
- <其他>

## 11. 依赖与阻塞
- Depends on：
- Blocks：
- 阻塞条件（遇到即停，标 blocked 并写明原因、缺失信息、已尝试方案、需谁决策）：

## 12. 建议执行档位
<档位>　理由：<一句话>

## 13. 升级条件
<什么情况下升级到上一档>

## 14. 预估规模
<小/中/大>　<是否小于 2 小时：否>

## 15. 风险与假设
- 假设（NON_BLOCKING，来自未知登记册 U-xx）：

## 16. 完成记录（执行者填写，独立验证者判定 PASS/FAIL/UNKNOWN）
- 提交：
- 验证者结论：
