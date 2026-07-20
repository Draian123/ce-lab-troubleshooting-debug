# Scenario 1 — Can't SSH to Instance

## Symptom
- Instance is **running**.
- Security group **looks correct** (inbound TCP 22 from my IP is present).
- SSH connection **times out** (`ssh: connect to host ... port 22: Connection timed out`).

## Why this matters
A **timeout** (not "connection refused") means packets are being **dropped silently
somewhere on the network path**, *before* reaching the SSH daemon. If sshd were down
we'd get "connection refused". So the SSH service is fine — the problem is networking.

## Diagnosis (work the path outside-in)

```bash
# 1. Confirm the instance is really up and reachable at the OS level
aws ec2 describe-instance-status --instance-ids i-0abc123 \
  --query 'InstanceStatuses[0].[InstanceState.Name,SystemStatus.Status,InstanceStatus.Status]'
# -> running / ok / ok

# 2. Does the instance even have a PUBLIC IP?  (very common cause)
aws ec2 describe-instances --instance-ids i-0abc123 \
  --query 'Reservations[0].Instances[0].[PublicIpAddress,SubnetId,VpcId]'
# -> [ null, subnet-xxxx, vpc-xxxx ]   <-- no public IP is a red flag

# 3. Security group actually allows 22 from my IP?
aws ec2 describe-security-groups --group-ids sg-0abc123 \
  --query 'SecurityGroups[0].IpPermissions'
# -> port 22 from my.ip.addr/32  ... looks fine, as reported

# 4. Route table for the subnet — is there a route to the Internet Gateway?
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxx" \
  --query 'RouteTables[0].Routes'
# -> only 'local' 10.0.0.0/16 ... NO 0.0.0.0/0 -> igw  <-- ROOT CAUSE

# 5. Network ACL — is it blocking 22 (or ephemeral return ports)?
aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=subnet-xxxx" \
  --query 'NetworkAcls[0].Entries'
```

## Root Cause
The subnet's **route table has no route to an Internet Gateway** (no
`0.0.0.0/0 -> igw-xxxx` entry). The instance sits in what is effectively a **private
subnet**: the security group is correct, but traffic from the internet can never reach
it because there's no path in/out.

(The second most common variant of this scenario — and worth ruling out — is that the
instance simply has **no public IP address** assigned, or a **Network ACL denies**
inbound 22 / the outbound ephemeral return ports.)

## Fix

```bash
# Add the missing default route to the Internet Gateway
aws ec2 create-route \
  --route-table-id rtb-0abc123 \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id igw-0abc123

# If the instance had no public IP, associate an Elastic IP instead:
# aws ec2 allocate-address
# aws ec2 associate-address --instance-id i-0abc123 --allocation-id eipalloc-xxxx
```

## Verify

```bash
# Route now present
aws ec2 describe-route-tables --route-table-id rtb-0abc123 \
  --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`]'

# Network reachability
nc -zv <public-ip> 22        # -> succeeded!
ssh -i key.pem ec2-user@<public-ip>   # -> logs in
```

## Prevention
- Use an **IaC template** (CloudFormation/Terraform) that always attaches the IGW route
  for public subnets.
- Name subnets clearly `public-*` / `private-*` so mistakes are obvious.
- Use **VPC Reachability Analyzer** to test the path before deploying.

## Screenshots
- `screenshots/s1-before-route-table.png` — route table missing 0.0.0.0/0
- `screenshots/s1-after-route-added.png` — route to IGW present, SSH succeeds
