# Job Offers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A verified householder creates a job offer in the app; after screening and, when needed, staff moderation, it is published and jobbers see it with commune and quartier only.

**Architecture:** A new Django app `apps/listings` with staff-editable catalogue models (`OfferCategory`, `ModerationTerm`), an `Offer` model, and rules in services (`screening`, `offers`, `moderation`). Two API surfaces (householder: own offers; jobber: published offers) and console pages in the Django admin. Flutter code lives in `petitgombo_core/src/offers/`; the householder app shows "Mes offres" once verified, the jobber app shows "Offres".

**Tech Stack:** Django 5.2, DRF, Celery beat, pytest; Flutter 3.24.2, Riverpod, Dio.

**Spec:** `docs/superpowers/specs/2026-11-12-job-offers-design.md` (product spec: `skill.md`).

## Global Constraints

- Work on branch `feat/job-offers`, created from `feat/householder-verification`. Commit after each task.
- Backend commands run from `backend/`: `.venv/bin/pytest`, `.venv/bin/ruff check . && .venv/bin/ruff format --check .`.
- Flutter is 3.24.2 (Dart 3.5); use only its APIs; add no new packages. Run `flutter analyze` and `flutter test` in every Dart package touched; format with `dart format -l 100`.
- All user-facing copy is French; code, comments and logs are English. The householder app says "vous", the jobber app "tu".
- Every limit is a Django setting read from the environment with the spec's default. Categories and moderation terms are database rows edited in the console, never constants in code.
- Business rules live in services, never in views, admin classes or the Flutter client.
- Nothing returned to a jobber may contain: an address, coordinates, the householder's name, phone or id, flags, or the refusal reason. Tests assert this on raw response text.
- Every staff decision writes an `AdminAction` (`apps.audit.services.record`).
- API errors use `{"error": code, "message": french}` via `apps/accounts/api/errors.py`.
- Times are stored in UTC and interpreted in `Africa/Abidjan` (`timezone.localtime`).
- Flutter UI follows the existing tokens (`Gaps`, `Radii`, `AppColors`, `FlowScaffold`, `ChoiceCard`, `BusyButton`, `MessageBanner`): one primary action per screen, no inline font sizes, status never by colour alone, no overflow at 320dp with text scale 2. Async views have loading (skeleton), empty, error (with "Réessayer") and data states.
- Amounts are written `3 500 FCFA` (narrow no-break space not required; a normal space). Dates are written like `jeu. 14 nov. · 09:00 – 12:00`, formatted by hand (no `intl` package).

**Out of scope (do not build):** applications, bookings, payment, chat, recurring or multi-day offers, map images, editing a published offer, notifications, distance search, category management in the staff mobile app.

## Review Focus

1. **Terms typed with other case or accents.** `Logée`, `LOGEE`, `étranger` / `etranger`, `WhatsApp` / `whatsapp` must all raise their flag. (Task 2)
2. **Phone numbers in disguise.** `07 08 09 10 11`, `0708.09.10.11`, `+225 0708091011`, `zéro sept zéro huit…` — the first three must raise `contact_details`; the spelled-out form is not detected and that is accepted. (Task 2)
3. **Time passes while an offer waits.** An offer whose start has passed cannot be published by staff and is not listed to jobbers, even before the periodic task runs. (Task 3, Task 5, Task 6)
4. **Catalogue changes between draft and send.** A category made inactive, or a duty removed, after the draft was saved: sending is refused with a clear message; already-sent offers keep their copied name and duties. (Task 3)
5. **Double tap on "Publier l'offre".** The second send answers `invalid_state`; the app treats it as done and shows the offer once. (Task 3, Task 7)

---

## File Structure

```
backend/apps/listings/
  apps.py  models.py  admin.py  console_views.py  tasks.py
  migrations/0001_initial.py  0002_seed_catalogue_and_groups.py
  services/catalogue.py  screening.py  offers.py  moderation.py
  api/serializers.py  views.py  urls.py
  templates/admin/listings/offer_review.html
backend/tests/test_listings_models.py  test_offer_screening.py  test_offer_service.py
              test_my_offers_api.py  test_offers_api.py  test_offer_moderation.py
mobile/packages/petitgombo_core/lib/src/offers/
  offer_models.dart  offers_api.dart  offer_format.dart  offer_copy.dart
  my_offers_controller.dart  offers_controller.dart
  screens/my_offers_screen.dart  offer_form_flow.dart  my_offer_detail_screen.dart
  screens/offers_screen.dart  offer_detail_screen.dart
```

