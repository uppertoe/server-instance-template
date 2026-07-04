# Scope determination — ⟨host⟩

Which frameworks bind this instance, decided once and revisited when the
operating relationship changes. Sources: PDP Act 2014 (Vic) ss 84, 88;
Health Records Act 2001 (Vic); DH Policy & Funding Guidelines §24; SOCI Act;
Privacy Act 1988 (Cth). Background: docs/compliance-plan-vic-health.md §1.

| Question | Answer | Consequence |
|---|---|---|
| Does the system hold **health information** collected in Victoria? | **No.** By design: no identifiable health information is stored, processed, or transmitted by any app on this host. This is a hard design constraint (US hosting makes it HPP 9-load-bearing), re-assessed before every new app. | HRA HPPs apply directly (HPP 4 security/retention, HPP 9 transborder) — regardless of public/private status |
| Is the operator a **contracted service provider to a PDP Act Part 4 body** (e.g. the Department of Health — public health services themselves are excluded by s 84(2))? | **No.** No contract with any PDP Act Part 4 body exists. | If yes: VPDSS flows down via s 88(2) → SRPA + PDSP + attestation artifacts required (PDSP window: Jul–Aug of even years) |
| Is the system operated **for/within a public health service** subject to the DH Policy & Funding Guidelines? | **No.** Personal project of a clinician; not operated for, endorsed by, or integrated with any health service. | If yes: DH Baseline Cybersecurity Controls + VMIA self-assessment + §24.4 one-hour incident reporting apply; supplier risk sits with the health service |
| Is the host part of a **SOCI-designated critical hospital's** infrastructure? | **No.** | If yes: CIRMP obligations (E8 ML1 / ISO 27001 / equivalent, annual board report) |
| Does any app handle data for a **private practice** (APP entity)? | **No** at present. Trigger for review before any such app deploys. | If yes: Privacy Act 1988 + Notifiable Data Breaches scheme |
| Does anything connect to **My Health Record**? | **No — and by design never will on this host** (s 77 onshore mandate is incompatible with US hosting). | If ever yes: s 77 onshore mandate + ADHA conformance — out of scope for this platform |

**Determination (2026-07-05, instance rch-vps):** No Victorian health-privacy
instrument binds this instance today because it holds no health information and
serves no health service. The full WS-A artifact set is nonetheless maintained
as **best practice and scrutiny-readiness**: the platform is built and evidenced
to Victorian health standards (see `../scaffold/docs/08-security-model.md` and
`../reports/`) so that IF a future app changes any answer above, the mandatory
artifacts are already true rather than aspirational. The no-PHI constraint is
the load-bearing condition of US hosting and of the operate-first posture.

**Made by:** ⟨name⟩, operator · **Date:** 2026-07-05 · **Review trigger:** new contract,
new app, new data class, or organisational change.
