# Applications Implementation Plan (stage 1 of 3 of piece 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A J1 jobber applies to a published offer; the householder sees the applicants, accepts one, and a booking exists in state `accepted`; the offer leaves the jobbers' list.

**Architecture:** A new Django app `apps/bookings` with `Application` and `Booking` models and a service module holding every rule; thin DRF views for both roles; Flutter code in `petitgombo_core/src/applications/`, wired into the existing offer screens of the jobber and householder apps. Payment, the address release, check-in and reviews are stages 2 and 3; this stage only declares the later booking states.

**Tech Stack:** Django 5.2, DRF, drf-spectacular, Celery beat, pytest; Flutter 3.24.2, Riverpod StateNotifier, Dio.

**Spec:** `docs/superpowers/specs/2026-11-13-applications-and-bookings-design.md` (product spec: `skill.md`).

## Global Constraints

- Branch `feat/jobber-verification` continues; if it was merged, branch `feat/applications` from `main`. Commit after each task.
- Backend commands run from `backend/`: `.venv/bin/python -m pytest`, `.venv/bin/ruff check . && .venv/bin/ruff format --check .`, `.venv/bin/python manage.py makemigrations --check`.
- Flutter 3.24.2 (Dart 3.5), no new packages; `flutter analyze` and `flutter test` in every package touched; `dart format -l 100`.
- French copy; code, comments and logs in English. Jobber app says "tu", householder app "vous".
- Rules live in services. Every limit is a setting read from the environment. Errors are `{"error": code, "message": french}` via `apps/accounts/api/errors.py`. Every change writes an audit row with `apps.audit.services.record(actor, action, obj, **extra)`.
- J1 is `jobber_tier(user) == "J1"`; H1 is `householder_tier`.
- Nothing returned to a jobber may contain the householder's name, phone, id or exact address; nothing returned to a householder may contain a jobber's phone, last name, photo or id other than the application and booking ids. Tests assert this on raw response text.
- Flutter UI uses the existing tokens (`Gaps`, `Radii`, `AppColors`, `FlowScaffold`, `ChoiceCard`, `BusyButton`, `MessageBanner`), one primary action per screen, loading/empty/error/data states, no overflow at 320dp with text scale 2.
- Amounts `3 500 FCFA`; dates formatted by the existing `offer_format.dart` helpers.

**Out of scope (stages 2 and 3, do not build):** payment, `confirmed` and later transitions, address release, cancellation, check-in/out, reviews, ratings, disputes, notifications.

## Review Focus

1. **Two taps, two devices on "Accepter".** The second call answers `invalid_state` and exactly one booking exists. (Task 3)
2. **An applicant who stops being J1 between applying and being accepted.** Accepting is refused with `applicant_not_verified`; the householder is told. (Task 3)
3. **The offer is withdrawn or starts while applicants wait.** Nobody can be accepted; the sweep declines the pending applications. (Task 3)
4. **A message hiding a number or a handle** ("zéro sept…" is accepted, but `07 08 09 10 11`, `0708.09.10.11`, `+225 0708091011`, `WhatsApp`, `whatsapp` are refused). (Task 2)
5. **Withdraw then apply again; apply to two offers at the same hour; hit the caps.** Reapplying works; overlap and both caps refuse with their own code. (Task 2)

## File Structure

- `backend/apps/bookings/` (new): `models.py`, `services/applications.py`, `api/{serializers,jobber_views,views,urls}.py`, `admin.py`, `tasks.py`.
- Modify: `backend/apps/listings/models.py` (`Offer.Status.BOOKED`), `services/screening.py` (public `contact_in`), `api/jobber_views.py` and `api/views.py` (extra fields), `config/settings.py`, `config/api_urls.py`, `apps/accounts/api/errors.py`.
- `mobile/packages/petitgombo_core/lib/src/applications/` (new): `application_models.dart`, `applications_api.dart`, `applications_controller.dart`, `applicants_controller.dart`, `application_copy.dart`, `screens/{apply_screen,my_applications_screen,applicants_screen}.dart`.

---

### Task 1: Models, settings, the `booked` offer status