---

### Task 1: Models, catalogue seed, groups, settings

**Files:**
- Create: `backend/apps/listings/__init__.py`, `apps.py`, `models.py`, `migrations/0001_initial.py`, `migrations/0002_seed_catalogue_and_groups.py`, `services/__init__.py`, `services/catalogue.py`
- Modify: `backend/config/settings.py` (`INSTALLED_APPS`, settings), `.env.example`
- Test: `backend/tests/test_listings_models.py`

**Interfaces:**
- Settings (env type, default): `OFFER_EARLIEST_START` (str `"06:00"`), `OFFER_LATEST_END` (str `"19:00"`), `OFFER_MIN_PAY_XOF` (int 1000), `OFFER_MAX_PAY_XOF` (int 100000), `OFFER_PAY_FLAG_FACTOR` (float 2), `OFFER_MAX_DAYS_AHEAD` (int 30), `OFFER_MAX_OPEN_PER_HOUSEHOLDER` (int 3), `OFFER_NOTE_MAX_LENGTH` (int 300), `OFFER_REVIEW_HOURS` (int 24).
- `OfferCategory`: `name` (unique), `duties` (JSON list of str), `durations_minutes` (JSON list of int), `suggested_pay_min`, `suggested_pay_max` (positive ints), `active` (bool, default True), `position` (int, default 0). `clean()` refuses: empty duties, empty durations, a duration ≤ 0, min > max. Ordering `position, name`. French verbose names "catégorie d'offre" / "catégories d'offres".
- `ModerationTerm`: `text` (max 80), `kind` (`appearance|travel|empty_home|off_platform`), unique together `(text, kind)`. Verbose names "terme de modération" / "termes de modération".
- `Offer` (UUID pk): `author` FK User (PROTECT), `category` FK (PROTECT), `category_name`, `duties` (JSON list), `starts_at` (datetime), `duration_minutes`, `pay_xof`, `note` (blank), `commune`, `quartier` (blank until sent), `status` (`draft|in_review|published|refused|withdrawn|closed`, default `draft`), `flags` (JSON list), `reason` (blank), `moderated_by` (FK null, PROTECT), `moderated_at`, `sent_at`, `published_at`, `created_at`, `updated_at`. Property `ends_at`. `OPEN_STATUSES = (in_review, published)`. Indexes on `(status, starts_at)` and `(author, created_at)`. Permission `moderate_offer`. Verbose names "offre" / "offres".
- Migration `0002`: creates the three categories and the moderation terms exactly as listed in the spec tables; creates groups `offer_moderator` (`moderate_offer`, `view_offer`) and `catalogue_manager` (add/change/delete/view on `offercategory` and `moderationterm`), following `verification/migrations/0002_verification_agent_group.py`.
- `catalogue.active_categories() -> QuerySet[OfferCategory]`.

- [ ] **Step 1: Write the failing tests** — `test_seeded_categories_have_the_spec_values` (three names; Ménage durations `[120, 180, 240]`, pay 2000–5000; Accompagnement durations `[120, 240, 480]`, pay 3000–8000), `test_seeded_terms_cover_the_four_kinds`, `test_category_clean_refuses_empty_duties_bad_durations_and_inverted_pay`, `test_inactive_categories_are_left_out_of_active_categories`, `test_groups_have_their_permissions` (and `enrolment_agent` has neither), `test_offer_ends_at_and_default_status`, `test_offer_settings_have_the_spec_defaults`.
- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_listings_models.py` — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest`, ruff, `manage.py makemigrations --check --dry-run` — expected PASS, "No changes detected".
- [ ] **Step 5: Commit** — `feat: offer catalogue and offer model`.

---

### Task 2: Screening

**Files:**
- Create: `backend/apps/listings/services/screening.py`
- Test: `backend/tests/test_offer_screening.py`

**Interfaces:**
- Consumes: Task 1 models and settings.
- Produces:
  - `normalise(text: str) -> str` — lower case, accents removed (`unicodedata` NFKD), whitespace collapsed.
  - `screen(*, category: OfferCategory, pay_xof: int, note: str, first_offer: bool) -> list[str]` — the flags, in this order, each at most once: `pay_high`, `pay_low`, `contact_details`, `appearance`, `travel`, `empty_home`, `off_platform`, `first_offer`.
