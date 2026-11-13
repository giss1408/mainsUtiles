# Jobber verification — design

Date: 2026-11-13. Product spec: `skill.md` (sections 3 "Guarantor", 4 "Trusted contacts", 5 "Usability rules").
Builds on householder verification and job offers. This is piece 3 of 4, split in two plans.

## Goal

A mini-jobber proves who they are and who vouches for them, staff confirm it, and the account reaches
tier **J1**. J1 is the condition for applying to offers, which comes after this piece. Until J1 the
jobber keeps browsing offers (tier J0), as the spec requires.

## Decisions already taken

- **Two plans.** 3a: identity and guarantor. 3b: trusted contact and safety briefing. Each ships
  working and tested on its own.
- **J1 is configuration, not code.** The setting `JOBBER_REQUIRED_STEPS` lists the steps that must be
  confirmed. 3a sets it to identity and guarantor; 3b adds trusted contact and briefing.
- **Identity is checked by staff from photos**, exactly as for householders (same service, same console
  queue, same retention and encryption). One identity document backs one account, across both roles.
- **The safety briefing is text cards plus a confirmation question**, edited by staff in the web console,
  until the learning videos exist. The first cards are placeholders the product owner replaces.
- **Applications are not built here.** Nothing enforces J1 yet; the tier is computed and shown.

## Out of scope

- Applications, bookings, payment. Enforcement of J1 on them.
- Service area (commune) declared by the jobber; tier J2.
- Linked-account detection (guarantor, bill or phone shared across accounts); banned-guarantor rule.
  These need bookings to mean anything and are recorded in the threat model as open.
- Automated call to the guarantor; real SMS. Staff phone the guarantor; SMS goes through the mock.
- Liveness check. A person compares the selfie with the document, as for householders.

## Plan 3a — identity and guarantor

### Backend

- `submit_identity` accepts a jobber as well as a householder. The role check becomes
  "householder or jobber"; address proof and home location stay householder-only.
- **Guarantor** (new model, reviewed like the others, in `apps/verification`):

  | Field | Notes |
  |-------|-------|
  | `photo` | The bill, a `VerificationPhoto` of a new kind `guarantor_bill` |
  | `document_type` | One of `GUARANTOR_DOCUMENT_TYPES` (configuration) |
  | `guarantor_name`, `guarantor_phone` | Typed by the jobber; stored encrypted |
  | `guarantor_phone_hash` | Keyed hash, to compare with the jobber's own number and to count |
  | `relationship` | parent, relative, landlord, other |
  | `holder_name`, `reference_number`, `reference_hash`, `issued_on` | Recorded by staff from the bill; encrypted except the hash and date |
  | `contacted_at`, `contacted_by` | Set when staff record the call |
  | `confirmed_at`, `expires_at` | Expires after `GUARANTOR_VALID_MONTHS` |

  Status values are the existing ones (submitted, in review, confirmed, refused, expired). The spec's
  "contacted" is the `contacted_at` timestamp on an in-review record.
- **Submission rules:** the guarantor's phone is a valid Ivorian number and is not the jobber's own;
  the jobber has no other open guarantor record; the photo passes the same checks as other photos.
- **Confirmation rules** (service, never the view): the identity is already confirmed; the call has been
  recorded; the staff member ticked that the name on the bill matches the stated name and that the
  guarantor knows the jobber and agreed to be contacted; the bill is not older than
  `GUARANTOR_BILL_MAX_AGE_MONTHS` and not dated in the future; the bill reference backs at most
  `GUARANTOR_MAX_JOBBERS` jobbers (default 3). Every decision, view and call record leaves an audit row.
- **Console:** a "Garants" review queue in the web console for the existing `verification_agent` group,
  with the bill photo, the call action, and confirm/refuse with a reason shown to the jobber.
- **API** (jobber only, `IsJobber`): `GET /api/v1/jobber/verification` (checklist),
  `POST .../identity`, `POST .../guarantor` (multipart). Statuses only in every response: never the
  guarantor's name or phone, the bill, or any identity field.
- **Tier:** `jobber_tier(user)` is J1 when every step in `JOBBER_REQUIRED_STEPS` is confirmed, otherwise J0.
  An hourly task expires guarantors past their date, as for address proofs.

### Jobber app

- A **Vérification** card at the top of the Offres screen shows progress ("1 étape sur 2") and opens
  the checklist. Browsing is never blocked.
- The checklist and the identity and photo screens are the householder ones, driven by the role's API
  base path; the copy is in the informal "tu" for the jobber.
- **Guarantor flow:** one step per screen with "Étape x sur y": who vouches (name, phone, relationship),
  the bill photo with the in-app camera only, summary, sent. A privacy note says what happens: we
  phone your guarantor, we use the number only for this, and the bill is seen only by verification staff.
- The Profil trust card shows real badges for the confirmed steps ("Identité vérifiée",
  "Garant confirmé") and nothing it has not earned.

### Tests

Backend: permission failures for every endpoint (householder, anonymous, other jobber, staff token);
submission and confirmation rules including each refusal code; encryption (no plain name or phone in
the database); the guarantor's data absent from every response; one open record per jobber; reference
cap; expiry; audit rows; tier with each step missing. Mobile: controller states, each flow screen, the
card on Offres, badges on Profil, and 320dp at twice the text size.

## Plan 3b — trusted contact and safety briefing

- **Trusted contact:** name, phone, relationship; stored encrypted. The server sends a code by SMS
  (mock provider) to the contact; the jobber types the code the contact reads out, which records
  acceptance once. Up to `TRUSTED_CONTACTS_MAX` (default 2), at least one confirmed. The contact's phone
  may not be the jobber's own or the guarantor's. Changing a contact later has a cooling-off delay
  (configuration) with notice to the old number.
- **Safety briefing:** `BriefingCard` (title, short body, question, choices, correct choice, order,
  active) edited in the console; `BriefingCompletion` per jobber and card. A wrong answer shows the
  explanation and allows a retry; all active cards answered correctly confirms the step. If staff add a
  card later, existing J1 jobbers keep J1 and see it as a new card.
- The checklist gains the two steps; `JOBBER_REQUIRED_STEPS` gains `trusted_contact` and `briefing`.

## Open decisions for the business

- Lawful basis for holding a guarantor's name, phone and bill, who is not a user and has not agreed
  to our privacy notice. The jobber's app copy and the privacy notice must say so; a lawyer reviews it.
- The call script and the official number staff call from; the cap of jobbers per bill.
- Bills accepted from guarantors without a utility bill (prepaid meter, certificate).
- Content of the briefing cards, until the learning videos exist.
