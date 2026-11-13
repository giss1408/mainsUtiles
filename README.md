# petitGombo

Safety-first mini-job marketplace. The product specification is in [skill.md](skill.md);
implementation plans are in [docs/superpowers/plans](docs/superpowers/plans).

## Layout

- `backend/` — Django API, staff web console (Django admin), Celery tasks.
- `mobile/packages/petitgombo_core` — shared Flutter code.
- `mobile/apps/householder`, `mobile/apps/jobber`, `mobile/apps/staff` — the three apps.
- `docs/threat-model.md` — threats, controls and their test status.
- `docs/deployment.md` — running the backend in production with Docker.

## Prerequisites

Docker, Python 3.13, Flutter 3.24 or later.

## Backend: first run

```bash
cp .env.example .env
docker compose up -d                      # PostgreSQL and Redis
cd backend
python3.13 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/python manage.py migrate
.venv/bin/python manage.py createsuperuser
.venv/bin/python manage.py runserver 0.0.0.0:8000
```

The web console is at http://localhost:8000/admin/ and the API schema at
http://localhost:8000/api/schema/.

## Tests and lint

```bash
cd backend
.venv/bin/pytest
.venv/bin/ruff check .
```

## Open decisions

These are not settled by the code and must be supplied by the business:

- Payment provider(s) and whether holding funds needs a licensed partner.
- Identity verification provider.
- SMS and call provider; the official WhatsApp Business number.
- Data-protection registration (ARTCI), biometric processing and hosting location.
- Lawful basis for holding identity photos and selfies ourselves. Until an identity provider is
  contracted they are stored by the backend, encrypted. This must be settled before launch.
- The in-app privacy notice ("Confidentialité et données") is a draft. The data controller, the
  contact address and the retention periods are placeholders in `LegalConfig`
  (`mobile/packages/petitgombo_core/lib/src/info/info_screens.dart`); the full terms of use are not
  written. Fill them in, have the notice reviewed by a lawyer, then set `LegalConfig.reviewed`.
- Ratings and reviews: the star and review components exist, but no rating is stored or shown until
  missions can be booked and completed.
- Labour status of mini-jobbers, insurance cover.
- Safety desk staffing and hours, incident protocol, police contact, emergency numbers.
- Trademark, domain and store availability of the name "petitGombo".

## Trying the enrolment flow by hand

Create an application as the app would:

```bash
curl -X POST http://localhost:8000/api/v1/enrolment/applications \
  -H 'Content-Type: application/json' \
  -d '{"phone":"07 08 09 10 11","role":"jobber","device_id":"11111111-1111-4111-8111-111111111111","device_model":"curl","platform":"android","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","client_token":"smoke-token"}'
```

Then open the web console, go to "Demandes d'enrôlement", approve the application and press
"Envoyer par WhatsApp". Staff members need the `enrolment_agent` group (superusers have every right).

## Mobile apps

Flutter 3.24 or later. The shared code is in `mobile/packages/petitgombo_core`; each app is a thin
entry point.

| App | Folder | Android id |
|-----|--------|------------|
| petitGombo (householders) | `mobile/apps/householder` | `com.regisse.petitgombo` |
| petitGombo Jobber | `mobile/apps/jobber` | `com.regisse.petitgombo.jobber` |
| petitGombo Staff | `mobile/apps/staff` | `com.regisse.petitgombo.staff` |

