# Troubleshooting Guide — Methodology

A repeatable, systematic method for diagnosing and fixing cloud deployment issues.
The goal is to move from *symptom* to *root cause* to *verified fix* without guessing.

## Core Principle

**Change one thing at a time, verify, then move on.** Guessing and changing
multiple variables at once hides the real root cause and creates new bugs.

## The 6-Step Method

### 1. Define the problem precisely
- What is the exact symptom? (timeout vs. connection refused vs. 500 error are all different)
- When did it start? What changed just before?
- Is it reproducible? Always, or intermittently?

> **Key distinction:** A **timeout** usually means traffic is being *dropped silently*
> (security group, NACL, routing, wrong IP). A **"connection refused"** means the
> packet *reached the host* but nothing is listening on that port (service down,
> wrong port, bound to 127.0.0.1 only).

### 2. Gather evidence (don't assume)
- Read the actual configuration with the AWS CLI, don't trust the console at a glance.
- Check logs: `journalctl`, `/var/log/`, and CloudWatch Logs.
- Test connectivity at each layer.

### 3. Work the layers, outside-in (OSI-style)
Follow the path a packet actually takes and test each hop:

| Layer | What to check | Tool |
|-------|---------------|------|
| DNS / IP | Correct public IP / DNS resolves | `nslookup`, `dig` |
| Routing | Route table has IGW/NAT route | `aws ec2 describe-route-tables` |
| Firewall (subnet) | Network ACL allows in **and** out | `aws ec2 describe-network-acls` |
| Firewall (instance) | Security group inbound rule | `aws ec2 describe-security-groups` |
| Host firewall | `ufw`/`iptables` on the OS | `sudo iptables -L` |
| Service | Process listening on the port | `ss -tuln`, `ps aux` |
| Application | App logs / health | `journalctl -u <svc>` |

### 4. Form a hypothesis, then test it
State what you *think* is wrong and how you'll confirm it **before** changing anything.
Example: "curl localhost works but public fails → I bet the SG has no port 80 rule.
I'll check with `describe-security-groups` before adding a rule."

### 5. Apply the smallest fix and verify
- Make one change.
- Re-run the exact failing command to confirm it now works.
- Confirm you didn't break anything else.

### 6. Document
- Record the symptom, root cause, fix, and how you verified it.
- Note how to prevent it next time (IaC, checklist, alarm).

## Isolation Techniques

- **Bisect the path:** SSH into the instance and `curl localhost` — if that works,
  the problem is *between* the client and the host (network), not the app.
- **Binary search config changes:** revert to a known-good state, then re-apply changes
  one at a time until the failure reappears.
- **Compare working vs. broken:** diff a healthy resource's config against the broken one.

## Common AWS Failure Categories

1. **Networking** — security groups, NACLs, route tables, missing/absent public IP, subnet is private.
2. **Firewall on host** — OS-level `iptables`/`ufw` blocking despite correct SG.
3. **Service binding** — app bound to `127.0.0.1` instead of `0.0.0.0`.
4. **Dependencies** — database/cache unreachable (SG-to-SG rule, wrong endpoint, credentials).
5. **Permissions/IAM** — instance role missing a policy.
6. **Configuration** — wrong env vars, wrong port, typo in endpoint.

## Golden Rules

- Read the **exact** error message — it usually names the layer.
- Timeout ≠ refused ≠ error. Each points at a different layer.
- If it worked yesterday, ask *what changed*.
- Verify the fix by reproducing the original failing action.
