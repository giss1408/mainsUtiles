# Householder verification (direct route) — design

Date: 2026-11-12. Product spec: `skill.md` (sections 3, 4 and "Security and privacy").

## Goal

A householder can prove who they are and where they live, staff confirm it, and the account reaches
tier **H1**. H1 is the condition for publishing job offers, which is the next piece of work.

This is the first of four pieces agreed with the product owner:

1. Householder verification, direct route (this document).
2. Job offers: creation, moderation, browsing by jobbers. Publishing requires H1.
3. Jobber verification (identity, guarantor, trusted contact, safety briefing), before applications
   and bookings.
4. Third-party bill route, and the mobile-money name match once a payment provider is chosen.

## Decisions already taken

- **Scope:** householders only; the proof of address must be in the householder's own name (water or
  electricity bill, or certificat de résidence).
- **Identity check:** done by staff from photos taken in the app, because no identity provider is
  contracted. Photos are stored by us, encrypted. Whether we may lawfully hold identity photos is an
  open data-protection decision for the product owner; it must be settled before launch.
- **No liveness check** in this piece. A person compares a selfie with the document.

## Out of scope

- Third-party bill route; mobile-money account name match.
- A real identity provider, automated document checks, liveness.
- Reviewing verifications from the staff mobile app (web console only).
- More than one address per householder.
- On-device blur and glare detection; resumable chunked uploads.
- Push or SMS when a decision is made. The app shows the new status when opened or refreshed.
- A free-text "reason for access" prompt and second-staff approval in the console. Views are logged
  automatically; the prompts belong to the console-hardening work.
- Any change to the jobber app.

## The three steps

A householder completes three steps, in any order, each reviewed on its own.

| Step | What the householder provides | What staff record |
|------|-------------------------------|-------------------|
| Identity | Photo of the document front, photo of the back, selfie | Full name, date of birth, document type, document number, expiry date |
| Proof of address | Document type, one photo, commune (from a list), quartier (typed) | Holder name, customer or reference number, issue date; two confirmations (below) |
| Home location | GPS position recorded at home | Nothing; staff use it when judging the proof of address |

### Status of a step

`not_started → submitted → in_review → confirmed | refused`; a confirmed proof of address can
become `expired`.

- `submitted`: the householder has sent everything the step needs.
- `in_review`: a staff member has opened it. Set automatically on first opening.
- `refused`: staff give a reason, shown to the householder. The householder may start the step
  again, which creates a new submission; the refused one is kept for the record.
- A step that is `submitted`, `in_review` or `confirmed` cannot be sent again by the householder.
- The home location has no staff decision of its own: it is `submitted` once recorded, and becomes
  `confirmed` or `refused` together with the proof of address, because staff judge them together.
  Recording a new location is allowed until the proof of address is confirmed.

### Tier

The tier is computed, never stored or set by hand:

- **H1** when identity is `confirmed`, proof of address is `confirmed` and not expired, and the home
  location is `confirmed`.
- **H0** otherwise.

## Rules enforced by the server

All limits are settings read from the environment, with these defaults.

| Rule | Setting | Default |
|------|---------|---------|
| Householder must be an adult at the time of the decision | `MINIMUM_AGE_YEARS` | 18 |
| The identity document must not be expired at the time of the decision | — | — |
| One identity document number backs one account | — | — |
| One bill customer number or certificate reference backs one householder | — | — |
| Proof of address issued recently | `ADDRESS_PROOF_MAX_AGE_MONTHS` | 3 |
| Proof of address stays valid, counted from confirmation | `ADDRESS_PROOF_VALID_MONTHS` | 12 |
| Home location accuracy required | `HOME_PIN_MAX_ACCURACY_M` | 50 |
| Photo size limit | `VERIFICATION_PHOTO_MAX_BYTES` | 3 000 000 |
| Communes offered in the list | `SERVICE_COMMUNES` | Abobo, Adjamé, Anyama, Attécoubé, Bingerville, Cocody, Koumassi, Marcory, Plateau, Port-Bouët, Songon, Treichville, Yopougon |
| Accepted identity documents | `IDENTITY_DOCUMENT_TYPES` | `cni`, `passport`, `carte_consulaire`, `permis` |
| Accepted proofs of address | `ADDRESS_PROOF_TYPES` | `facture_eau`, `facture_electricite`, `certificat_residence` |

- A decision that breaks a rule is refused with a clear message to the staff member; nothing changes.
- To confirm a proof of address, staff must tick both: "the name matches the confirmed identity" and
  "the address is consistent with the commune, quartier and home location". Identity must already
  be confirmed, and a home location must have been recorded.
