# Scenario 2 — Website Not Loading

## Symptom
- Can **SSH** to the instance (so basic networking + SSH SG rule are fine).
- Application **is running**.
- `curl localhost:80` on the instance **works** → returns the page.
- Public access `curl http://<public-ip>` **fails / times out**.

## Why this matters
`curl localhost:80` working proves the **web server is up, listening, and serving**.
The failure is therefore **between the client and the host** — a networking layer, not
the app. Since SSH works, routing and the IGW are fine; the difference between SSH
(works) and HTTP (fails) is almost always a **missing inbound rule for port 80**.

## Diagnosis

```bash
# 1. Confirm the app is listening on all interfaces, not just loopback
ss -tuln | grep :80
# GOOD:  LISTEN 0 511 0.0.0.0:80    (or *:80)
# BAD:   LISTEN 0 511 127.0.0.1:80  <-- would only answer localhost

# 2. From the instance, it works:
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:80   # -> 200

# 3. Inspect the security group inbound rules
aws ec2 describe-security-groups --group-ids sg-0abc123 \
  --query 'SecurityGroups[0].IpPermissions[].{proto:IpProtocol,from:FromPort,to:ToPort,cidr:IpRanges}'
# -> only port 22 present.  NO port 80.  <-- ROOT CAUSE

# 4. Rule out host firewall
sudo iptables -L -n | grep -E '80|DROP'
sudo ufw status
```

## Root Cause
The **security group has no inbound rule for HTTP (TCP 80)**. Only SSH (22) was opened.
Public HTTP traffic hits the SG and is dropped, producing a timeout, even though the
web server serves fine locally.

*(If `ss` had shown the app bound to `127.0.0.1:80`, the root cause would instead be
the app binding to loopback only — fix by binding to `0.0.0.0`. Here it binds correctly,
so the SG is the culprit.)*

## Fix

```bash
# Open port 80 to the world (or restrict CIDR as appropriate)
aws ec2 authorize-security-group-ingress \
  --group-id sg-0abc123 \
  --protocol tcp --port 80 \
  --cidr 0.0.0.0/0

# If also serving HTTPS:
# aws ec2 authorize-security-group-ingress --group-id sg-0abc123 \
#   --protocol tcp --port 443 --cidr 0.0.0.0/0
```

## Verify

```bash
# Rule is now present
aws ec2 describe-security-groups --group-ids sg-0abc123 \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`]'

# From your laptop (not the instance):
curl -v http://<public-ip>        # -> HTTP/1.1 200 OK
nc -zv <public-ip> 80             # -> succeeded
```

## Prevention
- Bake required ingress ports (22/80/443) into the IaC security-group definition.
- Use a **load balancer** in front so instances only trust the ALB's SG.
- Add a CloudWatch/Route 53 **health check** on the public URL to catch this fast.

## Screenshots
- `screenshots/s2-before-sg-no-port80.png` — SG only shows port 22
- `screenshots/s2-after-port80-added.png` — port 80 rule added, site loads publicly
