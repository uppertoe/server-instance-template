# Scope determination — staging reference instance

Which frameworks bind this instance, decided once and revisited when the
operating relationship changes. Sources: PDP Act 2014 (Vic) ss 84, 88;
Health Records Act 2001 (Vic); DH Policy & Funding Guidelines §24; SOCI Act;
Privacy Act 1988 (Cth). Background: scaffold docs/compliance-plan-vic-health.md §1.

| Question | Answer | Consequence |
|---|---|---|
| Does the system hold **health information** collected in Victoria? | **No.** Apps: ntfy (host security alerts), auth service (disabled; would hold operator email only). No clinical apps deployed. | HRA HPPs dormant. **Tripwire: the first app holding any identifiable health information re-opens this whole pack** — jurisdiction record and commissioning first. |
| Is the operator a **contracted service provider to a PDP Act Part 4 body**? | **No.** The operator is an *employed* specialist clinician at a Victorian public health service, not a contractor supplying services to the Department or a Part 4 body. No relevant contract exists. | VPDSS s 88(2) flow-down does **not** apply to the operator; no SRPA/PDSP/attestation obligation (the Jul–Aug 2026 PDSP window is not ours to meet). |
| Is the system operated **for/within a public health service** subject to the DH Policy & Funding Guidelines? | **Not currently.** Staging is personal infrastructure holding no health-service data. | Dormant. **If an instance is to support employment duties with patient data, it must be commissioned through the health service's digital/security governance first** — an employee-built system holding patient data outside that governance is shadow IT, whatever its hardening. On commissioning: DH Baseline Controls, VMIA self-assessment, and the §24.4 one-hour incident clock activate, with supplier-risk questions answered by this pack. |
| Is the host part of a **SOCI-designated critical hospital's** infrastructure? | **No.** Personal VPS, not hospital infrastructure. | No CIRMP obligations. Re-ask at commissioning. |
| Does any app handle data for a **private practice** (APP entity)? | **No** (operator currently in salaried practice only). | Privacy Act/NDB dormant. **Tripwire: any private-rooms app (billing, bookings, notes) makes the operator an APP entity** — NDB scheme and APP 11 apply from the first record. |
| Does anything connect to **My Health Record**? | **No — and never on this platform.** | s 77 onshore mandate + ADHA conformance are out of scope by design. |

**Determination:** while the instance holds no health information and the
operator acts privately, the binding obligations are ordinary lawful conduct
plus good practice; the WS-A artifacts in this pack are maintained as
*reference implementations*, not regulatory requirements. The mandatory set
activates at whichever comes first: (a) an app holding identifiable health
information, (b) commissioning by/for a health service, or (c) a private
practice app.

**Made by:** repo owner (employed specialist clinician) · **Date:** 2026-07-05 ·
**Review trigger:** new app, new data class, commissioning discussion,
private-practice use, or organisational change.
