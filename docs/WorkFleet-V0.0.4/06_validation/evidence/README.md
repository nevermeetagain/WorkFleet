---
id: WF-EVIDENCE-README
type: evidence
title: 证据（EVD）目录规则
status: active
version: V0.0.4
created: 2026-10-17
sources: [docs/项目完整文档体系.txt §26, docs/项目完整目录结构.txt 第六/七节, 04_planning/ownership-matrix.md §4, 04_planning/current-plan.md §11]
---

# 证据（EVD）

## 1. 目标
证据必须**可检查、可定位、与任务相关、可复现、不依赖口头解释**（文档体系 §26）。判断标准：**一周后一个没参与的人，只看这个目录就能复现结论。**

## 2. 目录与编号
- 一个任务一个目录：`EVD-<任务号>/`，编号与任务、验收记录相同（`TASK-041` → `VAL-041` → `EVD-041/`）。
- 只允许该任务的执行者写入自己的 EVD 目录，验证者可追加 `verifier/` 子目录（`ownership-matrix.md §4`：实现任务对 `docs/**` 只有本任务 EVD 目录的写权限）。
- 不移动、不改名已提交的证据；补充用新文件。

## 3. 标准结构
```text
EVD-XXX/
├── README.md              # 必需：复现说明（见 §4）
├── env.txt                # 必需：环境快照
├── commands.md            # 必需：按顺序执行的命令，可直接复制
├── output/                # 必需：命令原始输出
│   ├── 01-make-guard.txt
│   ├── 02-test-unit.txt
│   └── 03-e2e.txt
├── screenshots/           # 有界面或真机操作时必需
│   ├── 01-<步骤短名>.png
│   └── 02-<步骤短名>.png
├── recordings/            # 演示脚本录屏（里程碑 E2E 任务必需），可放外链清单 links.md
├── data/                  # 测量原始数据（CSV / JSONL）与计算脚本（基线指标必需）
└── verifier/              # 独立验证者复现时的输出（可选）
```

## 4. README.md（复现说明）必须包含
1. 对应：TASK、VAL、REQ 编号。
2. 被验提交：commit SHA、分支、PR。
3. 前置条件：需要的账号/设备/服务（真机类写清是谁的设备、哪个平台账号，**不写凭据**）。
4. 复现步骤：编号列表；命令引用 `commands.md` 行号；人工步骤配截图编号。
5. 预期结果：与任务卡验收条目逐条对应。
6. 已知差异：与预期不一致之处及原因。

## 5. env.txt 必须包含
`git rev-parse HEAD`、`git status --porcelain`（应为空或说明）、操作系统与版本、`node -v`、`pnpm -v`、关键依赖版本（锁文件哈希）、中转与节点所在地区（跨境测量时）、执行时间（CST）。

## 6. 命令输出
- 原样保存标准输出与标准错误（`cmd > output/NN-name.txt 2>&1`），**不删减、不手改**；过长时可截断，但必须保留首尾与退出码，并注明截断位置。
- 每个输出文件末尾记录退出码：`# exit code: 0`。
- 必须包含 `make guard` 的输出（Done 条件之一）。

## 7. 截图
- 放 `screenshots/`，PNG，文件名 `NN-步骤短名.png`，与 README 复现步骤编号一致。
- 临时截图、调试日志不放这里，放 `.local/`（`docs/项目完整目录结构.txt`：临时文件/截图 → `.local/`，自动 gitignore）；只有作为证据的才移入 EVD。
- 真机截图需能看出平台与时间（状态栏或聊天时间戳）。

## 8. 脱敏（强制）
- 不得出现：密码、API Key、Bot Token、设备令牌、会话 Cookie、context_token、二维码可扫的原图、手机号、他人聊天内容。
- 截图打码；日志用占位符（`sk-***`）。提交前 gitleaks 会扫描（守卫 GD-04），被拦即视为证据不合格。

## 9. 不合格证据（验证者应判 UNKNOWN 或 FAIL）
- 只有“已完成”“测试通过”的文字描述，没有原始输出；
- 输出无法对应到 commit；
- 截图与步骤对不上；
- 依赖执行者本机才存在的文件或环境而未说明。
