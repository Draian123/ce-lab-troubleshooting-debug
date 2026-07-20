# Scenario 3 — Application Crashes

## Symptom
- Application **starts successfully**.
- **Crashes after ~30 seconds**.
- Error in logs: **`Cannot connect to database`**.

## Why this matters
Starting fine then dying at ~30s is the classic signature of a **connection attempt
that hangs until it times out**. The app boots, tries to reach the database, waits for
the default connection timeout (~30s), gives up, and crashes. A *timeout* (not
"connection refused" or "access denied") again points at a **network block between the
app and the DB**, most often a missing **security-group-to-security-group** rule.

## Diagnosis

```bash
# 1. Read the actual application logs / CloudWatch Logs
journalctl -u myapp -n 50 --no-pager
# or:
aws logs tail /myapp/application --since 10m --follow
# -> "Error: connect ETIMEDOUT db.xxxx.rds.amazonaws.com:5432"

# 2. What DB endpoint / port is the app configured to use?
sudo cat /etc/myapp/config.env | grep -i db
# DB_HOST=mydb.abc123.eu-west-1.rds.amazonaws.com
# DB_PORT=5432

# 3. Test connectivity to the DB from the instance
nc -zv mydb.abc123.eu-west-1.rds.amazonaws.com 5432
# -> timed out   <-- confirms network block (not auth, not wrong creds)

# 4. Inspect the RDS instance's security group inbound rules
aws rds describe-db-instances --db-instance-identifier mydb \
  --query 'DBInstances[0].[Endpoint.Address,VpcSecurityGroups]'

aws ec2 describe-security-groups --group-ids sg-DB123 \
  --query 'SecurityGroups[0].IpPermissions'
# -> no rule allowing 5432 from the app's security group  <-- ROOT CAUSE
```

## Root Cause
The **RDS (database) security group does not allow inbound traffic on the DB port
(5432/3306) from the application instance's security group**. The app can resolve the
endpoint but every connection attempt is silently dropped, hangs for ~30s, times out,
and the process exits.

*(Rule out the close cousins with the diagnosis above: if `nc` had connected but the log
said "password authentication failed", the cause would be wrong credentials/env vars;
if the endpoint didn't resolve, a wrong `DB_HOST`. Here `nc` times out → it's the SG.)*

## Fix

```bash
# Allow the app's SG to reach the DB on its port (SG-to-SG rule = best practice,
# no hard-coded IPs, scales with autoscaling)
aws ec2 authorize-security-group-ingress \
  --group-id sg-DB123 \
  --protocol tcp --port 5432 \
  --source-group sg-APP123
```

Also confirm the app's environment is correct (only if the log pointed at auth/config):

```bash
# Example env sanity check
grep -E 'DB_HOST|DB_PORT|DB_USER|DB_NAME' /etc/myapp/config.env
sudo systemctl restart myapp
```

## Verify

```bash
# DB SG now allows the app SG on 5432
aws ec2 describe-security-groups --group-ids sg-DB123 \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`5432`]'

# Connectivity from the app instance
nc -zv mydb.abc123.eu-west-1.rds.amazonaws.com 5432   # -> succeeded

# App stays up past 30s and logs a healthy DB connection
sudo systemctl restart myapp
journalctl -u myapp -f      # -> "Connected to database" ; process stable
```

## Prevention
- Define the **SG-to-SG rule in IaC** so app and DB are wired together at deploy time.
- Add **connection-retry with backoff** and a readiness probe so a slow DB doesn't
  hard-crash the app.
- Put DB endpoint/credentials in **Secrets Manager / SSM Parameter Store**, not hard-coded.
- Add a **CloudWatch alarm** on app restarts / DB connection errors.

## Screenshots
- `screenshots/s3-before-logs-db-timeout.png` — logs showing ETIMEDOUT / crash loop
- `screenshots/s3-after-db-connected.png` — SG rule added, app stable, "Connected to database"
