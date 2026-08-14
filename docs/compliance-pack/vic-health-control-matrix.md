# Control matrix — staging reference instance

One row per control: which standard demands it, what implements it, and where
the evidence lives. The DH column maps to the **Baseline Cybersecurity
Controls** workbook (VMIA hub) — dormant until commissioning by a health
service; the matrix stands on the HPP/ISM/E8/VPDSS columns without it.

Legend: ✅ implemented · ⚠️ partial/pending item ⟨ref⟩ · ➖ per-deployment decision.
Evidence paths are on-host unless prefixed `reports/` (fetched by the audit
playbooks) or `CI`.

| # | Control | HPP | ISM | E8 | VPDSS | Implemented by | Evidence | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | Host OS hardened to CIS Ubuntu 24.04 (L1 + **L2 on this host**) | 4.1 | 1409 | — | E11.090 | `os-/ssh-/baseline-hardening` roles | `reports/openscap-*` + tailoring file + exceptions register | ✅ |
| 2 | Docker daemon hardened (CIS Docker §1–4) | 4.1 | 1409 | — | E11.090 | `docker` role | `reports/docker-bench-*` | ✅ |
| 3 | Containers non-root, cap-dropped, read-only, no-new-privs (CIS §5) — incl. one-shot init containers | 4.1 | 1409 | app hardening | E11.090 | compose §5 blocks + labelled init audit | `reports/compose-audit-*` + CI KICS | ✅ |
| 4 | Key-only SSH, root locked, no password auth; restricted deploy (wrapper-only sudo, no docker group) | 4.1 | 0484/0485 | restrict admin | E11.120 | `ssh-hardening`, `deploy-user` (restricted mode — host var, template default off; set true on this host, with a dedicated admin key) | openscap SSH rules; `sshd -T` capture; smoke test | ✅ |
| 5 | MFA for privileged/app access | 4.1 | 1173 | MFA | E11.120 | auth tier TOTP for admins | auth `.env` capture (`TOTP_ENABLED`) | ⚠️ B4 — flip at commissioning (auth currently disabled) |
| 6 | Firewall default-deny in/out, Docker-aware; **container egress on the same allowlist** | 4.1 | — | — | E11.130 | `firewall` role (DOCKER-USER allowlist + DROP) | `ufw status verbose` + `iptables -S VPS-SCAFFOLD-DOCKER-USER` captures | ✅ |
| 7 | TLS for all external access (ACME, auto-HTTPS); HSTS + security-header baseline injected per site | 4.1 | crypto ch. | — | E11.140 | Caddy + route renderer | cert chain capture; rendered bundle in git | ✅ |
| 8 | OS security patches auto-applied; **patch-window reboots**; SLA backstop alert | 4.1 | patch SLAs | patch OS | E11.040 | unattended-upgrades + Automatic-Reboot + `pending-security-updates.timer` + `vps-boot-check` | journal `PATCH-SLA` lines; boot-check ntfy history | ✅ |
| 9 | Daily CVE scan of running images; 48h clock on fixable CRITICALs | 4.1 | patch SLAs | patch apps | E11.040 | `vuln-scan.timer` (digest-pinned scanner) | `/var/lib/vuln-scan/<date>/` · `reports/vuln-*` | ✅ |
| 10 | Application control equivalent (digest-pinned images incl. deploy-hook lint, AppArmor, 3-day automerge cooldown) | 4.1 | 1409 | app control | E11.090 | compose pins + `check-image-pins.sh` + Renovate `minimumReleaseAge` | CI `static-checks` job (image-pins step); `aa-status` capture | ✅ |
| 11 | Audit logging: auditd (immutable, L2 ruleset), AIDE, real-time audit→ntfy | 4.1 | 1988 partial | — | E11.110 | `baseline-hardening`, `notify` (immutable `-e 2` ruleset requires `baseline_cis_l2_audit_rules=true`; set on this host, template default off) | auditd rules capture; ntfy history | ✅ |
| 12 | Logs off-host, tamper-evident, 12-month retained (retrievable for search) | 4.1 | 1988/1815 | — | E11.110 | `log-export` role → write-only Object-Locked S3 (provisioning fails without a destination unless `log_export_accept_none`) | bucket policy capture; export timer journal | ✅ |
| 13 | **Logs reviewed**, not just retained | 4.1 | log review | — | E11.110 | `vps-log-digest` weekly timer (counts, deltas, auth denials) | digest journal entries (dated) + ntfy history | ✅ |
| 14 | Backups encrypted, hourly, integrity-checked weekly | 4.1 | 1810/1811 | backups | E11.180 | `backup` role (restic, checksum-verified install) | `backup-verify` journal; restic config capture | ✅ |
| 15 | Restore tested with RPO/RTO recorded | 4.1 | 1810+ | backups | E11.180 / Std 7 | `restore-drill.timer` | `/var/lib/backup-drill/latest.txt` | ✅ |
| 16 | Backup history protected from on-box credential compromise | 4.1 | 1814 | backups | E11.180 | Versioned bucket + prefix-scoped IAM (no version-delete right); restic's weekly `forget --prune` needs `s3:DeleteObject`, so the bucket is **NOT** Object-Locked | bucket versioning capture; 90-day noncurrent-version recovery via account creds | ⚠️ |
| 17 | Encryption at rest (swap ✅; data volumes/disk pending) | 4.1 | crypto ch. | — | E11.140 | encrypted swap (random key per boot) | `lsblk`/crypttab capture | ⚠️ B1.2–3 — next provision; **mandatory before health data** |
| 18 | Host-down alerting (external dead-man's switch) | — | — | — | Std 7 | `vps-deadman.timer` — **required by provisioning** (explicit opt-out only) | monitor history; notify-role gate | ✅ |
| 19 | Web/DB tier separation; **per-app proxy-network exclusivity** | 4.1 | 1269–1271 | — | E11.130 | generated per-app networks + compose-audit gates | `reports/compose-audit-*` (`proxy_network_exclusive`, db controls) | ✅ (A8 label-based DB detection pending) |
| 20 | Whole-of-box recovery: encrypted offsite secret bundle + rebuild drill + RTO log | 4.1 | — | — | Std 7 | `make-recovery-bundle.sh` + scaffold docs/09 | bundle generated 2026-07-06; full wipe+rebuild drill PASS, RTO ~63 min in docs/09 RTO log | ✅ |
| 21 | Asset register with BILs | — | — | — | Std 2 | [information-asset-register.md](information-asset-register.md) | the register | ✅ (this pack) |
| 22 | Hosting jurisdiction documented with HPP 9 ground | 9 | — | — | Std 8 | [hosting-jurisdiction-record.md](hosting-jurisdiction-record.md) | the record | ✅ (n/a ground; migration tripwire recorded) |
| 23 | Retention/deletion honours 7-year/age-25 + deletion logs | 4.2–4.4 | — | — | — | [retention-deletion-design.md](retention-deletion-design.md) | app deletion logs (n/a — no health records) | ✅ (stance documented) |
| 24 | Incident response incl. DH 1-hour pathway | — | — | — | Std 6 | [incident-response-runbook.md](incident-response-runbook.md) + scaffold docs/11 | runbook; annual test record | ⚠️ DH tree dormant until commissioning; first tabletop pending |
| 25 | Quarterly access review | 4.1 | — | restrict admin | E11.120 / Std 4 | [access-review.md](access-review.md), prompted by maintenance-day issue | dated entries | ✅ (log started) |
| 26 | Secrets handling: 0600 files, AIDE-monitored, encrypted offsite copies, documented rotation | 4.1 | 1449 analog | — | E11.150 | `.env` pattern + recovery bundle + env-files restic | recovery-bundle generated 2026-07-06; `restic snapshots --tag env-files-files` | ✅ |
| 27 | EDR or documented compensating controls | — | — | — | — | auditd+AIDE+real-time ntfy+Trivy+watchers stack | this matrix + audit bundle; written acceptance only if operated for a health service | ➖ C2 — health-service context only |
| 28 | Supply-chain: SHA-pinned actions, CodeQL, Scorecard, gitleaks, branch protection | — | 1409 supply | — | Std 8 | `.github/` workflows + CODEOWNERS + gitleaks secret-scan | Scorecard report; CI runs; branch-protection API capture | ✅ (branch protection on: required checks, force-push/deletion blocked, enforce-admins; `require-code-owner-review` deferred — solo maintainer can't self-approve) |

**Version note (2026-07-05):** measurement of record is CIS Ubuntu 24.04
**v1.0.0** (SSG profiles) and CIS Docker **v1.6.0** (docker-bench) — version
lag tracked in the scaffold exceptions register.
