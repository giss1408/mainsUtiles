# Job offers — design

Date: 2026-11-12. Product spec: `skill.md` (sections 3, 4, 5 "Usability rules", 6 "Listing fields").
Builds on householder verification (`2026-11-12-householder-verification-design.md`).

## Goal

A verified householder creates a mini-job offer in the householder app. After moderation the offer
is published, and mini-jobbers see it in the jobber app with the commune and quartier only.

This is piece 2 of 4. Applying to an offer and booking come later, with jobber verification.

## Decisions already taken

- Categories, their duties, duration presets and suggested pay are **data, edited by staff in the
  web console**, not code. The first ones are created with placeholder values that the product
  owner will replace.
- An offer with no moderation signal is published at once; one with a signal waits for staff.
- An offer always takes place at the householder's confirmed address. Nothing about the address is
  typed in the offer.

## Out of scope

- Applications, selection, bookings, payment, chat.
- Recurring offers; offers lasting several days.
- A map or blurred-area image: jobbers see the commune and quartier as text.
- Editing a published offer (the householder withdraws it and creates another).
- Push or SMS notifications. The apps show the new status when opened or refreshed.
- Search by distance, favourites, ratings.
- Managing categories from the staff mobile app (web console only).
- A second address per householder.

## Catalogue (edited by staff)

**Category** — what staff edit in the console under "Catégories d'offres":

| Field | Meaning |
|-------|---------|
| Name | Shown in both apps, for example "Ménage" |
| Duties | A list of short lines the householder ticks, for example "Balayer et laver les sols" |
| Durations | Allowed lengths in minutes, for example 120, 180, 240 |
| Suggested pay, minimum and maximum | In FCFA; shown as a guide and used by moderation |
| Active | An inactive category cannot be chosen for a new offer; existing offers keep it |
| Order | Position in the list |

Created by a migration, with placeholder values to be replaced:

| Name | Duties (placeholders) | Durations | Suggested pay |
|------|-----------------------|-----------|---------------|
| Ménage | Balayer et laver les sols; Dépoussiérer; Nettoyer la cuisine; Nettoyer les sanitaires; Repasser le linge | 2 h, 3 h, 4 h | 2 000–5 000 FCFA |
| Cuisine | Préparer un repas; Faire la vaisselle; Ranger la cuisine | 2 h, 3 h | 2 000–5 000 FCFA |
| Accompagnement d'une personne âgée | Tenir compagnie; Aider à la marche; Préparer un repas léger; Accompagner pour une sortie à pied | 2 h, 4 h, 8 h | 3 000–8 000 FCFA |

**Moderation terms** — words or phrases that send an offer to staff, edited in the console under
"Termes de modération". Each has a text and a kind. Created by a migration with a starting list
(placeholders, to be reviewed):

| Kind | Meaning | Starting examples |
|------|---------|-------------------|
| `appearance` | Age, gender or looks requested | jeune fille, jolie, belle, célibataire |
| `travel` | Travel, lodging or abroad | voyage, logé, logée, nourri logé, étranger, Europe |
| `empty_home` | The home will be empty | maison vide, personne à la maison, seul à la maison |
| `off_platform` | Contact outside the app | WhatsApp, appelle, appelez, mon numéro |

Matching ignores case and accents. Phone numbers and e-mail addresses in the note are detected by
pattern, not by a term.

Changing a category or a term never changes offers already created: an offer keeps a copy of the
category name and the ticked duties as they were.

Limits that are not per category are settings read from the environment:

| Setting | Default |
|---------|---------|
| `OFFER_EARLIEST_START` | 06:00 |
| `OFFER_LATEST_END` | 19:00 |
| `OFFER_MIN_PAY_XOF` | 1000 |
| `OFFER_MAX_PAY_XOF` | 100000 |
| `OFFER_PAY_FLAG_FACTOR` (pay above this × the category maximum is flagged) | 2 |
| `OFFER_MAX_DAYS_AHEAD` | 30 |
| `OFFER_MAX_OPEN_PER_HOUSEHOLDER` | 3 |
| `OFFER_NOTE_MAX_LENGTH` | 300 |

Times are in the Africa/Abidjan time zone.

## An offer

| Field | Rule |
|-------|------|
| Category | Active when the offer is sent |
| Duties | At least one, each from the category's list |
| Date and start time | Not in the past; at most `OFFER_MAX_DAYS_AHEAD` days ahead |
| Duration | One of the category's durations; start and end within the allowed hours, same day |
| Pay | Whole FCFA, between the minimum and maximum settings |
| Note | Optional, up to `OFFER_NOTE_MAX_LENGTH` characters |
| Place | The householder's confirmed commune and quartier, copied when the offer is sent |

### Status

`draft → in_review | published`; `in_review → published | refused`;
`draft | in_review | published → withdrawn`; `published → closed`.

- `draft`: saved, visible only to its author, editable.
- Sending a draft checks every rule, then runs the screening. No signal: `published`. Any signal:
  `in_review`, with the signals recorded as flags.
- `in_review`: waits for staff, who publish or refuse with a reason shown to the householder.
- `refused`: final. The householder may copy it into a new draft.
- `withdrawn`: taken down by the householder. Final.
- `closed`: its start time has passed. Set by a periodic task; an offer whose start has passed is
  also hidden from jobbers at once, before the task runs.
- Only a draft can be edited or deleted.
- "Open" offers, for the limit per householder, are those `in_review` or `published`.

### Who may do what

- Creating, editing and sending needs a householder at tier **H1** with a confirmed, unexpired
  proof of address. A householder at H0 can see the screen, which says verification is needed.
- If the householder falls back to H0 (proof of address expired), their published and in-review
  offers are withdrawn automatically by the same periodic task, with the reason shown.