**Files:**
- Create: `backend/apps/bookings/{__init__,apps,models}.py`, migration `0001_initial.py`
- Modify: `backend/apps/listings/models.py` (+ migration), `backend/config/settings.py` (INSTALLED_APPS, settings), `backend/apps/listings/services/screening.py`
- Test: `backend/tests/test_booking_models.py`

**Interfaces:**
- Produces: `Application(id uuid, offer FK PROTECT, jobber FK PROTECT, message TextField(blank), status, created_at, decided_at null)`, `Application.Status` = `pending/accepted/declined/withdrawn`; constraint `one_live_application` unique `(offer, jobber)` where status in (`pending`,`accepted`). `Booking(id uuid, offer FK PROTECT, application OneToOne PROTECT, householder FK, jobber FK, category_name, duties JSON, starts_at, duration_minutes, pay_xof, commune, quartier, status, accepted_at, created_at)`, `Booking.Status` = `accepted, confirmed, address_released, checked_in, completion_pending, completed, cancelled, expired, disputed, safety_hold`; `Booking.LIVE` = every status except `cancelled`, `expired`, `completed`; constraint `one_live_booking_per_offer` unique `offer` where status in `LIVE`. `Offer.Status.BOOKED = "booked", "Réservée"` (not added to `OPEN_STATUSES`, so a booked offer frees a slot and `tidy` never withdraws it). `screening.contact_in(text: str) -> bool`: true for an email, a phone (the existing patterns) or an `off_platform` moderation term. Settings `APPLICATIONS_MAX_OPEN=5`, `APPLICATIONS_MAX_PER_OFFER=20`, `APPLICATION_MESSAGE_MAX=200`.

- [ ] **Step 1: Write failing tests**: `test_a_jobber_has_one_live_application_per_offer`, `test_a_withdrawn_application_does_not_block_a_new_one`, `test_an_offer_has_one_live_booking`, `test_a_cancelled_booking_frees_the_offer`, `test_booked_is_not_an_open_status`, `test_contact_in_catches_numbers_emails_and_off_platform_terms` (`07 08 09 10 11`, `0708.09.10.11`, `+225 0708091011`, `a@b.ci`, `WhatsApp`, `whatsapp`; not "Je suis disponible le matin").
- [ ] **Step 2: Run** them. Expected: FAIL (module missing).
- [ ] **Step 3: Implement** the app, models, constraints, migrations (`makemigrations bookings listings`), settings, `contact_in`.
- [ ] **Step 4: Run** the full backend suite, ruff, `makemigrations --check`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): application and booking models`.

### Task 2: Apply and withdraw

**Files:** Create `backend/apps/bookings/services/applications.py`; modify `apps/accounts/api/errors.py`; test `backend/tests/test_applications.py`.

**Interfaces:**
- Produces: `class BookingError(Exception)` with `.code`; `apply(user, offer_id, message: str) -> Application`; `withdraw(user, application_id) -> Application`; `my_applications(user)` (queryset, newest first, `select_related("offer")`). A foreign id is `forbidden`.
- Error codes (STATUS, MESSAGES in French "tu"): `jobber_verification_required` 403 "Termine ta vérification pour postuler."; `offer_unavailable` 409 "Cette offre n'est plus disponible."; `already_applied` 409 "Tu as déjà postulé à cette offre."; `too_many_applications` 409 "Tu as déjà {n} candidatures en attente." (no format: "Tu as trop de candidatures en attente. Retire-en une."); `offer_full` 409 "Cette offre a déjà beaucoup de candidatures."; `application_overlap` 409 "Tu as déjà un job à cette heure-là."; `message_contact_details` 400 "Ne mets pas de numéro ni de contact dans ton message."; `message_too_long` 400 "Ton message est trop long."; `applicant_not_verified` 409 "Ce candidat n'est plus vérifié."; reuse `forbidden`, `invalid_state`.
- Rules for `apply`: jobber role and active, else `forbidden`; J1, else `jobber_verification_required`; offer `published` and `starts_at > now`, else `offer_unavailable`; the offer row locked; message stripped, ≤ `APPLICATION_MESSAGE_MAX` and `contact_in` false (an empty message is allowed); no live application of this jobber on this offer; pending applications of the jobber < `APPLICATIONS_MAX_OPEN`; pending ones on the offer < `APPLICATIONS_MAX_PER_OFFER`; no live booking of the jobber overlapping `[starts_at, starts_at + duration)`; no `disputed` booking of the jobber. Audit `booking.application.apply`. `withdraw`: pending only, else `invalid_state`; audit `booking.application.withdraw`.

- [ ] **Step 1: Write failing tests**: `test_apply_stores_the_application_and_audits`, `test_only_a_j1_jobber_can_apply`, `test_householder_and_inactive_user_forbidden`, `test_unpublished_started_or_booked_offer_is_unavailable`, `test_second_application_to_the_same_offer_is_refused`, `test_message_with_contact_details_is_refused` (parametrized on the Review Focus 4 list), `test_message_length_and_empty_message`, `test_open_applications_cap_and_offer_cap`, `test_overlapping_booking_is_refused_and_a_neighbouring_one_is_not`, `test_withdraw_then_apply_again_works`, `test_withdraw_only_pending_and_only_own`, `test_a_jobber_with_a_dispute_cannot_apply`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** the service and the error entries. Reuse `jobber_tier` and `screening.contact_in`.
- [ ] **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): apply to an offer and withdraw`.

