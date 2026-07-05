# Hosting jurisdiction record — staging reference instance

HPP 9 (Health Records Act 2001 Vic) treats storing health information with a
provider **outside Victoria** as a transborder transfer needing a documented
ground under HPP 9.1(a)–(g). This record is that documentation. Keep it
current — it is the first artifact a privacy review requests.

## Where the data physically is

| Component | Provider | Provider ownership/HQ | Region/location | Notes |
|---|---|---|---|---|
| VPS | RackNerd | US-owned | United States | budget VPS; no IRAP/HCF assessment |
| Backups (restic) | AWS S3 | US-owned | ⟨bucket region — record per instance⟩ | client-side encrypted (restic AES-256) before upload; Object Lock on |
| Log export | AWS S3 (Object-Locked bucket) | US-owned | ⟨bucket region⟩ | write-only IAM user; journald/audit/access logs |
| Transactional email | ⟨SMTP relay — fill when auth enabled⟩ | — | — | OTP emails contain addresses, no clinical data |
| External monitor | self-hosted status service (operator-controlled) | — | ⟨region⟩ | receives heartbeats only, no payload data |
| DNS / registrar | ⟨registrar⟩ | — | — | metadata only |

Administration is performed from: Australia only.

## Lawful basis (HPP 9.1 ground)

**Not required — and deliberately so.** This instance holds **no health
information** (see the [asset register](information-asset-register.md)), so
HPP 9 is not engaged. US hosting is recorded as acceptable **only under that
condition**.

**Tripwire (binding on future changes):** before any app holding identifiable
Victorian health information is deployed, this record must be re-made, and
the defensible default is **migration to an Australian-region provider**
(ideally IRAP-assessed) relying on 9.1(a) — see compliance plan C1. A 9.1(f)
contract-plus-controls position on a US budget host would be weak (no DPA,
foreign-owned, no at-rest encryption yet) and is **not** the plan. The backup
and log bucket regions count as transfer destinations and move with it.

**Ground relied on:** n/a (no health information held) · **Assessed by:**
repo owner · **Date:** 2026-07-05

## Constraints acknowledged

- My Health Record data is **never** hosted here (MHR Act s 77 hard onshore
  prohibition — consent cannot override it).
- Backup and log bucket regions count as transfer destinations in their own
  right.
- Provider changes re-open this record before migration, not after.