- A householder sees only their own offers.
- A jobber sees published offers whose start is in the future. A jobber never sees drafts,
  refused or withdrawn offers, flags, or anything about the householder beyond what is listed below.
- Staff need the permission `listings.moderate_offer` (new group `offer_moderator`) to publish or
  refuse. Editing categories and terms uses the standard console permissions on those two models,
  held by superusers and by a new group `catalogue_manager`.

### Screening signals (flags)

| Flag | Raised when |
|------|-------------|
| `pay_high` | Pay is above `OFFER_PAY_FLAG_FACTOR` × the category's suggested maximum |
| `pay_low` | Pay is below the category's suggested minimum |
| `contact_details` | The note contains a phone number or an e-mail address |
| `appearance`, `travel`, `empty_home`, `off_platform` | The note contains a term of that kind |
| `first_offer` | It is the householder's first offer ever sent |

`first_offer` means every householder's first offer is seen by a person.

## What a jobber sees

For each published offer: category name, ticked duties, date, start time, duration, pay, commune,
quartier, and the note. Nothing else: no address, no position, no name, no phone number, no
householder id, no flags. The list is ordered by start time, soonest first, 20 per page, and can be
filtered by commune.

The detail screen states: "L'adresse exacte est communiquée seulement après une réservation
confirmée." There is no button to apply or to contact the householder.

## Backend

A new Django app, `apps/listings`. Rules live in its services.

- Models: `OfferCategory`, `ModerationTerm`, `Offer` (author, category, copied category name,
  duties, start, duration, pay, note, copied commune and quartier, status, flags, reason,
  moderated_by, moderated_at, published_at, timestamps).
- Services: `catalogue` (active categories), `screening` (flags for an offer), `offers` (create,
  update, delete a draft; send; withdraw; copy; the periodic clean-up), `moderation` (publish,
  refuse; each writes an `AdminAction`).
- It uses `verification.services.tiers` to read the tier and the confirmed commune and quartier.

API (JSON, existing error shape `{error, message}` with French messages):

- Householder (`IsHouseholder`):
  - `GET /api/v1/offer-categories` → active categories with duties, durations, suggested pay.
  - `GET /api/v1/my-offers` → own offers, newest first, with `can_publish` (tier H1) at top level.
  - `POST /api/v1/my-offers` → create a draft. `PATCH /api/v1/my-offers/{id}` → edit a draft.
    `DELETE` → delete a draft.
  - `POST /api/v1/my-offers/{id}/send`, `/withdraw`, `/copy`.
- Jobber (`IsJobber`):
  - `GET /api/v1/offers?commune=` → published, future offers (paginated), plus the list of
    communes for the filter.
  - `GET /api/v1/offers/{id}` → one published, future offer; anything else answers 404.
- Errors: `verification_required` (403), `category_invalid`, `duties_invalid`, `time_invalid`,
  `duration_invalid`, `pay_invalid`, `note_too_long` (400), `too_many_offers` (409),
  `invalid_state` (409).

Web console:

- "Offres": a moderation queue (default filter: `in_review`), with the offer, its flags in plain
  French, the householder's phone, and "Publier" / "Refuser" (reason required). Offers are never
  edited through the generic form.
- "Catégories d'offres" and "Termes de modération": ordinary editable lists. Duties and durations
  are entered one per line.

## Apps

Shared code in `petitgombo_core/src/offers/`, following the verification code (API class,
controller, copy class, screens).

Householder app:

- After verification the home screen becomes "Mes offres": the list of own offers with their
  status in plain words, and "Créer une offre". Before verification the home screen is the
  verification checklist, as today; once verified, the checklist is reached from a "Compte vérifié"
  row.
- Creation is one step per screen: category → duties (tick boxes) → date, start time and duration
  → pay (with "Suggestion : 2 000 à 5 000 FCFA") → optional note (with the reminder "N'indiquez ni
  numéro de téléphone, ni adresse, ni information médicale.") → summary → "Publier l'offre".
  Progress is saved as a draft after each step.
- After sending: "Offre publiée." or "Offre envoyée. Nous la vérifions sous 24 h."
- Offer detail: the content, the status, the refusal reason if any, and the actions allowed in
  that status ("Modifier" and "Supprimer" for a draft, "Retirer l'offre" when in review or
  published, "Créer une offre semblable" when refused, withdrawn or closed).
- Amounts are written `3 500 FCFA`; dates as `jeu. 14 nov. · 09:00 – 12:00`.

Jobber app:

- The signed-in home screen becomes "Offres": the list (category, date and time, pay, commune and
  quartier), a commune filter, pull-to-refresh, loading skeleton, empty state "Aucune offre pour le
  moment.", and the detail screen described above. The jobber app speaks in "tu".

## Tests

Backend: every endpoint for each role and without a token; a householder never reaches another's
offer; H0 cannot create or send; every rule in the offer table, at its boundary (06:00 start, end
exactly 19:00, pay at the limits, 30 days ahead); every status change including invalid ones; each
flag, with case and accent variants; `first_offer`; the jobber list never contains drafts, refused,
withdrawn, closed or past offers, nor any address, position, phone or householder id; category and
term edits do not alter existing offers; the periodic task closes past offers and withdraws those
of householders back at H0; moderation permission, single audit row, second decision refused.

Apps: API classes, controllers, each screen state, the whole creation flow, a refused offer and
its copy, the jobber list filter, and 320dp screens at twice the text size.

Manual check on a phone: create and publish an offer in the householder app, approve it in the
console (a first offer is always reviewed), and see it in the jobber app.

## Threat model

`docs/threat-model.md`: "Lure listings" gains what is built (only verified householders at a
confirmed address can publish; screening and human review; first offers always reviewed; no
contact path yet) and "Address harvesting" notes that offers expose commune and quartier only.