### Task 3: Applicants, accept, trust lines, sweep

**Files:** Modify `services/applications.py`, create `apps/bookings/tasks.py`, modify `config/settings.py` (beat `close-stale-applications` hourly); test `backend/tests/test_accept.py`.

**Interfaces:**
- Produces: `applicants(user, offer_id) -> list[dict]` (householder owner only, else `forbidden`; pending applications oldest first; each `{"id", "first_name", "tier": "J1", "jobs_done": int, "rating": None, "message", "created_at"}`; `first_name` is the first word of the confirmed identity's name, "Jobber" if none; `jobs_done` counts the jobber's `completed` bookings); `accept(user, application_id) -> Booking` (see below); `householder_trust(householder) -> {"tier": "H1", "jobs_done": int, "rating": None}` (`jobs_done` counts completed bookings as householder); `close_stale() -> int` (pending applications whose offer is not `published` or has started become `declined`, `decided_at` set); Celery task `close_stale_applications`.
- `accept`: one transaction, the offer row locked then the application row: owner of the offer and householder role, else `forbidden`; application `pending`, else `invalid_state`; offer `published` and not started, else `offer_unavailable`; the jobber is still J1, else `applicant_not_verified`; creates the `Booking` (`accepted`, snapshot copied from the offer, `accepted_at` now); application `accepted`; every other pending application on the offer `declined`; offer `booked`. Audit `booking.accept` on the booking.

- [ ] **Step 1: Write failing tests**: `test_applicants_list_has_first_name_tier_and_message_and_nothing_else` (raw text has no phone, last name, photo or user id), `test_only_the_owner_sees_applicants`, `test_accept_creates_one_booking_declines_the_others_and_books_the_offer`, `test_second_accept_is_invalid_state_and_one_booking_exists` (two sequential calls; plus a `transaction=True` test with two threads), `test_accept_refused_when_the_applicant_lost_j1`, `test_accept_refused_when_the_offer_is_withdrawn_or_started`, `test_booked_offer_is_not_visible_to_jobbers`, `test_close_stale_declines_pending_applications_of_dead_offers`, `test_householder_trust_counts_only_completed_bookings`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** and register the beat entry.
- [ ] **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): applicants and accepting one`.

### Task 4: Jobber API

**Files:** Create `apps/bookings/api/{serializers,jobber_views,urls}.py`; modify `config/api_urls.py`, `apps/listings/api/jobber_views.py`; test `backend/tests/test_applications_api.py`.

**Interfaces:**
- Produces (role jobber, `IsJobberRole` from listings): `POST offers/<uuid>/apply` body `{message}` → 201 `{id, offer_id, status, created_at}`; `GET my-applications` → `{results: [{id, status, message, created_at, offer: {id, category_name, starts_at, duration_minutes, pay_xof, commune, quartier, status}, booking: {id, status} | null}]}`; `POST my-applications/<uuid>/withdraw` → the application; `GET my-bookings` → `{results: [{id, status, category_name, starts_at, duration_minutes, pay_xof, commune, quartier}]}` (never an address). `GET offers/<uuid>` gains `householder: {tier, jobs_done, rating}` and `my_application: {id, status} | null`. `BookingError` maps through `error_response`; a foreign application id is 404.

- [ ] **Step 1: Write failing tests**: `test_apply_returns_201_and_the_list_shows_it`, `test_each_error_code_has_its_status_and_french_message`, `test_offer_detail_carries_the_trust_line_and_my_application`, `test_no_jobber_response_contains_the_householder_name_phone_or_id` (raw text), `test_my_bookings_shows_the_accepted_booking_without_address`, `test_householder_gets_403_on_jobber_routes`, `test_withdraw_of_someone_elses_application_is_404`, `test_the_schema_validates` (spectacular exit 0).
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** views and URLs.
- [ ] **Step 4: Run** the full suite, ruff, `manage.py spectacular --validate`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): jobber API for applications`.