- Rules: `pay_high` when `pay_xof > OFFER_PAY_FLAG_FACTOR * category.suggested_pay_max`; `pay_low` when `pay_xof < category.suggested_pay_min`. A term matches when its normalised text appears in the normalised note as whole words (word-boundary match, so "belle" does not match "poubelle"). `contact_details` when the note contains an e-mail address, or 8 or more digits once spaces, dots, dashes and a leading `+` are ignored between digits.

- [ ] **Step 1: Write the failing tests**

```python
def test_clean_offer_has_no_flags(menage): assert screen(category=menage, pay_xof=3000, note="Merci d'apporter des gants.", first_offer=False) == []
def test_pay_boundaries(menage):                       # 10000 no flag, 10001 pay_high; 2000 no flag, 1999 pay_low
@pytest.mark.parametrize("note", ["Logée sur place", "LOGEE", "voyage a l'etranger", "à l'Étranger"])
def test_travel_terms_ignore_case_and_accents(...)     # Review Focus 1 -> ["travel"]
@pytest.mark.parametrize("note", ["contact WhatsApp", "whatsapp", "Appelez-moi"])
def test_off_platform_terms(...)
def test_terms_match_whole_words_only(menage)          # "sortir la poubelle" -> no appearance flag
@pytest.mark.parametrize("note", ["07 08 09 10 11", "0708.09.10.11", "+225 0708091011", "a@b.ci"])
def test_contact_details_in_disguise(...)              # Review Focus 2
def test_short_numbers_are_not_contact_details(menage) # "3 pièces, 2 salles de bain, 4e étage"
def test_first_offer_flag_and_order(menage)            # pay_high + travel + first_offer, in that order
def test_a_term_added_in_the_database_is_used_at_once(menage)
```
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: offer screening`.

---

### Task 3: Offer service

**Files:**
- Create: `backend/apps/listings/services/offers.py`, `backend/apps/listings/tasks.py`
- Modify: `backend/config/settings.py` (`CELERY_BEAT_SCHEDULE` entry `tidy-offers`, every 15 minutes), `backend/apps/accounts/api/errors.py`
- Test: `backend/tests/test_offer_service.py`

**Interfaces:**
- Consumes: Tasks 1–2; `verification.services.tiers.householder_tier`, `current_record`; `verification.models.AddressProof`.
- `class OfferError(Exception)` with `.code`: `forbidden | verification_required | category_invalid | duties_invalid | time_invalid | duration_invalid | pay_invalid | note_too_long | too_many_offers | invalid_state`.
- Produces (all keyword-only after the first argument):
  - `create_draft(user, *, category_id, duties: list[str], starts_at: datetime, duration_minutes: int, pay_xof: int, note: str = "") -> Offer`
  - `update_draft(offer, *, user, **fields) -> Offer` — same fields, all optional
  - `delete_draft(offer, *, user) -> None`
  - `send(offer, *, user) -> Offer` — validates everything again, copies `category_name`, `commune`, `quartier`, runs `screening.screen`, sets `sent_at`; no flags → `published` with `published_at`; flags → `in_review`
  - `withdraw(offer, *, user) -> Offer` — from `draft`, `in_review` or `published`
  - `copy_as_draft(offer, *, user) -> Offer` — from any status; keeps category, duties, duration, pay, note; `starts_at` is moved to the same time on the next day that is still in the future
  - `visible_to_jobbers() -> QuerySet[Offer]` — `published` with `starts_at > now`, ordered by `starts_at`
  - `tidy() -> dict` — closes published offers whose start has passed; withdraws (reason "Votre compte n'est plus vérifié. Renouvelez votre justificatif de domicile.") the open offers of householders no longer at H1; returns `{"closed": n, "withdrawn": n}`
- Rules: every function requires `user.role == "householder"` and, for anything on an existing offer, `offer.author == user` (`forbidden`). `create_draft`, `update_draft`, `send`, `copy_as_draft` require tier H1 (`verification_required`). Drafts are validated on save with the same rules as on send, except the open-offer limit, which is checked on send (`too_many_offers`). Validation: category exists and is active (`category_invalid`); duties non-empty, unique, each in the category's list (`duties_invalid`); `starts_at` in the future and within `OFFER_MAX_DAYS_AHEAD` days, local start ≥ `OFFER_EARLIEST_START`, local end ≤ `OFFER_LATEST_END` on the same local day (`time_invalid`); duration in the category's list (`duration_invalid`); pay within the min and max settings (`pay_invalid`); note length (`note_too_long`). Only a draft can be updated, deleted or sent (`invalid_state`). `send` locks the row (`select_for_update`). `first_offer` is true when the author has no other offer with `sent_at` set.
- `tasks.tidy_offers()` calls `offers.tidy()`.
- French messages added to `errors.py`: `verification_required` (403) "Faites vérifier votre compte pour publier une offre."; `category_invalid` (400) "Cette catégorie n'est plus disponible."; `duties_invalid` (400) "Choisissez au moins une tâche de la liste."; `time_invalid` (400) "Choisissez une date à venir, entre 06:00 et 19:00."; `duration_invalid` (400) "Choisissez une durée proposée."; `pay_invalid` (400) "Indiquez un montant entre 1 000 et 100 000 FCFA."; `note_too_long` (400) "La précision est trop longue."; `too_many_offers` (409) "Vous avez déjà 3 offres en cours. Retirez-en une pour en publier une autre." The time and pay messages are built from the settings, not hard-coded.
- `conftest.py` gains `verified_householder` (a householder at H1 with commune Cocody, quartier Angré, built through the verification services) and `menage` (the seeded category).

- [ ] **Step 1: Write the failing tests**

```python
def test_h0_householder_cannot_create_or_send(...)                 # verification_required
def test_jobber_and_staff_are_forbidden(...)
def test_draft_is_saved_with_no_place_and_no_flags(...)
def test_time_rules_at_their_boundaries(...)                       # 06:00 ok, 05:59 no; end 19:00 ok, 19:01 no; past no; 30 days ok, 31 no  (freezegun)
def test_duties_duration_pay_and_note_rules(...)                   # each invalid value -> its code; nothing saved
def test_send_first_offer_goes_to_review_with_first_offer_flag(...)
def test_send_second_clean_offer_is_published_at_once(...)         # after the first was published by staff
def test_send_copies_category_name_commune_and_quartier(...)
def test_send_twice_is_invalid_state(...)                          # Review Focus 5
def test_fourth_open_offer_is_too_many(...)
def test_category_made_inactive_or_duty_removed_before_send_is_refused(...)   # Review Focus 4
def test_editing_the_category_later_does_not_change_a_sent_offer(...)         # Review Focus 4
def test_only_drafts_can_be_updated_or_deleted(...)
def test_withdraw_from_each_allowed_status_and_not_from_refused(...)
def test_another_householder_cannot_touch_the_offer(...)           # forbidden on every function
def test_copy_as_draft_moves_the_date_to_the_future(...)
def test_visible_to_jobbers_hides_past_offers_before_tidy_runs(...) # Review Focus 3
def test_tidy_closes_past_offers_and_withdraws_those_of_unverified_householders(...)
```
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: offer rules, sending and clean-up`.

