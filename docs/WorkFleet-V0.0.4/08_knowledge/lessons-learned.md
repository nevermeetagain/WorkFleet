---
id: WF-LESSONS
type: knowledge
title: 经验教训
status: active
version: V0.0.4
created: 2026-10-17
sources: [docs/WorkFleet-V0.0.3/03_solution/option-comparison.md, docs/WorkFleet-V0.0.3/03_solution/decisions/decision-log.md, docs/WorkFleet-V0.0.3/08_knowledge/fact-baseline.md §3–4, docs/WorkFleet-V0.0.3/08_knowledge/meetings/qa-log.md, docs/WorkFleet-V0.0.3/06_validation/requirement-coverage.md]
---

# 经验教训

> 每条：发生了什么（有出处）→ 根因 → 以后怎么做（落到哪条规则）。只记有文档证据的事。

| ID | 发生了什么 | 根因 | 以后怎么做 | 出处 |
|---|---|---|---|---|
| L-01 | **Q-15 误判**：V0.0.3 初稿把“执行 Agent 分档”列为需提问的待定项，称“fable 含义未知、需用户定义”；实际用户 12:32 的项目规划指令 §8.2/§8.3 已完整定义四档（fable/opus/sonnect/haiku）、默认 opus 与券制，原话“默认档 = opus。不要默认用 sonnect，也不要默认用 fable。” | 没有在提问前回查用户已有指令；把“我不认识这个词”当成“用户没定义” | 提问前先检索用户已给出的全部指令与 QA 记录，确认确实未定义再问；用户既有指令视同已裁定（DEC-050）。路线图中该行已 cancelled | option-comparison Q-15“更正（2026-10-17 17:50）”；DEC-050；QA-22 |
| L-02 | **把问题问错了**：Q-03 原问“微信是否只绑 WorkFleet”，用户回“我感觉你没想明白”，并补充两类画像（本人 = 微信 + 开发 CLI；朋友 = 飞书 + 其他智能体） | 从功能开关角度提问，没先代入用户的真实使用场景 | 先用画像代入场景，再把问题重构为规则（“一个 Bot 身份一个消费者”，DEC-034）；问题要能让用户用场景回答 | QA-06；DEC-034/035 |
| L-03 | **推荐被用户推翻两次**：Q-08 推荐“总控后置到 MVP 之后”，用户选“跟第一版一起做”；Q-12 推荐“先自用、公司场景作演示”，用户答“真会有老板和多部门用” | 规划者以控制工期为先，低估了用户场景的真实性与优先级 | 推荐要基于用户已陈述的场景；对“是否真实使用”类问题不预设为演示；被推翻后同步检查受影响的范围与工期风险（R-03） | QA-14、QA-19；DEC-043/047 |
| L-04 | **旧结论在前提消失后仍被沿用**：V0.0.2 中“C2 同仓自建 82 分领先”的 15 分优势来自“复用现有资产”，新仓下归零（C1/C2 同为 78.8）；A-10 同仓、A-45 闭源、A-47 Python 主栈的理由同样失效 | 评分与结论没有记录其依赖的前提，前提变化时无人复核 | 每个结论写明前提；前提变化时把结论标“失效”并重开问题（V0.0.3 已重开为 Q-01/Q-02）；本版规则：AI 分析不自动升格为设计依据（`document-standard.md §9`） | V0.0.3 fact-baseline §3 |
| L-05 | **外部 AI 分析含多处事实错误**：如“Cursor 无 ACP”（实际支持 `agent acp`）、Claude Code 包名过时、“Paperclip 用 GraphQL”、“团队模式入站扇出给所有 agent”、Go+PG+Redis+Neo4j 重栈等 | 未经代码级或官方来源核实就引用 | `docs/AnalyzeOthers/` 只作待审查输入；采纳前必须有直接证据并标证据标签；防自证循环规则（`current-plan.md §12`） | V0.0.3 fact-baseline §4 |
| L-06 | **决策与路线图互相矛盾而未察觉**：DEC-025 写“ZCode、OpenClaw 后置”，路线图 v1 已列入；G1/G10 标 MUST/SHOULD 却放在 v2；DEC-002/016/022/030 写于单机网关时期，与云中转（DEC-037）冲突 | 决策逐条追加，没有在每次重大变更后做全局一致性核对 | 每次范围变更后做一次“代入核对”（V0.0.3 requirement-coverage 的做法）；V0.0.4 起冲突决策用 ADR 正式取代并在 `09_archive/superseded/` 登记 | requirement-coverage §5；DEC-051/052/053 |
| L-07 | **端口段写错**：用户指定 5100–5200，旧文档仍写 3100–3200，仓内 grep 无一处 5100 段 | 早期文档未以用户原始约束为准 | 用户给定的硬约束进 REQ-C（REQ-C-003）并在守卫/评审中检查；改约束必须全仓 grep | V0.0.3 fact-baseline F-03；DEC-016 |
| L-08 | **“先做一小片”的建议被否决**：18:04 规划者建议 V0.0.4 先切“微信 + Claude Code + ZCode + 网页控制台”一片，用户 18:08 回“不，按照我的设计…建立完整的、详细的文档目录及文件” | 把“交付节奏”的建议放到了“文档规划”层面；用户要的是先有完整设计与文档体系，再按切片执行 | 规划与执行分层：规划阶段按用户给定规范产出完整体系；切片只用于执行排序（`slices.md`、`current-plan.md`） | QA-26.5、QA-27；REQ-INBOX-20261017-003 |
| L-09 | **V0.0.1 的 FTS 设计缺陷**在 V0.0.2 通过 DDL 实测才发现：外部内容（`content='event'`）的 FTS5 表没有同步触发器，插入数据后检索“登录超时”命中数为 0 | 设计只写了 DDL，没做最小插入-检索实测 | 数据结构类设计必须附可执行验证（V0.0.4 已对 0001 迁移做 sqlite3 建库核对，`fact-baseline.md` F-24；检索正确性仍需 TASK-025 用例覆盖）；中文检索用 trigram（DEC-015） | `docs/WorkFleet-V0.0.2/50-附录/DDL实测/v001_fts_defect_output.txt`；DEC-015 |

## 变更记录
| 日期 | 变更 |
|---|---|
| 2026-10-17 | 初版 |