### Task 5: Householder API

**Files:** Create `apps/bookings/api/views.py`; modify `apps/bookings/api/urls.py`, `apps/listings/api/views.py` and its serializers; test `backend/tests/test_applicants_api.py`.

**Interfaces:**
- Produces (householder): `GET my-offers/<uuid>/applicants` → `{results: [...applicants...]}`; `POST my-offers/<uuid>/applicants/<uuid>/accept` → 201 `{id, status, jobber_first_name, category_name, starts_at, pay_xof}`. `GET my-offers/<uuid>` and the list gain `applicants_count` (pending) and `booking: {id, status, jobber_first_name} | null`. Another householder's offer or an application not on this offer is 404.

- [ ] **Step 1: Write failing tests**: `test_applicants_endpoint_lists_only_pending_with_no_phone_or_last_name`, `test_accept_returns_the_booking_and_the_offer_shows_booked`, `test_accept_twice_is_409`, `test_other_householders_offer_is_404`, `test_jobber_gets_403_on_householder_routes`, `test_my_offers_carry_applicants_count_and_booking`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite, ruff, spectacular validate. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): householder API for applicants`.

### Task 6: Console, threat model, README

**Files:** Create `apps/bookings/admin.py`; modify `docs/threat-model.md`, `README.md`; test `backend/tests/test_bookings_console.py`.

**Interfaces:** Produces read-only `ApplicationAdmin` and `BookingAdmin` (no add, change or delete; list shows offer category, status, dates; the jobber appears by phone, the message is not listed). Threat-model rows: accomplice or sock-puppet applicants (one live application, caps, J1 re-checked at accept), message used to move off-platform (screened), double accept (row locks, one live booking constraint), identity leak through the applicant card (first name only, tests), applying while a booking overlaps. README: a section "Applications" (rules, settings, the stage plan).

- [ ] **Step 1: Write failing tests**: `test_staff_can_list_applications_and_bookings_but_not_edit`, `test_the_list_pages_show_no_message_text`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement** and write the docs. **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(console): applications and bookings, docs`.

### Task 7: Flutter models, API and controllers

**Files:** Create `lib/src/applications/{application_models,applications_api,applications_controller,applicants_controller,application_copy}.dart`; modify `lib/src/offers/offer_models.dart` (`PublicOffer.householder`, `.myApplication`; `MyOffer.applicantsCount`, `.booking`), `lib/petitgombo_core.dart`; tests `test/application_models_test.dart`, `test/applications_controller_test.dart`, `test/applicants_controller_test.dart`.