---

### Task 4: Householder API

**Files:**
- Create: `backend/apps/listings/api/__init__.py`, `serializers.py`, `views.py`, `urls.py`
- Modify: `backend/config/api_urls.py`
- Test: `backend/tests/test_my_offers_api.py`

**Interfaces:**
- Consumes: Task 3 services, Task 1 catalogue.
- Endpoints (`IsHouseholder`):
  - `GET /api/v1/offer-categories` → `{"categories": [{id, name, duties, durations_minutes, suggested_pay_min, suggested_pay_max}], "limits": {earliest_start, latest_end, min_pay, max_pay, max_days_ahead, note_max_length}}`
  - `GET /api/v1/my-offers` → `{"can_publish": bool, "review_hours": int, "offers": [MyOffer]}` newest first
  - `POST /api/v1/my-offers` body `{category_id, duties, starts_at, duration_minutes, pay_xof, note}` → 201 `MyOffer`
  - `PATCH /api/v1/my-offers/{id}` (any subset) → `MyOffer`; `DELETE` → 204
  - `POST /api/v1/my-offers/{id}/send` → `MyOffer`; `/withdraw` → `MyOffer`; `/copy` → 201 `MyOffer`
- `MyOffer`: `{id, category_id, category_name, duties, starts_at, duration_minutes, pay_xof, note, commune, quartier, status, reason, created_at}`. Never `flags` (the householder must not learn the detection rules).
- An offer that is not the caller's answers 404. `OfferError` maps through `errors.error_response`; `forbidden` → 404.