- A home location reported by the phone as coming from a fake-GPS app is accepted and flagged
  (`mock_location`) for staff. A location with accuracy worse than the limit is refused with
  "Position trop imprécise. Rapprochez-vous d'une fenêtre ou sortez, puis réessayez."
- A periodic task marks confirmed proofs of address `expired` once their validity has passed. The
  account then computes as H0 and the step can be started again.
- Photos must be JPEG and within the size limit. Each records the capture time sent by the app and,
  when the app has it, the capture position.

## Storage and privacy

- Photos are encrypted before they are written to disk and are never served as static files. Only
  one console view returns them: it checks the permission, decrypts in memory, sets
  `Cache-Control: no-store`, and writes an audit row (`verification.view_photo`) each time.
- Sensitive fields are encrypted in the database: full name, date of birth, document number, holder
  name, customer or reference number, home coordinates.
- Duplicate detection uses a keyed hash of the normalised number (upper case, no spaces or
  punctuation), so numbers are never stored or compared in plain text.
- One key, `FIELD_ENCRYPTION_KEY`, comes from the environment. With `DEBUG` off the backend refuses
  to start without it, as it already does for `SECRET_KEY`. Key rotation is not built here.
- The commune and quartier are stored in plain text: they are what jobbers will later see on offers.
- Nothing from this app is ever returned to a jobber. The householder's own API returns statuses,
  the commune and quartier, and refusal reasons; never the recorded identity fields, never photos,
  never coordinates.
- Logs never contain photo bytes, document numbers, names or coordinates.

## Backend

A new Django app, `apps/verification`. Business rules live in its services; views and admin classes
only call them.

### Models

- `VerificationPhoto`: owner, `kind` (`id_front`, `id_back`, `selfie`, `address_proof`), encrypted
  file, SHA-256 of the original image (to detect the same image reused across accounts, raised as a
  flag for staff), `captured_at`, optional capture position (encrypted), `created_at`.
- `IdentityVerification`: user, status, the three photos, `document_type`, encrypted `full_name`,
  `date_of_birth`, `document_number`, `document_number_hash`, `document_expires_on`, `flags`,
  `reason`, `reviewed_by`, `reviewed_at`, `created_at`.
- `AddressProof`: user, status, photo, `document_type`, `commune`, `quartier`, encrypted
  `holder_name` and `reference_number`, `reference_hash`, `issued_on`, `confirmed_at`, `expires_at`,
  `flags`, `reason`, `reviewed_by`, `reviewed_at`, `created_at`.
- `HomeLocation`: user, status, encrypted latitude and longitude, `accuracy_m`, `mock_location`,
  `captured_at`, `created_at`.

A user has at most one open (`submitted`, `in_review` or `confirmed`) record of each kind, enforced
by a database constraint. The uniqueness of `document_number_hash` and `reference_hash` among
confirmed records is also a database constraint.

### Services

- `encryption`: encrypt and decrypt bytes and text; keyed hash. Uses the `cryptography` package
  already installed.
- `submissions`: `submit_identity`, `submit_address_proof`, `record_home_location`; each checks the
  role, the open-record rule and the input, and stores the photos.
- `review`: `open_for_review`, `confirm_identity`, `refuse_identity`, `confirm_address`,
  `refuse_address`, `read_photo`; each checks the staff permission, locks the row, applies the
  rules above, and writes an `AdminAction`.
- `tiers`: `householder_tier(user) -> "H0" | "H1"` and the checklist shown to the app.
- Identity sits behind the existing `IdentityProvider` interface. The interface is extended so that
  a provider receives the submitted photos and returns a result that may be "pending human review";
  the implementation used now, `StaffReviewIdentity`, always returns that. A real provider replaces
  it later without changing the app or the review rules.

### API (householder token only; any other role gets 403)

- `GET /api/v1/verification` → `{tier, communes, identity: {status, reason}, address: {status,
  reason, commune, quartier, expires_at}, home_location: {status, reason}}`.
- `POST /api/v1/verification/identity` (multipart: `document_type`, `front`, `back`, `selfie`,
  `captured_at`, optional `lat`, `lng`) → the checklist.
- `POST /api/v1/verification/address` (multipart: `document_type`, `photo`, `commune`, `quartier`,
  `captured_at`, optional `lat`, `lng`) → the checklist.
- `POST /api/v1/verification/home-location` (`lat`, `lng`, `accuracy_m`, `mock_location`,
  `captured_at`) → the checklist.
