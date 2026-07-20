# Screenshots — Before/After Evidence

Add before/after screenshots for each scenario here. Suggested filenames
(referenced from the scenario solution files):

**Scenario 1 — Can't SSH**
- `s1-before-route-table.png` — route table missing `0.0.0.0/0 -> igw`, SSH times out
- `s1-after-route-added.png` — IGW route present, SSH connects

**Scenario 2 — Website not loading**
- `s2-before-sg-no-port80.png` — security group only shows port 22; public curl times out
- `s2-after-port80-added.png` — inbound port 80 added; site loads publicly

**Scenario 3 — Application crashes**
- `s3-before-logs-db-timeout.png` — app logs showing DB connection timeout / crash loop
- `s3-after-db-connected.png` — DB SG rule added; app stable, "Connected to database"

> Capture each pair while reproducing the failing command, applying the fix, then
> re-running the same command to prove it now works.
