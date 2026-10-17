---
id: WF-TECH-REQ
type: technical-requirements
title: 技术需求
status: approved-for-planning
version: V0.0.4
created: 2026-10-17
---

# 技术需求

| ID | 技术需求 | 来源 |
|---|---|---|
| TR-01 | Node.js 22 LTS、TypeScript 5 strict、pnpm workspaces | ADR-004/009、REQ-C-001 |
| TR-02 | 契约 JSON Schema 2020-12 唯一源，生成 TS 类型与 ajv 校验器；CI 检查生成物漂移 | ADR-002 |
| TR-03 | SQLite（WAL、foreign_keys=ON、busy_timeout=5000）经 better-sqlite3 + Kysely；迁移纯 SQL 序号文件 | ADR-003/009、DEC-028 |
| TR-04 | 中转：Fastify 5 + ws；只监听 127.0.0.1:5101，经 Caddy/Nginx 443 TLS 反代 | ADR-001/009、DEC-051 |
| TR-05 | 节点：127.0.0.1:5100/5102/5103/5104；单实例锁；子进程监管（Windows Job Object、POSIX 进程组） | DEC-021/041 |
| TR-06 | 中转↔节点 WSS envelope v1：seq/ack、续传、幂等键、20 s 心跳、1 MiB 帧上限 | ADR-005 |
| TR-07 | Web：React 19、Vite、TanStack Query、Zustand、Radix/shadcn、Tailwind 4、@rjsf；两个构建目标；PWA | ADR-008/014 |
| TR-08 | 凭据：中转 IM 凭据 AES-256-GCM（主密钥文件 0600 或环境变量）；节点 OS 钥匙串（DPAPI/Keychain/libsecret）回退加密文件 | DEC-020/044 |
| TR-09 | 日志 pino JSON + trace_id；/metrics Prometheus 文本 | REQ-NF-007 |
| TR-10 | 测试：vitest（单测/集成）、Playwright（E2E）、FakeAgent/FakeChannel；CI 三平台矩阵 | DEC-029、ADR-011 |
