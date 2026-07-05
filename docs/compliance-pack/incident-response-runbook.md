# Incident response runbook — staging reference instance

**Owner:** repo owner ⟨phone — keep current⟩ · **Deputy:** none (single
operator; the dead-man's monitor is the deputy) · **Last test:** pending
(first tabletop due within 12 months)

Generic procedure: `scaffold/docs/11-incident-response.md` (read it first).
This file holds the *instance* specifics: contacts, class table, and which
notification rows are live.

> **Status: no health information is held**, so the DH/eHealth rows below are
> DORMANT. They activate — and this runbook must be re-issued with real
> contacts — the day this instance is commissioned for health-service use.
> DH Policy & Funding Guidelines §24.4: significant ICT incidents go to the
> eHealth Incident Management Team **within the hour**; all cyber incidents
> (including supplier breaches) as soon as detected **or suspected**.

## 1. Detection sources

ntfy topic (gitignored inventory) carries: auditd real-time config-tampering
events · AIDE integrity failures · unit failures (backup, docker, sshd,
fail2ban…) · fixable CRITICAL CVEs (daily scan) · patch-SLA breaches ·
disk-threshold and container-health watchers · post-reboot health reports ·
weekly security digest (auth-denial spikes, listening-socket changes) ·
monthly channel self-test. External monitor alarms on host-down. Manual:
provider notices, GitHub security alerts.

## 2. Triage (15 minutes)

1. Confirm on a second source (`journalctl -u ⟨unit⟩`, `last`,
   `ausearch -ts recent`, `docker ps`) — from the incident log, not memory.
2. Classify: **A** suspected compromise · **B** availability ·
   **C** vulnerability, no compromise indication · **D** data-breach
   indication (on this instance: credentials/operator data; no health data
   held).
3. Class A or D → containment AND notification in parallel.

## 3. Containment (class A/D)

Snapshot first (provider console), then isolate — prefer the **provider
firewall** over on-host `ufw` (works even if the host is attacker-controlled):

```
# On-host fallback (keep the box for forensics):
sudo ufw insert 1 allow from ⟨admin IP⟩ to any port 22 proto tcp
sudo ufw delete allow 80/tcp; sudo ufw delete allow 443/tcp; sudo ufw delete allow 443/udp
cd /opt/deploy && docker compose down
# Freeze the repo-to-root chain:
sudo systemctl stop auto-deploy.timer   # if enabled
```
Then lock `main` / disable automerge on GitHub until closed.

## 4. Notification tree

| Who | When | How | Live? |
|---|---|---|---|
| Operator (self) + incident log | immediately | — | ✅ |
| Hosting provider (RackNerd) | abuse/compromise per ToS | provider portal | ✅ |
| GitHub (account compromise) | immediately | support + credential rotation | ✅ |
| eHealth Incident Management Team (DH) | within the hour (significant) / on suspicion (all) | 1300 598 686 · Digital.Health.Incident.Notification@health.vic.gov.au | 💤 dormant — activates at commissioning |
| Health service CISO/IT security | with the DH call | ⟨fill at commissioning⟩ | 💤 dormant |
| HCC (Vic) | encouraged ≤14 days for health-privacy breaches | hcc.vic.gov.au | 💤 dormant |
| OAIC NDB | if private-practice data + likely serious harm (30-day assessment) | oaic.gov.au | 💤 dormant — activates with any private-practice app |
| ASD ransomware-payment report | 72 h if any payment made (Cyber Security Act 2024) | cyber.gov.au/report | ✅ (applies regardless) |

## 5. Evidence preservation

Provider disk snapshot **before anything else**; the Object-Locked S3 log
bucket already holds the tamper-evident journal/audit/access trail
independent of the box. Additionally copy off-host: `journalctl -o export`,
`/var/log/audit/`, `caddy_logs` volume (access log carries the per-user
`user` field), AIDE databases, `/var/lib/vuln-scan`, `docker inspect` of all
containers. Record `date -u`, `who`, and hashes in the incident log.

## 6. Recovery

Rebuild, don't disinfect: `scaffold/docs/09-recovery.md` (fresh VPS →
provision → restore from a pre-incident restic snapshot). Rotate everything
in the recovery bundle + `SESSION_SECRET` + SSH/GitHub credentials; repoint
dead-man and ntfy before cutover; re-run `audit-all.yml`; post-incident note
and RTO entry within 2 weeks.

## 7. Annual test

Tabletop the worst plausible scenario for the current app set (today:
credential theft → repo-to-root attempt; at commissioning: class D on the
highest-BIL app). Record date, participants, gaps, fixes here.
