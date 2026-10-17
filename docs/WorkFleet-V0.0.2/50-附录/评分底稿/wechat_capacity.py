# 微信 ClawBot 额度推演（假设参数均为判断性，标注于 08 §1.5）
CAP=10; RES_P0=2; USABLE=CAP-RES_P0
profiles=8; turns_per_profile=6; approvals_per_profile=1; fail_rate=0.10; work_hours=10
completions=profiles*turns_per_profile; approvals=profiles*approvals_per_profile; fails=round(completions*fail_rate)
naive=completions+approvals+fails
print("naive msgs/day",naive,"inbounds needed",-(-naive//USABLE))
# 设计：审批 p0 逐条；失败 p1 逐条；完成 p3 每小时合并 1 条（最多 work_hours 条）；阻塞/提问 p1 逐条（假设 2）
questions=2
digests=work_hours
designed=approvals+fails+questions+digests
print("designed msgs/day",designed,"inbounds needed",-(-designed//USABLE))
# 审批回复本身即入站：每条 Y1/N 回复重置窗口
print("approval replies as inbounds",approvals,"→ capacity",approvals*CAP)
# 静默期（用户 8h 不回复）：只剩一个窗口 10 条，p0 保留 2
night_events=profiles*1  # 夜间每 profile 1 条完成
print("night: completions",night_events,"→ 1 合并摘要 + 剩余", USABLE-1)
# 24h 无入站 → context_token 失效 → 全部走 fallback
# S4
for subs in (1000,10000,100000):
    tg=subs/30/0.9; fs=subs/50/0.9
    print(subs,"TG min",round(tg/60,1),"Feishu min",round(fs/60,1))