- Errors use the existing shape `{error, message}` with French messages: `invalid_state` (409) when
  the step is already open, `photo_invalid` (400), `photo_too_large` (413), `commune_invalid` (400),
  `location_inaccurate` (422).

### Web console

- A new section "Vérifications" with two queues: identities and proofs of address, oldest first,
  filtered on `submitted` and `in_review` by default.
- The identity page shows the three photos side by side and the form for the recorded fields, with
  "Confirmer" and "Refuser" (reason required).
- The proof-of-address page shows the photo, the commune and quartier, the home location (the
  coordinates, the accuracy, the fake-GPS flag, and a link that opens the point in a map), the
  confirmed identity name for comparison, the form, the two tick boxes, and "Confirmer" / "Refuser".
- New permissions `verification.review_verification` and `verification.view_verification_photo`,
  granted to a new group `verification_agent` created by a migration.
- Records are never edited through the generic admin form; every change goes through an action.

### Deployment

- Photos live in a directory set by `VERIFICATION_STORAGE_DIR`; in production this is a named
  Docker volume mounted in `web` only. `docs/deployment.md` gains the new variable, the volume, and
  the fact that a database backup without this volume and the key is incomplete.

## Householder app

- New dependencies in the householder app: `camera` (in-app capture) and `geolocator` (position).
  Android permissions: camera, fine location. No gallery access is requested.
- The verification screens live in `petitgombo_core` under `src/verification/`, with their own API
  class, controller and copy class, following the enrolment code. Only the householder app shows
  them; the jobber app is unchanged.
- The signed-in home screen of the householder app shows the checklist "Vérification de votre
  compte" with the three steps, each with its status in plain words and the next action:
  - not started → "Commencer"
  - `submitted` → "Envoyé. Nous vérifions sous 24 h."
  - `in_review` → "En cours de vérification."
  - `confirmed` → "Confirmé" with a check icon
  - `refused` → the reason, and "Recommencer"
  - `expired` → "Justificatif expiré. Envoyez-en un nouveau.", and "Recommencer"
  - When the tier is H1: "Compte vérifié".
- One step per screen, one primary action per screen:
  - Identity: choose the document type, then three capture screens (front, back, selfie) with a
    frame overlay and a review screen ("Reprendre" / "Utiliser cette photo"), then send.
  - Proof of address: choose the type, capture, choose the commune, type the quartier, send. A note
    reminds the user that the document must be in their own name and recent.
  - Home location: an explanation ("Faites cette étape chez vous."), one button "Enregistrer ma
    position", then the result.
- Photos are resized on the phone to at most 1600 pixels on the long side and saved as JPEG before
  upload. A failed upload keeps the photos in memory and offers "Réessayer"; nothing is written to
  the gallery or to permanent storage.
- Denied camera or location permission shows what to do and a button that opens the app settings.
- The checklist refreshes when the app returns to the foreground and on pull-to-refresh.
- All copy is French, in a `VerificationCopy` class, as for enrolment.

## Tests

Backend:

- Each endpoint: no token (401), jobber token (403), staff token (403), householder (allowed).
- A householder never sees another householder's data; the response never contains recorded
  identity fields, coordinates or photo locations.
- Every status change, including each invalid one (send twice, decide twice, decide a refused
  record, confirm the address before the identity).
- Under-18, expired document, duplicate document number, duplicate reference number, proof older
  than the limit, missing tick boxes: each refused with nothing changed.
- Two staff deciding the same record: one succeeds, one gets an invalid-state error, one audit row.
- Photos: stored bytes differ from the uploaded bytes; the console photo view answers 403 without
  the permission and writes one audit row per view with it; non-JPEG and oversized uploads refused.
- Tier: H1 only with all three confirmed; back to H0 after the expiry task runs.
- Settings: startup fails without `FIELD_ENCRYPTION_KEY` when `DEBUG` is off.

App:

- API class: request shapes and error mapping.
- Controller: checklist loading, each submission, refusal then retry, upload failure then retry.
- Screens: every checklist status, permission denied, and a 320dp screen at twice the text size.
  Camera and position are behind small interfaces so tests supply fakes.

Manual check on a phone: complete the three steps, confirm them in the console, see "Compte
vérifié"; refuse one and see the reason and "Recommencer".

## Threat model

`docs/threat-model.md` is updated: "Forged or reused documents" and "Lure listings" move from
planned to partly built, with what is and is not covered (no liveness, staff judgement only), and
"Data breach" notes the encrypted photos and fields.
