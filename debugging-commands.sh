#!/usr/bin/env bash
#
# debugging-commands.sh
# A cheat-sheet of commands for troubleshooting AWS EC2 / networking / app issues.
# NOT meant to be run top-to-bottom — copy the section you need and fill in the IDs.
#
# Placeholders:  i-xxxxx = instance id   sg-xxxxx = security group   rtb-xxxxx = route table
#                PUBLIC_IP = public IP        SVC = systemd service      subnet-xxxxx = subnet id
set -euo pipefail

########################################
# 1. INSTANCE STATE & METADATA
########################################

# Is the instance running? What are its status checks?
aws ec2 describe-instance-status --instance-ids i-xxxxx \
  --query 'InstanceStatuses[0].[InstanceState.Name,SystemStatus.Status,InstanceStatus.Status]'

# Public IP, subnet, VPC, and attached security groups
aws ec2 describe-instances --instance-ids i-xxxxx \
  --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress,SubnetId,VpcId,SecurityGroups]'

########################################
# 2. NETWORK PATH (outside-in)
########################################

# Security group inbound rules (which ports are open, from where)
aws ec2 describe-security-groups --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions'

# Add a missing inbound rule (example: HTTP 80 from anywhere)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx --protocol tcp --port 80 --cidr 0.0.0.0/0

# Add an SG-to-SG rule (example: app SG -> DB SG on 5432)
aws ec2 authorize-security-group-ingress \
  --group-id sg-DBxxxx --protocol tcp --port 5432 --source-group sg-APPxxxx

# Route table for a subnet — must have 0.0.0.0/0 -> igw for public access
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxxx" \
  --query 'RouteTables[0].Routes'

# Add the missing default route to an Internet Gateway
aws ec2 create-route --route-table-id rtb-xxxxx \
  --destination-cidr-block 0.0.0.0/0 --gateway-id igw-xxxxx

# Network ACLs (subnet-level firewall — remember it needs return/ephemeral ports too)
aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=subnet-xxxxx" \
  --query 'NetworkAcls[0].Entries'

########################################
# 3. CONNECTIVITY TESTS (from your laptop)
########################################

nc -zv PUBLIC_IP 22            # is port 22 reachable? (succeeded vs timed out vs refused)
nc -zv PUBLIC_IP 80
telnet PUBLIC_IP 80            # alternative reachability test
curl -v http://PUBLIC_IP       # verbose HTTP request (see where it hangs/fails)
nslookup DB_ENDPOINT    # does the DNS name resolve?
dig +short DB_ENDPOINT

########################################
# 4. ON THE INSTANCE — SERVICE & PORTS
########################################

# What's listening, and on which interface?  0.0.0.0 = all, 127.0.0.1 = loopback only
ss -tuln
ss -tuln | grep :80

# Is the process running?
ps aux | grep -i APP

# systemd service status + recent logs
systemctl status SVC
journalctl -u SVC -n 50 --no-pager
journalctl -u SVC -f          # follow live

# Restart after a config change
sudo systemctl restart SVC

# Host firewall (can block even when the SG is correct)
sudo iptables -L -n
sudo ufw status

# General system logs
sudo tail -n 100 /var/log/messages    # Amazon Linux / RHEL
sudo tail -n 100 /var/log/syslog      # Ubuntu/Debian

########################################
# 5. CLOUDWATCH LOGS
########################################

# List log groups
aws logs describe-log-groups --query 'logGroups[].logGroupName'

# Tail an application log group
aws logs tail /myapp/application --since 15m --follow

# Filter for errors in a log group
aws logs filter-log-events --log-group-name /myapp/application \
  --filter-pattern 'ERROR' --start-time $(( ( $(date +%s) - 900 ) * 1000 ))

########################################
# 6. DATABASE (RDS) CHECKS
########################################

# Endpoint, port, and the SGs attached to the DB
aws rds describe-db-instances --db-instance-identifier mydb \
  --query 'DBInstances[0].[Endpoint.Address,Endpoint.Port,DBInstanceStatus,VpcSecurityGroups]'

# From the app instance: can we even reach the DB port?
nc -zv DB_ENDPOINT 5432    # postgres
nc -zv DB_ENDPOINT 3306    # mysql

########################################
# 7. QUICK TRIAGE HEURISTICS
########################################
# timeout           -> traffic dropped: security group / NACL / route table / no public IP
# connection refused-> reached host, nothing listening: service down / wrong port / bound to 127.0.0.1
# works on localhost, fails publicly -> missing SG inbound rule OR app bound to loopback
# starts then dies ~30s with DB error -> DB SG missing inbound from app SG (or wrong creds/endpoint)
