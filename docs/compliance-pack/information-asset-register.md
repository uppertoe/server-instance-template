# Information asset register — staging reference instance

Business Impact Levels per the VPDSF BIL table (v2.1): 1 Minor · 2 Limited ·
3 Major · 4 Serious. Identifiable health information typically assesses at
**BIL-2 (Limited) → OFFICIAL: Sensitive**; justify anything lower.
C-I-A = impact of a Confidentiality / Integrity / Availability compromise.

| App / asset | Information held | Identifiable? | C | I | A | Marking | Lives in | Backed up to | Retention class |
|---|---|---|---|---|---|---|---|---|---|
| ntfy | alert history (host security events, hostnames, service names) | no | 1 | 1 | 1 | OFFICIAL | `ntfy_cache`/`ntfy_lib` volumes | not backed up | operational |
| auth service | **disabled on staging** — when enabled: operator email, session/TOTP secrets | yes (operator only) | 2 | 2 | 1 | OFFICIAL: Sensitive | `auth_data` volume (AES-GCM for reversible secrets) | **none** — env-files covers `.env` only; a dedicated backup service for `auth_data` must be added before enabling auth | operational |
| host logs | auditd/auth/caddy access logs (source IPs; `user` field carries auth emails on protected routes) | partial (operator + visitors' IPs) | 2 | 2 | 1 | OFFICIAL: Sensitive | journald + `caddy_logs` volume | Object-Locked S3 log bucket (12 months) | 12 months |
| secrets/config | inventory tokens, SMTP/S3 credentials, restic password | no (credentials, not personal info) | 2 | 2 | 2 | OFFICIAL: Sensitive | gitignored files, mode 600 | encrypted recovery bundle (offsite) + env-files restic | until rotation |
| backups | union of backed-up assets above | as per sources | 2 | 2 | 2 | OFFICIAL: Sensitive | restic (client-side AES-256) → S3 bucket | — | per source |

**No asset on this instance holds health information.** The register's first
clinical row is the tripwire that re-opens the
[scope determination](scope-determination.md) and
[jurisdiction record](hosting-jurisdiction-record.md) — a clinical app's row
will typically read: identifiable **yes**, C=2+ → OFFICIAL: Sensitive,
retention `health record 7yr/age-25`, and MUST name an AU-region backup repo.

**Highest classification on the system:** OFFICIAL: Sensitive (credentials
and operator-identifying logs; no health information) — this drives the
control-proportionality argument in the [SSP](system-security-plan.md).

Review: with every new app, and at least annually. Last review: 2026-07-05.
