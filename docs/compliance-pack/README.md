# Compliance pack — worked example (staging reference instance)

This is the scaffold's `docs/templates/` set **filled in for this template's
staging reference instance**: a single VPS run by an *employed* clinician,
hosting only the bundled operational apps (ntfy; auth disabled), holding **no
health information — with no intention of ever hosting patient data on this
stack** (see the standing-intent note in the scope determination). It exists so that (a) the staging box itself has an
honest, complete evidence pack, and (b) a real deployment starts from a
worked example instead of blank angle brackets.

**For a real deployment:** copy this directory in your (private) instance
repo, re-answer [scope-determination.md](scope-determination.md) first — it
decides how much of the rest is mandatory — then re-fill every field marked
`⟨fill at commissioning⟩`. Commit the results; the git history is the review
trail. The gitignored `compliance/` directory remains for raw evidence dumps
that should never reach a public fork.

**The one rule that runs through every document here:** the moment any app on
an instance holds identifiable health information, the substantive
requirements activate — hosting jurisdiction (AU region), TOTP, at-rest
encryption, retention discipline — plus the DH incident clock if the system
operates for a health service. Each document marks its own tripwire. The
pack's purpose is that the system meets the privacy and security requirements
*demonstrably, on its merits* — a standard the paper-and-spreadsheet status
quo it replaces never meets.

| Document | Status for staging |
|---|---|
| [scope-determination.md](scope-determination.md) | Complete — most frameworks dormant (no health data, employed operator) |
| [information-asset-register.md](information-asset-register.md) | Complete — highest class OFFICIAL (operational data only) |
| [system-security-plan.md](system-security-plan.md) | Complete |
| [vic-health-control-matrix.md](vic-health-control-matrix.md) | Complete — current control statuses |
| [hosting-jurisdiction-record.md](hosting-jurisdiction-record.md) | Complete — US hosting recorded as acceptable *only* while no health data |
| [retention-deletion-design.md](retention-deletion-design.md) | Complete — platform stance; no health records held |
| [incident-response-runbook.md](incident-response-runbook.md) | Complete — DH tree dormant until commissioning |
| [access-review.md](access-review.md) | Log started; quarterly entries prompted by the maintenance-day issue |
