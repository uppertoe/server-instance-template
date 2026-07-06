# System Security Plan — staging reference instance

**System owner / operator:** repo owner (employed specialist clinician;
personal infrastructure) · **Last review:** 2026-07-05
**Scaffold version:** `vps-base-template @` the `scaffold/` submodule pointer
in this repo — the exact hardening code applied to this host, resolvable per
commit.

## 1. Purpose and scope

A hardened single-VPS platform for small web applications, run as the staging
reference for the `server-instance-template`. Apps hosted: ntfy (self-hosted
destination for the host's own security alerts; loopback publish + optional
authenticated public subscription) and the email-OTP auth gateway (disabled).
**No health information is held** — see the
[asset register](information-asset-register.md) and
[scope determination](scope-determination.md). Highest classification:
OFFICIAL: Sensitive (credentials, operator-identifying logs).

## 2. Architecture

Single Ubuntu 24.04 LTS VPS (2 GB) · Docker Compose stack assembled by
`include:` from the scaffold's Caddy base + per-app compose files · Caddy
terminates TLS on 80/443 — the only published ports (plus loopback-bound
ntfy for on-host publishing) · **per-app private proxy networks**, generated
into a committed bundle: Caddy joins every `<app>_proxy` network, each app
only its own, so apps cannot reach each other or forge the `Remote-*`
identity headers; the runtime audit fails if two apps ever share a
Caddy-reachable network · container egress restricted to the host's outbound
port allowlist (DOCKER-USER chain) · restic client-side-encrypted backups to
S3 (versioned, **not** Object-Locked — restic prune needs delete rights; see
control-matrix row 16) · journald/audit/access logs exported to a write-only
Object-Locked S3 bucket (≥12 months) · ntfy alerting with an **external
dead-man's-switch monitor (required by provisioning)**, disk/container-health
watchers, post-reboot health reports, a monthly alert self-test, and a weekly
security digest as the automated log review.

Hosting: RackNerd, United States — lawful-basis position and the
migration tripwire in the
[hosting jurisdiction record](hosting-jurisdiction-record.md).

## 3. Control inventory

The complete control → implementation → evidence map is the
[control matrix](vic-health-control-matrix.md). Defensibility chain for the
OS baseline (ISM-1409): the ISM requires ASD **and vendor** hardening
guidance; Canonical's vendor tooling for Ubuntu (USG) implements the CIS
benchmark, so the scaffold enforces and measures **CIS Ubuntu 24.04 Server**
(L1, with the **L2 profile enabled on this host**), verified by OpenSCAP with
a documented tailoring file, plus CIS Docker §1–4 (docker-bench) and §5
(compose audit) at the container layers.

## 4. Deliberate exceptions

Maintained in the scaffold's exceptions register
(`scaffold/docs/08-security-model.md`): cloud-N/A CIS rules, public
reverse-proxy ports, UFW-over-nftables, benchmark version lag. Per-instance
exceptions: none.

## 5. Cryptography

In transit: TLS via Caddy/ACME (external), SSH ed25519/ETM-only MACs (admin).
At rest: restic AES-256 for backups (client-side, before upload); swap is
random-key encrypted per boot; **root filesystem and data volumes are not yet
encrypted at rest** (compliance plan B1.2–3 — scheduled for the next
provision, and mandatory before any health information). **PQC posture:**
cryptography is delegated to Caddy/OpenSSH/restic upstream defaults;
migration to ML-KEM/ML-DSA suites follows Ubuntu LTS and upstream releases,
reviewed at each annual SSP review, target completion before the ASD 2030
deadline.

## 6. Access

Model: `scaffold/docs/05-access-model.md` — **restricted mode on**: `deploy`
is wrapper-only sudo with no docker group; `admin` is break-glass. The
repo-to-root boundary (merge rights = root via the deploy path) is documented
there. It is currently guarded by the 3-day automerge cooldown + required CI
checks; `require-code-owner-review` is **not** enabled (a solo maintainer
cannot self-approve, which would deadlock merges), so CODEOWNERS is advisory
until a second reviewer exists. The optional `deploy_verify_signature` gate
(refuse an unsigned HEAD at deploy) is the technical backstop for this boundary.

| Access | Who | Factor(s) | Reviewed |
|---|---|---|---|
| SSH (`deploy`, `admin`) | operator (sole) | ed25519 key, passphrase-protected | 2026-07-05 |
| App admin (auth tier) | — (disabled) | email OTP (+ TOTP at commissioning) | 2026-07-05 |
| Backup / log-export S3 | on-host root config | prefix-scoped / write-only IAM | 2026-07-05 |
| GitHub (merge = root boundary) | operator (sole) | 2FA (TOTP) enforced; branch protection on (force-push/deletion blocked, required checks); require-code-owner-review pending a second reviewer | 2026-07-05 |

Secrets: gitignored `.env`/inventory files at mode 600, AIDE-monitored,
encrypted offsite copy via `scripts/make-recovery-bundle.sh`, rotation on
personnel change or ≤12 months. Quarterly review:
[access-review.md](access-review.md).

## 7. Assessment history

| Date | Assessment | Result | Report |
|---|---|---|---|
| 2026-07-04 | OpenSCAP CIS L1+L2 (tailored), docker-bench, compose audit, Lynis, Trivy — `audit-all.yml` bundle | pass with registered exceptions | `reports/*-rch-vps-<date>/` (local) + CI evidence page |
| 2026-07-04 | Restore drill | PASS (RPO/RTO recorded) | `/var/lib/backup-drill/latest.txt` |
| 2026-07-05 | Adversarial security review (A1–A11) + remediation | high-risk findings closed; A8 + A5-residual open | `scaffold/docs/adversarial-security-audit-2026-07-05.md` |
| ⟨at commissioning⟩ | Independent review / pen test | — | — |
