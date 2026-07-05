# Retention & deletion design — staging reference instance

HPP 4.2 (Health Records Act 2001 Vic): a health service provider must not
delete health information earlier than **7 years after the last service — or,
for information collected while the individual was under 18, until they turn
25 — whichever is later**. HPP 4.3 requires deletions to be logged; HPP 4.4
requires transfer logging. (Under-18 collection is the norm, not the edge
case, for paediatric workloads — age-25 will usually be the binding rule.)

## The platform stance (one paragraph an auditor can accept)

The **application database is the record of record**; retention obligations
attach to it, not to backup copies. restic's snapshot pruning
(default keep 7 daily / 4 weekly / 6 monthly) is *copy lifecycle management* —
it discards redundant snapshots of data that still lives in the database, so
it is not a HPP 4.2 deletion. A HPP 4.2 deletion happens only at application
level, is subject to the 7-year/age-25 rule, and must produce a deletion log.
The invariant: **no snapshot prune may ever remove the only remaining copy of
undeleted health information** — which holds automatically while the live
database retains the record.

## Per-app retention

No app on this instance holds health records; the health-record row below is
the pattern a clinical app must fill before deployment.

| App | Record types | Retention rule | Deletion mechanism | Deletion log |
|---|---|---|---|---|
| ⟨clinical app — none deployed⟩ | ⟨clinical records⟩ | 7yr/age-25 (HPP 4.2) | ⟨app admin function; if none, records are kept indefinitely — state that⟩ | ⟨where the app writes HPP 4.3 logs⟩ |
| ntfy | host security alerts | operational (cache-pruned by ntfy) | automatic cache expiry | n/a (not health records) |
| auth service (disabled) | accounts, session data | operational — removed when access revoked | admin removal + key rotation | [access-review.md](access-review.md) entries |
| host logs | auditd/auth/access | 12 months (ISM-1988), Object-Locked | bucket lifecycle after lock expiry | n/a (not health records) |

## Decommissioning

On instance retirement: final backup verified via restore drill → records
transferred/archived per HPP 4.4 (logged — n/a while no health records) →
volumes wiped (provider destroy + crypto-erase once at-rest encryption lands;
swap is already random-key encrypted per boot) → restic repository retained or
destroyed per the same retention rule → this record updated with dates.

**Owner:** repo owner · **Last review:** 2026-07-05
