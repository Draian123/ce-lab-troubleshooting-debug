# Lab Solution — M2.09 Troubleshooting and Debugging

This lab presents three intentionally broken deployment scenarios. Each is diagnosed
using a systematic, layer-by-layer method and fixed with the smallest verified change.

## Deliverables

| File | Purpose |
|------|---------|
| [`TROUBLESHOOTING-GUIDE.md`](./TROUBLESHOOTING-GUIDE.md) | The methodology — a repeatable 6-step debugging process |
| [`scenario-1-solution.md`](./scenario-1-solution.md) | Can't SSH — root cause: missing IGW route (private subnet) |
| [`scenario-2-solution.md`](./scenario-2-solution.md) | Website not loading — root cause: security group missing inbound port 80 |
| [`scenario-3-solution.md`](./scenario-3-solution.md) | App crashes — root cause: DB security group missing inbound from app SG |
| [`debugging-commands.sh`](./debugging-commands.sh) | Reusable AWS CLI + Linux troubleshooting cheat-sheet |
| [`screenshots/`](./screenshots/) | Before/after evidence for each scenario |

## Summary of Root Causes & Fixes

| # | Symptom | Root Cause | Fix |
|---|---------|-----------|-----|
| 1 | SSH times out | Subnet route table has no `0.0.0.0/0 -> igw` (effectively private) | `aws ec2 create-route ... --gateway-id igw-xxxx` |
| 2 | Public site fails, `curl localhost` works | Security group has no inbound TCP 80 | `aws ec2 authorize-security-group-ingress --port 80` |
| 3 | App crashes ~30s, "Cannot connect to database" | DB security group missing inbound from app SG | `authorize-security-group-ingress --source-group sg-APP` |

## Key Diagnostic Insight

The single most useful distinction throughout this lab:

> **Timeout** = traffic is silently **dropped** on the network path (security group,
> NACL, route table, missing public IP).
> **Connection refused** = the packet **reached the host** but nothing is listening
> (service down / wrong port / bound to loopback only).

Every scenario here produced a *timeout*, which correctly pointed the investigation at
the **networking layers** rather than the application — and in all three cases the fault
was an AWS security-group or routing misconfiguration, not the app itself.
