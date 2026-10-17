---
id: ADR-011
type: adr
title: 架构守卫与 CI 门禁
status: accepted
version: V0.0.4
created: 2026-10-17
decider: 规划 Agent（opus 档）；用户可推翻
---

# ADR-011：架构守卫与 CI 门禁

## 1. Context
规划指令 §9.4；PROJECT-STRUCTURE-SPEC 第八部分。

## 2. Problem
需要一个可执行、可验证、可逆的选择，供并行开发 CLI 共同遵守。

## 3. Options
A dependency-cruiser + ESLint + Makefile guard + gitleaks + 契约测试；B 仅代码审查

## 4. Decision
选 A。

## 5. Rationale
机器约束比记忆可靠；三平台矩阵（ubuntu/windows/macos）跑单测，E2E 只在 ubuntu。

## 6. Consequences
### Positive
+ 并行 CLI 不会悄悄越界。
### Negative
− CI 时长增加。
### Risks
—

## 7. Status
accepted（2026-10-17）。推翻需新 ADR，并把本文改为 superseded。

## 8. Related
Makefile；.github/workflows/ci.yml（TASK-014）