**Interfaces:**
- Produces: `ApplicationStatus {pending, accepted, declined, withdrawn}`; `JobberApplication`, `ApplicantCard`, `BookingSummary`, `HouseholderTrust`; `ApplicationsApi.apply(access, offerId, message)`, `.mine(access)`, `.withdraw(access, id)`, `.myBookings(access)`, `.applicants(access, offerId)`, `.accept(access, offerId, applicationId)`; `ApplicationsController` (state: `applications`, `bookings`, `loading`, `sending`, `error`; `load()`, `apply(offerId, message) -> bool`, `withdraw(id)`), `ApplicantsController` (family by offer id: `load()`, `accept(applicationId) -> BookingSummary?`); the French `ApplicationCopy`.
- Rules: after `apply` the offer detail's `myApplication` is set locally; server messages shown as the error; `invalid_state` on accept reloads the list.

- [ ] **Step 1: Write failing tests**: `fromJson` of each model; apply sends `{message}`; a refused apply keeps the message and shows the server text; `withdraw` updates the row; `accept` returns the booking and reloads; `invalid_state` on accept reloads; offline shows the retry message.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the package tests and analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): application models, API and controllers`.

### Task 8: Jobber screens

**Files:** Create `lib/src/applications/screens/{apply_screen,my_applications_screen}.dart`; modify `offers/screens/offer_detail_screen.dart`, `offers/screens/offers_screen.dart`, `verification/screens/checklist_screen.dart` only if a route is needed; tests `test/apply_screens_test.dart`.

**Interfaces:** Offer detail shows the householder trust line ("Particulier vérifié · N jobs") and one primary button: "Postuler" (opens `ApplyScreen`: optional message, counter, summary of when and pay, send), or "Termine ta vérification" (opens the checklist) when the jobber is not J1, or the status ("Candidature envoyée", "Retirer ma candidature") when `myApplication` is set. The offers screen gets a "Mes candidatures" card under the verification card, opening `MyApplicationsScreen` (rows: category, when, status chip with an icon and text; accepted rows say "Acceptée : l'hôte doit encore payer"; pending rows can be withdrawn; empty and error states).

- [ ] **Step 1: Write failing tests**: `test_offer_detail_shows_apply_for_j1_and_the_checklist_link_otherwise`, `test_apply_sends_the_message_and_shows_the_sent_state`, `test_a_refused_message_stays_in_the_field_with_the_server_text`, `test_my_applications_lists_withdraws_and_shows_the_accepted_text`, `test_screens_fit_320dp_at_double_text_size`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** package tests, jobber app tests, analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): jobber applies to offers`.

### Task 9: Householder screens

**Files:** Create `lib/src/applications/screens/applicants_screen.dart`; modify `offers/screens/my_offer_detail_screen.dart`, `offers/screens/my_offers_screen.dart`; tests `test/applicants_screen_test.dart`.

**Interfaces:** A published offer with applicants shows "N candidat(s)" opening `ApplicantsScreen`: one card per applicant (first name, "J1", jobs done, message, "Accepter" with a confirm dialog "Accepter {prénom} ? Les autres candidats seront refusés."). After accepting, the offer shows the status "Réservée" and the booking line "{prénom} · en attente de votre paiement" (payment arrives in stage 2). The list row shows the applicants count. Empty state: "Pas encore de candidat."

- [ ] **Step 1: Write failing tests**: `test_applicants_are_listed_with_first_name_and_message`, `test_accept_asks_to_confirm_then_shows_the_booked_state`, `test_a_failed_accept_shows_the_server_text`, `test_my_offers_row_shows_the_applicants_count`, `test_screens_fit_320dp_at_double_text_size`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** package and householder tests, analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): householder reviews and accepts applicants`.

### Task 10: Whole-stage verification and handoff docs

**Files:** modify `README.md`, `next_steps.md`.

- [ ] **Step 1:** Run every suite: backend pytest, ruff, `makemigrations --check`, spectacular validate; `flutter analyze` and `flutter test` in `petitgombo_core`, `apps/jobber`, `apps/householder`, `apps/staff`; build the jobber and householder debug APKs. Expected: all pass.
- [ ] **Step 2:** Update `next_steps.md`: stage 1 done; stage 2 (payment, address release, cancellation) is next; keep the open business decisions (provider, fee, SMS).
- [ ] **Step 3: Commit** `docs: applications stage done`.