```bash
cd mobile/apps/jobber            # or mobile/apps/householder, mobile/apps/staff
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the host machine as seen from the Android emulator (the default when the option is
omitted). On a real phone use the computer's address on the local network and start the backend with
`runserver 0.0.0.0:8000`. Debug builds allow plain HTTP for this; release builds must use HTTPS.

Tests and analysis, in each of the four Dart packages (the core package and the three apps):

```bash
flutter test
flutter analyze
```

### Staff app

The staff app shows the enrolment queue (approve, refuse, hold, send the confirmation number by
WhatsApp) and, for staff with the right `verification.send_contact_code`, the trusted contacts queue
("À envoyer": send a code; "À prévenir": warn an old number). Both are sent by WhatsApp from this
app, on the phone that holds the official number; the contact's number is only ever inside the
one-time link, never shown or stored. It is distributed privately to the operations team, never through a public store, and it
blocks screenshots and screen recording.

A staff member signs in with a username, a password and a phone that an administrator has activated:

1. In the web console (`/admin/`), a superuser creates the staff account under "Utilisateurs" with the
   role "Personnel", "Statut équipe" ticked, and the `enrolment_agent` group.
2. The staff member opens the staff app and signs in. The first attempt registers the phone and shows
   "Appareil en attente d'activation par un administrateur."
3. The superuser opens "Appareils du personnel" in the web console, ticks the phone, and runs the
   action "Activer". A staff member has one active phone: activating a new one revokes the previous.
   "Révoquer" cuts a phone off immediately; a revoked phone registers again as a new device.
4. The staff member signs in again and reaches the queue.

The session is kept in memory only: closing the app signs out, and so do 12 hours without use. After 5
wrong passwords the account is locked for 15 minutes (`STAFF_LOGIN_MAX_FAILURES`,
`STAFF_LOGIN_LOCK_MINUTES`).

## Householder verification

A householder must be verified before publishing offers. After enrolment the householder app shows
a checklist, "Vérification de votre compte", with three steps:

1. **Pièce d'identité** — photos of the front and back of the document and a selfie, taken with the
   in-app camera (pictures cannot be picked from the gallery).
2. **Justificatif de domicile** — a water or electricity bill, or a certificat de résidence, in the
   householder's own name, with the commune and quartier.
3. **Position du domicile** — the GPS position, recorded once at home.

Staff review the first two in the web console, under "Vérifications": "Vérifications d'identité" and
"Justificatifs de domicile". The home position is judged together with the proof of address. When
all three are confirmed the account becomes tier H1 and the app shows "Compte vérifié".

To let a staff member review verifications, add them to the group `verification_agent` in the web
console ("Utilisateurs"). It is separate from `enrolment_agent`; superusers have every right.

What staff must know:

- The identity must be confirmed before the proof of address can be.
- The server refuses anyone under 18, an expired identity document, a document or customer number
  already used by another account, and a proof of address older than 3 months.
- A refusal needs a reason; the householder sees it and can start the step again.
- Every opening of a photo is recorded in the audit log.
- A confirmed proof of address expires after 12 months; the account then returns to H0 until a new
  one is confirmed.

Photos and sensitive fields are encrypted with `FIELD_ENCRYPTION_KEY`. In development a built-in key
is used and photos are written to `backend/verification_storage/` (git-ignored). The limits are
settings, listed in `.env.example` under "Householder verification".

Not built yet: the route for a bill in someone else's name, the mobile-money name match, automatic
document and liveness checks. Whether identity photos may lawfully be held
is an open decision (see "Open decisions").

## Jobber verification

A jobber is tier J0 until the steps named in `JOBBER_REQUIRED_STEPS` (default `identity, guarantor,
trusted_contact, briefing`) are confirmed, then J1. The jobber app shows a card on "Offres" ("Fais vérifier ton compte", with its
progress) that opens a checklist with four steps, written in "tu":

1. **Identité** — the same photos as a householder (front, back, selfie), sent to
   `POST /api/v1/jobber/verification/identity`.
2. **Garant** — the name and phone of a guarantor, the link with them (parent, family, landlord,
   other), and a photo of a bill in the guarantor's name (water, electricity, certificat de
   résidence or prepaid subscription), sent to `POST /api/v1/jobber/verification/guarantor`.
   `GET /api/v1/jobber/verification` returns statuses only, never the guarantor's name, phone or bill.
3. **Personne de confiance** — up to two people (`TRUSTED_CONTACTS_MAX`) the jobber names; at least one
   must be confirmed. A contact is confirmed by a 6-digit code that **staff send on WhatsApp** and
   the jobber types in the app. A contact is never removed, only **replaced**: the new one goes
   through the same code, the old one keeps counting for J1 until its replacement has confirmed, staff
   have warned the old number and `TRUSTED_CONTACT_CHANGE_DELAY_HOURS` (72) have passed.
4. **Consignes de sécurité** — the safety briefing: cards of text with a question, answered in the app.
   A wrong answer shows why and allows another try; all active cards answered correctly completes the
   step. A card added later does not take J1 away: the jobber just sees "Nouvelle carte à lire".

Staff work in the web console under "Vérifications", queue "Garants" (permission
`verification.view_guarantor`, group `verification_agent`):

1. Read the script to the guarantor over the phone and record the three answers ("Connaît-il le jeune ?",
   "Confirme son identité et son domicile ?", "Accepte d'être contacté ?"). All three must be yes.
2. Confirm with the holder's name, the bill reference, the issue date and whether the name matches,
   or refuse with a reason. The jobber's identity must be confirmed first, and the call recorded.

The same two queues are in the staff app, which is how the messages are normally sent. Staff also
work two more queues in the console under "Vérifications":

- **"Personnes de confiance"** (permission `verification.send_contact_code`, group `verification_agent`):
  "À envoyer" lists the contacts waiting for a code. "Envoyer le code par WhatsApp" shows an
  "Ouvrir WhatsApp" link once; the message is already written. Messages are always sent from the
  admin app, on the device that holds the official number (`OFFICIAL_WHATSAPP_NUMBER`); never from a
  personal phone. The contact's number appears only inside that link, and every view and
  send is audited. "À prévenir" lists confirmed contacts being replaced: warn the old number the same
  way; the delay starts then. Without that notice the old contact stays.
- **"Cartes de briefing"** (group `briefing_manager`): write each card (title, text, question, one
  choice per line, the number of the right line, the explanation shown after a wrong answer), reorder
  them and switch them on or off. **The three cards created by the migration are placeholders:
  replace them before launch.**

Settings (environment variables): `GUARANTOR_DOCUMENT_TYPES`, `GUARANTOR_BILL_MAX_AGE_MONTHS` (3),
`GUARANTOR_VALID_MONTHS` (12; an expired guarantor drops the jobber back to J0, swept hourly by
`expire-guarantors`), `GUARANTOR_MAX_JOBBERS` (3 jobbers per bill reference), `JOBBER_REQUIRED_STEPS`, `TRUSTED_CONTACTS_MAX` (2),
`TRUSTED_CONTACT_CODE_TTL_MINUTES` (1440), `TRUSTED_CONTACT_CODE_MAX_ATTEMPTS` (5),
`TRUSTED_CONTACT_RESEND_SECONDS` (600), `TRUSTED_CONTACT_MAX_ADDS_PER_DAY` (3, replacements included),
`TRUSTED_CONTACT_CHANGE_DELAY_HOURS` (72; swept hourly by `apply-contact-replacements`).

Staff API: `GET staff/contacts?file=send|notice`, `GET staff/contacts/<id>` (name; audited),
`POST staff/contacts/<id>/send` and `.../notice` (return `whatsapp_url`, never cached).

Open decisions: the lawful basis for holding a third party's name, phone and bill (the privacy notice
has a draft section "Informations sur votre garant"); whether a guarantor must consent in writing;
what staff do when a guarantor does not answer; the lawful basis for holding a trusted contact's number
(section "Informations sur votre personne de confiance" in the privacy notice); the staff
workload of sending every code (messages are decided: always sent from the admin app, on the device
with the official number); how a contact who
says "I did not agree" gets off the list, since a contact can be replaced by the jobber but never
removed; whether the briefing needs videos; whether J1 should be required to apply (applications
do not exist yet). The jobber app takes its photos with the same in-app camera as the householder
app; it asks for the camera permission only, never for the location.

## Job offers

A verified householder (tier H1, with a confirmed proof of address) creates a mini-job offer in the
householder app: a category, the duties ticked from its list, a date and start time, a duration, a
pay, and an optional note. The offer takes place at the householder's confirmed address, which is
copied into the offer when it is sent; no address is typed in it.

Statuses: `draft` (saved, editable, visible to its author), `in_review` (waiting for staff),
`published` (visible to mini-jobbers, who see the commune and quartier only), `refused` (with a
reason), `withdrawn` (taken down by the householder), `closed` (its start has passed). A householder
may hold at most three offers in review or published (`OFFER_MAX_OPEN_PER_HOUSEHOLDER`).

An offer goes to staff when it has a signal: a pay above twice the category maximum or below its
minimum, a phone number or e-mail address in the note, or a term of a kind listed in the console
(appearance, travel, empty home, contact outside the app). The householder's first offer always goes
to staff. Otherwise it is published at once.

Staff work in the web console:

- **"Offres"**: the moderation queue, by default the offers in review. Each shows its flags in plain
  French and the householder's phone. "Publier" needs the permission `listings.moderate_offer`;
  "Refuser" needs a reason. Offers are never edited through the generic form. The group
  `offer_moderator` holds this permission.
- **"Catégories d'offres"**: name, duties (one per line), durations in minutes (one per line),
  suggested pay minimum and maximum, active, and position. An inactive category cannot be chosen for
  a new offer; existing offers keep the name and duties they were sent with. The group
  `catalogue_manager` holds the rights to edit it.
- **"Termes de modération"**: a text and a kind (`appearance`, `travel`, `empty_home`,
  `off_platform`). Matching ignores case and accents.

The categories, pay ranges and moderation terms created by the migration
(`0002_seed_catalogue_and_groups`) are **placeholders**: replace them in the console before the
service opens. The limits (hours, pay bounds, days ahead, note length) are settings; see
`.env.example` under "Job offers".

A periodic task (`tidy-offers`, every 15 minutes) closes offers whose start has passed and withdraws
the offers of a householder who has fallen back to H0. Jobbers never see past or unpublished offers,
even before the task runs.

Jobbers see published offers in the jobber app ("Offres"), filtered by commune. The detail screen
states that the exact address is given only after a confirmed booking. Applying and booking are not
built yet.

## Applications

A J1 jobber applies to a published offer with an optional message of up to `APPLICATION_MESSAGE_MAX`
(200) characters; contact details in it are refused. The householder sees the applicants (first
name, tier, jobs done, message) and accepts one: that creates a booking in state `accepted`, declines
the others and marks the offer `booked`, which hides it from jobbers. A jobber may have
`APPLICATIONS_MAX_OPEN` (5) applications waiting and an offer may collect `APPLICATIONS_MAX_PER_OFFER`
(20); an application that overlaps one of the jobber's bookings is refused. An hourly task
(`close-stale-applications`) declines the applications of offers that were withdrawn or have started.

API: jobber `POST offers/<id>/apply`, `GET my-applications`, `POST my-applications/<id>/withdraw`,
`GET my-bookings`; householder `GET my-offers/<id>/applicants`,
`POST my-offers/<id>/applicants/<application>/accept`. Staff see applications and bookings, read-only,
in the console under "Réservations".

This is stage 1 of 3 (design: `docs/superpowers/specs/2026-11-13-applications-and-bookings-design.md`).
Stage 2 (below) adds payment, the address release and cancellation; check-in, the payout and
reviews are stage 3.

## Payment and address release

There is no payment API. The platform has one or more mobile-money accounts; the householder pays one
of them from their own app, then sends the transaction reference and a screenshot; staff check it
against the account's real history and confirm.

**Set up (staff, console "Moyens de paiement", group `payment_agent`).** One row per provider (Wave,
MTN MoMo, Orange Money): the receiving number, the account name, active or not. **With no active
method that has a number, nobody can apply or be accepted**, and the apps say so.

**The flow.** Accepting a jobber creates the booking (`accepted`). The householder opens the booking in
the app, sees the amount and the numbers, pays, picks the method, types the reference and chooses the
screenshot from the gallery (converted to JPEG on the phone). The booking becomes `payment_review`.
Staff open "Paiements" in the console (queue "À vérifier", oldest first, late ones marked), look at the
proof, tick "Le montant correspond" and "La référence correspond", and confirm or refuse (the reason is
shown to the householder, who can send another proof). One reference confirms only one booking. A
confirmed booking shows the jobber's full name and verified photo to the householder; the jobber gets
the exact pin (the householder's confirmed home position) `ADDRESS_RELEASE_HOURS` (3) before the start,
until the job's end; every release and every view of the proof is audited.

**Time and cancelling.** The householder has `PAYMENT_WINDOW_HOURS` (12) to send a proof, and never
past the release time. An unpaid booking then expires (hourly task `expire-unpaid-bookings`) and the
offer reopens if it has not started. A booking whose proof is under review never expires: staff are
expected to answer. Either side can cancel before check-in; money that may have been sent becomes a
line in "Remboursements à faire", and staff record the refund reference. Withdrawing a booked offer
cancels its booking while it is unpaid or under review.

**Settings:** `PAYMENT_WINDOW_HOURS`, `ADDRESS_RELEASE_HOURS`, `PLATFORM_FEE_PERCENT` (0 until the
business decides), `CANCEL_FREE_HOURS`, `PAYMENT_REVIEW_LATE_HOURS` (2).

**What staff must know.** A screenshot is easy to fake: confirm against the platform account's own
history, not the picture. The console warns when the same image was sent for another payment. Holding
customers' money may need a licence or a partner; get a legal review before launch.