- [ ] **Step 1: Write the failing tests** — every endpoint: no token 401, jobber 403, staff 403; `test_categories_and_limits`, `test_create_edit_send_withdraw_copy_round_trip`, `test_h0_householder_gets_403_verification_required_and_can_publish_false`, `test_invalid_fields_give_400_with_french_message` (one per code), `test_other_householders_offer_is_404_on_every_route`, `test_response_never_contains_flags`, `test_send_twice_is_409`, `test_delete_only_drafts`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: householder offers API`.

---

### Task 5: Jobber API

**Files:**
- Modify: `backend/apps/listings/api/serializers.py`, `views.py`, `urls.py`
- Test: `backend/tests/test_offers_api.py`

**Interfaces:**
- Consumes: `offers.visible_to_jobbers()`.
- Endpoints (`IsJobber`):
  - `GET /api/v1/offers?commune=&page=` → `{"count", "next", "previous", "results": [PublicOffer], "communes": [...]}` — 20 per page, soonest first; `communes` is `SERVICE_COMMUNES`; an unknown commune answers 400.
  - `GET /api/v1/offers/{id}` → `PublicOffer`, or 404 for anything not visible.
- `PublicOffer`: exactly `{id, category_name, duties, starts_at, duration_minutes, pay_xof, note, commune, quartier}`.

- [ ] **Step 1: Write the failing tests**

```python
def test_jobber_sees_only_published_future_offers_soonest_first(...)   # draft, in_review, refused, withdrawn, closed, past: all absent
def test_public_offer_has_exactly_the_allowed_keys(...)
def test_no_response_contains_address_position_phone_or_author(...)    # raw text: householder phone, user id, "5.3599", "flags", "reason"
def test_commune_filter_and_unknown_commune(...)
def test_detail_of_hidden_offer_is_404(...)                            # each hidden status and a past one (Review Focus 3)
def test_pagination_is_20_per_page(...)
def test_householder_staff_and_anonymous_are_refused(...)              # 403, 403, 401
```
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: jobber offers API`.

---

### Task 6: Moderation and web console

**Files:**
- Create: `backend/apps/listings/services/moderation.py`, `backend/apps/listings/admin.py`, `console_views.py`, `templates/admin/listings/offer_review.html`
- Test: `backend/tests/test_offer_moderation.py`

**Interfaces:**
- Consumes: Tasks 1, 3.
- `moderation.publish(offer, *, staff) -> None` — needs `listings.moderate_offer`; only from `in_review` (`invalid_state`); refuses when the start has passed (`time_invalid`) or the author is no longer H1 (`verification_required`); sets `published`, `published_at`, `moderated_by/at`; audit `offer.publish`.
- `moderation.refuse(offer, *, staff, reason: str) -> None` — reason required (`reason_required`); only from `in_review`; audit `offer.refuse` with the reason.
- Console:
  - `OfferAdmin` "Offres": list (sent date, author phone, category, start, pay, commune, status, flags); default filter `in_review` (reuse the "À traiter" filter pattern of `verification/admin.py`); read-only; change page uses `offer_review.html` showing every field, the flags in French, and "Publier" / "Refuser" (with "Motif") while `in_review`. Custom POST-only URLs `<uuid:pk>/publish/`, `<uuid:pk>/refuse/`.
  - Flag texts: `pay_high` "Rémunération très au-dessus de la catégorie."; `pay_low` "Rémunération en dessous de la catégorie."; `contact_details` "Numéro de téléphone ou e-mail dans la précision."; `appearance` "Mention de l'âge, du genre ou de l'apparence."; `travel` "Mention de voyage, de logement ou de l'étranger."; `empty_home` "Indique que le domicile sera vide."; `off_platform` "Propose un contact hors de l'application."; `first_offer` "Première offre de ce compte."
  - `OfferCategoryAdmin` "Catégories d'offres": editable; a form where `duties` and `durations_minutes` are text areas, one value per line (durations in minutes); calls `full_clean`.
  - `ModerationTermAdmin` "Termes de modération": editable list with a `kind` filter.

