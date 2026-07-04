# Information asset register — ⟨host⟩

Business Impact Levels per the VPDSF BIL table (v2.1): 1 Minor · 2 Limited ·
3 Major · 4 Serious. Identifiable health information typically assesses at
**BIL-2 (Limited) → OFFICIAL: Sensitive**; justify anything lower.
C-I-A = impact of a Confidentiality / Integrity / Availability compromise.

| App / asset | Information held | Identifiable? | C | I | A | Marking | Lives in | Backed up to | Retention class |
|---|---|---|---|---|---|---|---|---|---|
| ⟨app⟩ | ⟨e.g. patient identifiers + clinical notes⟩ | ⟨yes/no/pseudonymised⟩ | ⟨2⟩ | ⟨2⟩ | ⟨1⟩ | ⟨OFFICIAL: Sensitive⟩ | ⟨volume/db⟩ | ⟨restic repo + region⟩ | ⟨health record 7yr/25⟩ |
| auth service | email addresses, session/TOTP secrets | yes | 2 | 2 | 2 | OFFICIAL: Sensitive | `auth_data` volume (AES-GCM for reversible secrets) | ⟨repo⟩ | operational |
| ntfy | alert history (host security events) | no | 1 | 1 | 1 | OFFICIAL | `ntfy_*` volumes | not backed up | operational |
| host logs | auditd/auth/caddy access logs (IPs, emails in auth events) | partial | 2 | 2 | 1 | OFFICIAL: Sensitive | journald + `caddy_logs` | ⟨off-host target when B3 lands⟩ | 12 months |
| backups | union of the above | yes | ⟨max of rows⟩ | 2 | 2 | OFFICIAL: Sensitive | ⟨S3 bucket + region⟩ | — | per source |

**Highest classification on the system:** ⟨…⟩ — this drives the control
proportionality argument in the [SSP](system-security-plan.md) and the
[jurisdiction record](hosting-jurisdiction-record.md).

Review: with every new app, and at least ⟨annually⟩. Last review: ⟨date⟩.


---

## Instance register — rch-vps (made 2026-07-05)

| Asset | Class | Where | Owner | Protection |
|---|---|---|---|---|
| Caddy reverse proxy | Infrastructure | rch-vps container | operator | CIS §5 hardened, digest-pinned, healthchecked |
| ntfy alert service | Infrastructure (ops alerts only) | rch-vps container | operator | token-authenticated, loopback URL |
| System + audit logs | Operational metadata | journald → S3 Sydney (Object Lock, 12-month) | operator | hash-chained, write-only credentials |
| App .env secrets | Credentials | /opt/deploy (mode 600) + restic env-files service | operator | AES-256 encrypted backup; recovery root in operator password manager |
| AIDE baseline + evidence bundles | Integrity evidence | /var/lib/aide + reports/ (control machine) | operator | re-baseline journalled + shipped off-host |
| **Health information** | — | **None. Prohibited on this instance by scope-determination.md** | — | design constraint, reviewed before every new app |

No asset on this instance contains personal or health information. The register
must be re-issued before any app that changes that.