- [ ] **Step 1: Write the failing tests** — `test_publish_makes_the_offer_visible_to_jobbers_and_audits`, `test_refuse_needs_a_reason_and_the_householder_sees_it`, `test_second_decision_is_invalid_state_with_one_audit_row`, `test_publishing_a_past_offer_is_refused` (Review Focus 3), `test_staff_without_the_permission_are_forbidden`, `test_moderator_sees_queue_and_review_page_with_french_flags`, `test_publish_and_refuse_through_the_forms`, `test_verification_agent_gets_403_on_offers`, `test_decisions_via_get_are_405`, `test_offers_cannot_be_edited_added_or_deleted_in_admin`, `test_catalogue_manager_edits_a_category_with_one_value_per_line`, `test_bad_category_form_shows_errors_and_saves_nothing`, `test_moderator_cannot_edit_categories`, `test_a_new_term_flags_the_next_offer`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: offer moderation and catalogue in the web console`.

---

### Task 7: Flutter core — models, API, formatting, controllers

**Files:**
- Create: `mobile/packages/petitgombo_core/lib/src/offers/offer_models.dart`, `offers_api.dart`, `offer_format.dart`, `offer_copy.dart`, `my_offers_controller.dart`, `offers_controller.dart`
- Modify: `lib/petitgombo_core.dart`
- Test: `test/offers_api_test.dart`, `test/offer_format_test.dart`, `test/my_offers_controller_test.dart`, `test/offers_controller_test.dart`, `test/support/offer_fixtures.dart`

**Interfaces:**
- Consumes: Tasks 4–5 endpoints; `Session.authorized`, `guardApi`, `ApiError`.
- `offer_models.dart`: `OfferCategory {id, name, duties, durationsMinutes, suggestedPayMin, suggestedPayMax}`, `OfferLimits {earliestStart, latestEnd, minPay, maxPay, maxDaysAhead, noteMaxLength}` (times as `(int hour, int minute)`), `enum OfferStatus {draft, inReview, published, refused, withdrawn, closed}` (unknown → `inReview`), `MyOffer` (all `MyOffer` JSON fields, `DateTime startsAt` in local time), `PublicOffer`, `OfferDraft {categoryId, duties, startsAt, durationMinutes, payXof, note}` with `toJson()`, `MyOffers {canPublish, reviewHours, offers}`, `OfferPage {offers, communes, hasMore}`.
- `OffersApi(Dio)`: `categories(access) -> (List<OfferCategory>, OfferLimits)`, `myOffers(access) -> MyOffers`, `createDraft(access, OfferDraft) -> MyOffer`, `updateDraft(access, id, OfferDraft) -> MyOffer`, `deleteDraft(access, id)`, `send(access, id) -> MyOffer`, `withdraw(access, id) -> MyOffer`, `copy(access, id) -> MyOffer`, `offers(access, {String? commune, int page = 1}) -> OfferPage`, `offer(access, id) -> PublicOffer`.
- `offer_format.dart`: `formatXof(int) -> String` (`3500` → `3 500 FCFA`), `formatDuration(int minutes)` (`120` → `2 h`, `150` → `2 h 30`), `formatWhen(DateTime start, int durationMinutes)` (`jeu. 14 nov. · 09:00 – 12:00`), `formatDay(DateTime)` (`jeudi 14 novembre`).
- `OfferCopy`: all French text (statuses: draft "Brouillon", inReview "En cours de vérification", published "Publiée", refused "Refusée", withdrawn "Retirée", closed "Terminée"; householder texts in "vous", jobber texts in "tu"; see Tasks 8–9 for the exact strings).
- `MyOffersController extends StateNotifier<MyOffersState>` — state `{MyOffers? data, List<OfferCategory> categories, OfferLimits? limits, bool loading, bool sending, String? error}`; methods `load()`, `saveDraft(OfferDraft, {String? id}) -> Future<MyOffer?>`, `publish(String id) -> Future<MyOffer?>` (on `invalid_state` reloads and returns the offer found in the list — Review Focus 5), `withdraw(id)`, `delete(id)`, `copy(id) -> Future<MyOffer?>`. Provider `myOffersControllerProvider`.
- `OffersController extends StateNotifier<OffersState>` — state `{List<PublicOffer>? offers, List<String> communes, String? commune, bool loading, bool hasMore, String? error}`; methods `load()`, `setCommune(String?)`, `loadMore()`. Provider `offersControllerProvider`.
- Errors: server `message` when present; network → "Pas de connexion. Réessayez."; 401 → the session-expired text of `VerificationCopy`.

- [ ] **Step 1: Write the failing tests** — API: request path, method, body and parsing for each call; `starts_at` sent as UTC ISO; `offers` passes `commune` and `page`; 409 `too_many_offers` becomes `ApiError` with its message. Format: the four functions, including `formatXof(100000)` → `100 000 FCFA`, a Sunday in January, and a start at 06:00. Controllers: load, save then publish, publish answering `invalid_state` then a list containing the offer returns it (Review Focus 5), withdraw, delete removes it, copy, network failure keeps data and sets the message; jobber list load, filter by commune resets the list, `loadMore` appends, failure keeps the list.
- [ ] **Step 2: Run** `flutter test` in `petitgombo_core` — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test && flutter analyze` — expected all pass, no issues.
- [ ] **Step 5: Commit** — `feat(mobile): offers API, formatting and controllers`.

---

### Task 8: Householder screens

**Files:**
- Create: `mobile/packages/petitgombo_core/lib/src/offers/screens/my_offers_screen.dart`, `offer_form_flow.dart`, `my_offer_detail_screen.dart`
- Modify: `lib/src/app/petitgombo_app.dart`, `lib/src/verification/screens/checklist_screen.dart` (accept an optional `onBack`), `lib/petitgombo_core.dart`
- Test: `test/my_offers_screens_test.dart`, `test/app_test.dart`, `mobile/apps/householder/test/app_test.dart`

**Interfaces:**
- Consumes: Task 7; verification controller and `ChecklistScreen`.
- App root for a signed-in householder: loads the verification checklist; while not verified shows `ChecklistScreen` as today; once `verified`, shows `MyOffersScreen`.
- `MyOffersScreen({onSignOut})`: title "Mes offres"; a row "Compte vérifié" (check icon, opens the checklist with a back arrow); `FilledButton` "Créer une offre"; the list of own offers as cards (category, `formatWhen`, `formatXof`, status with an icon); skeleton while loading; empty state "Vous n'avez pas encore d'offre."; error banner with "Réessayer"; pull-to-refresh; reload when the app returns to the foreground; "Se déconnecter" at the bottom.
- `OfferFormFlow({MyOffer? draft})` — one step per screen inside `FlowScaffold`, system back goes to the previous step, a draft is saved (`saveDraft`) when the summary is reached and again on any later change:
  1. "Quel service cherchez-vous ?" — `ChoiceCard` per category.
  2. "Que faut-il faire ?" — a `CheckboxListTile` per duty; "Continuer" disabled until one is ticked.
  3. "Quand ?" — date (button opening `showDatePicker`, limited to today … today + `maxDaysAhead`), start time (`showTimePicker`, 24-hour), duration (`ChoiceChip` per category duration); error text from the server rule shown locally when the end would pass `latestEnd` or the start is before `earliestStart`: "Choisissez un horaire entre 06:00 et 19:00." (built from the limits).
  4. "Quelle rémunération ?" — numeric field with suffix "FCFA", helper "Suggestion : 2 000 à 5 000 FCFA" from the category; error "Indiquez un montant entre 1 000 et 100 000 FCFA." from the limits.
  5. "Une précision ? (facultatif)" — multi-line field with a character counter and the reminder "N'indiquez ni numéro de téléphone, ni adresse, ni information médicale."
  6. "Vérifiez votre offre" — summary (category, duties, when, pay, note, "Lieu : {commune}, {quartier}" from the verification checklist) and "Publier l'offre".
  After publishing: a result screen "Offre publiée." or "Offre envoyée. Nous la vérifions sous {hours} h." with "Retour à mes offres".
- `MyOfferDetailScreen(offerId)`: content, status, refusal or withdrawal reason; actions by status — draft: "Modifier", "Supprimer" (confirmation dialog "Supprimer ce brouillon ?"); in review or published: "Retirer l'offre" (confirmation "Retirer cette offre ? Les mini-jobbers ne la verront plus."); refused, withdrawn, closed: "Créer une offre semblable" (opens the form on the copy).

- [ ] **Step 1: Write the failing tests** — `my offers shows the empty state and Créer une offre`, `each status shows its French label`, `the whole creation flow sends the right draft then publishes` (assert the POST body and the `/send` call; first offer → "Offre envoyée. Nous la vérifions sous 24 h."), `a clean second offer shows Offre publiée.`, `Continuer stays disabled until a duty is ticked`, `a time outside the hours shows the message and blocks Continuer`, `pay outside the limits shows the message`, `back returns to the previous step and keeps the answers`, `a refused offer shows the reason and Créer une offre semblable`, `Retirer l'offre asks for confirmation then withdraws`, `Supprimer removes a draft`, `too many offers shows the server message on the summary`, `a verified householder lands on Mes offres and can open the checklist` (app test), `small phone with large text does not overflow` (list, each form step, detail).
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test && flutter analyze` in `petitgombo_core` and `householder` — expected all pass.
- [ ] **Step 5: Commit** — `feat(mobile): householder offer creation and my offers`.

---

### Task 9: Jobber screens

**Files:**
- Create: `mobile/packages/petitgombo_core/lib/src/offers/screens/offers_screen.dart`, `offer_detail_screen.dart`
- Modify: `lib/src/app/petitgombo_app.dart` (signed-in jobber → `OffersScreen`), `lib/petitgombo_core.dart`; delete `lib/src/home/home_placeholder_screen.dart` and its export if nothing uses it any more
- Test: `test/offers_screens_test.dart`, `test/app_test.dart`, `mobile/apps/jobber/test/app_test.dart`

**Interfaces:**
- Consumes: Task 7 `OffersController`.
- `OffersScreen({onSignOut})`: title "Offres"; commune filter (`DropdownButtonFormField`, first entry "Toutes les communes"); cards (category, `formatWhen`, `formatXof`, "{commune} · {quartier}"); skeleton; empty state "Aucune offre pour le moment." (with a commune selected: "Aucune offre dans cette commune pour le moment."); error banner with "Réessayer"; pull-to-refresh; "Voir plus" when `hasMore`; "Se déconnecter".
- `OfferDetailScreen(offer)`: category as title; "Tâches" with the duties as a list; "Quand" (`formatDay` and the hours); "Durée"; "Rémunération"; "Lieu" (commune, quartier); the note under "Précision" when present; an information row with a lock icon: "L'adresse exacte est communiquée seulement après une réservation confirmée."; a second row: "Tu pourras bientôt postuler aux offres." No apply or contact button.

- [ ] **Step 1: Write the failing tests** — `offers list shows category, when, pay and place`, `empty state`, `choosing a commune reloads with the filter and shows the commune empty state`, `Voir plus loads the next page`, `a failed load shows Réessayer and recovers`, `detail shows duties, place and the address notice, and no way to apply` (no `Postuler`, no phone number), `a signed-in jobber lands on Offres` (app test), `small phone with large text does not overflow` (list and detail).
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test && flutter analyze` in `petitgombo_core`, `jobber`, `householder`, `staff`; `flutter build apk --debug` in `householder` and `jobber` — expected all pass.
- [ ] **Step 5: Commit** — `feat(mobile): jobber offers list and detail`.

---

### Task 10: Documentation and end-to-end check

**Files:**
- Modify: `README.md`, `docs/threat-model.md`, `docs/deployment.md` (new settings only)

- [ ] **Step 1: README** — a "Job offers" section: how a householder publishes, the statuses, when an offer waits for staff, where staff moderate ("Offres"), how to edit "Catégories d'offres" (one duty per line, durations in minutes) and "Termes de modération", the two groups, the settings, and that the seeded categories, pay ranges and terms are placeholders to replace.
- [ ] **Step 2: Threat model** — "Lure listings": what is now built (only H1 householders at a confirmed address publish; screening; every first offer reviewed; no contact path) and what is not; "Address harvesting": offers expose commune and quartier only, asserted by `test_offers_api.py`.
- [ ] **Step 3: End-to-end manual check on a phone.** With the backend running and the phone connected: in the householder app create an offer and publish it; in the console publish it from "Offres" (a first offer is always reviewed); in the jobber app see it in "Offres" and open it; withdraw it in the householder app and see it disappear for the jobber. Record the result in the ledger, or why it could not be run.
- [ ] **Step 4: Commit** — `docs: job offers`.

---

## Spec coverage

| Spec section | Task |
|--------------|------|
| Catalogue, placeholders, limits | 1 |
| Screening signals | 2 |
| Offer fields, statuses, who may do what | 3 |
| Householder API | 4 |
| What a jobber sees, jobber API | 5 |
| Moderation, console, groups | 1, 6 |
| Householder app | 7, 8 |
| Jobber app | 7, 9 |
| Tests | each task |
| Threat model | 10 |
