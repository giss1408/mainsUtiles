# The Job and After Implementation Plan (stage 3 of 3 of piece 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A paid booking can be carried out and closed: the jobber checks in and out, the householder confirms (or time does), staff pay the jobber by hand and record it, a problem freezes the money until staff decide, and both sides review each other.

**Architecture:** Same Django app `apps/bookings`. New models `Payout`, `Report`, `Review`; new fields on `Booking` and `Payment`; services `jobs.py` (check-in, check-out, confirm, sweeps), `payouts.py`, `reports.py` (problems and dispute resolution), `reviews.py` (reviews and ratings); API additions under the existing booking routes; console pages in the Django admin; Flutter screens extend the booking screens of stage 2.

**Tech Stack:** Django 5.2, DRF, Celery beat, pytest; Flutter 3.24.2, Riverpod StateNotifier, Dio. No new package.

**Spec:** `docs/superpowers/specs/2026-11-13-applications-and-bookings-design.md` ("Completing", "Reviews", "Cancelling"). Earlier plans: `2026-11-13-applications.md`, `2026-11-13-payment-and-address-release.md`.

## Global Constraints

- Branch `feat/jobber-verification` continues. Commit after each task. Backend commands run from `backend/`: `.venv/bin/python -m pytest`, `.venv/bin/ruff check . && .venv/bin/ruff format --check .`, `makemigrations --check`, `manage.py spectacular --validate`. Never edit files, and never add a test file, while a full-suite run is in progress (write new test files into the scratchpad and move them in afterwards).
- Flutter 3.24.2; `flutter analyze` and `flutter test` in every package touched; `dart format -l 100`; no new package.
- French copy; householder "vous", jobber "tu". Amounts `3 500 FCFA`. Rules in services; limits are settings; errors `{"error", "message"}` via `apps/accounts/api/errors.py`; every transition and every view of sensitive data audited with `apps.audit.services.record` (an empty actor means the system acted).
- Nothing returned to a householder may contain a jobber's phone; nothing returned to a jobber may contain a householder's phone. **Exception:** the payout page shows the jobber's account phone to staff holding `bookings.make_payout`, audited, never cached, because staff must send the money to it (open decision: a separate payout number).
- Reviews are never visible to the other side before both are in or the window ends. A private report never notifies the other side.
- UI: existing tokens, one primary action per screen, loading/empty/error/data states, no overflow at 320dp with text scale 2.

**Out of scope:** the staff-app payouts and disputes queues (console first), strikes for repeated cancellations, push and SMS, live tracking, the door handshake, a geofence that blocks check-in (the distance is recorded and flagged, not enforced), payout to a number other than the account phone.

## Review Focus

1. **Paying the jobber twice, or paying a refunded booking.** A booking has one payout, recorded once; a refunded or split booking pays only its share. (Tasks 3, 4)
2. **The householder never answers.** After `RELEASE_TIMEOUT_HOURS` the job completes by itself; a jobber who never checks out ends in a dispute, not a payout. (Task 3)
3. **A jobber who never comes.** A paid booking whose end passes with no check-in is cancelled and the payment becomes a refund to make. (Task 3)
4. **A dispute raised after the timeout, or twice.** Refused once the booking is completed; a second report on the same booking is a note, not a second dispute. (Task 5)
5. **Reviews used as a weapon or a leak.** A comment with a number or "WhatsApp" is refused; one side's review is hidden until the other is in or seven days pass; a refused or disputed booking cannot be reviewed. (Task 6)

## File Structure

- Backend: `apps/bookings/models.py` (+ `Payout`, `Report`, `Review`; fields), `services/{jobs,payouts,reports,reviews}.py`, `api/{jobs_views,serializers,urls}.py`, `admin.py` + `templates/admin/bookings/`, `tasks.py`, migrations.
- Mobile core: `lib/src/applications/{job_models,job_api,job_controller}.dart` (or extensions of the stage 2 files), screens `{report_screen,review_screen}.dart`, changes to `my_booking_screen.dart` and `jobber_booking_screen.dart`.

---

### Task 1: Models, settings, permissions

**Files:** Modify `apps/bookings/models.py`, `config/settings.py`; migrations `0004_job_and_after.py`, `0005_payout_group.py`; test `tests/test_job_models.py`.

**Interfaces:**
- Produces: `Booking.checked_in_at, checked_out_at, completed_at` (null datetimes), `checkin_distance_m` (null int), `completion` (`""`, `"householder"`, `"timeout"`, `"staff"`). `Payment.refund_xof` (null int; null means the whole `pay_xof`... see Task 5). `Payout(id uuid, booking OneToOne PROTECT, amount_xof, status {due, paid}, due_at auto, reference TextField(blank, encrypted), paid_by FK null, paid_at null)`; constraint none beyond `OneToOne`. `Report(id uuid, booking FK PROTECT, author FK, kind {dispute, concern}, text, status {open, resolved}, outcome {"", release, refund, split}, jobber_xof null, resolved_by FK null, resolved_at null, note TextField(blank), created_at)`; constraint `one_open_dispute_per_booking` unique `booking` where `kind = dispute` and `status = open`. `Review(id uuid, booking FK PROTECT, author FK, about FK, stars 1..5, comment TextField(blank, max 300), created_at, published_at null)`; constraint `one_review_per_author_and_booking`. Permissions `make_payout` ("Peut enregistrer un paiement au jobber") and `resolve_dispute` on `Booking`. Group `payment_agent` gains `make_payout`, `resolve_dispute`, `view_payout`, `view_report`. Settings `RELEASE_TIMEOUT_HOURS=24`, `CHECKIN_EARLY_MINUTES=30`, `CHECKIN_FLAG_METERS=500`, `CHECKOUT_GRACE_HOURS=6`, `REVIEW_WINDOW_DAYS=7`, `REVIEW_COMMENT_MAX=300`.

- [ ] **Step 1: Write failing tests**: `test_one_payout_per_booking`, `test_one_open_dispute_per_booking_but_many_concerns`, `test_one_review_per_author_and_booking`, `test_stars_are_between_one_and_five`, `test_group_payment_agent_has_the_new_permissions`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** models, migrations (group via a data migration like `0003_payment_agent_group`), settings.
- [ ] **Step 4: Run** the full backend suite, ruff, `makemigrations --check`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): job, payout, report and review models`.

### Task 2: Check-in and check-out

**Files:** Create `services/jobs.py`; modify `apps/accounts/api/errors.py`; test `tests/test_check_in_out.py`.

**Interfaces:**
- Produces: `check_in(user, booking_id, *, lat: float | None, lng: float | None, accuracy_m: float | None = None) -> Booking` (the booked jobber, else `forbidden`; booking `confirmed` or `address_released`, else `invalid_state`; not earlier than `starts_at - CHECKIN_EARLY_MINUTES`, else `checkin_too_early`; not after the end, else `checkin_closed`; sets `checked_in`, `checked_in_at`; when a position is given and the householder's confirmed home pin exists, stores `checkin_distance_m` (haversine, metres); audit `booking.check_in` with the distance); `check_out(user, booking_id) -> Booking` (the booked jobber; booking `checked_in`, else `invalid_state`; sets `completion_pending` and `checked_out_at`; audit `booking.check_out`); `distance_m(a, b) -> int`; `needs_a_look(booking) -> bool` (distance known and above `CHECKIN_FLAG_METERS`). Error codes (French "tu"): `checkin_too_early` 409 "Tu pourras confirmer ton arrivée peu avant le début.", `checkin_closed` 409 "Le job est déjà terminé.".

- [ ] **Step 1: Write failing tests**: `test_check_in_moves_the_booking_and_records_the_distance`, `test_check_in_without_a_position_still_works_and_records_no_distance`, `test_too_early_and_too_late_have_their_codes`, `test_only_the_booked_jobber_of_a_confirmed_booking_can_check_in`, `test_a_far_check_in_is_flagged_for_staff`, `test_check_out_needs_a_check_in_and_sets_the_wait`, `test_distance_is_in_metres` (known pair of points), `test_double_tap_check_in_is_invalid_state`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): check in and check out`.

### Task 3: Confirmation, timeout and the sweeps

**Files:** Modify `services/jobs.py`, `tasks.py`, `config/settings.py` (beat); test `tests/test_job_completion.py`.

**Interfaces:**
- Produces: `confirm_done(user, booking_id) -> Booking` (the booking's householder; booking `completion_pending`, else `invalid_state`; `completed`, `completed_at`, `completion="householder"`; a `Payout` (`due`, `pay_xof`) is created; audit `booking.complete`); `complete_overdue(now=None) -> int` (bookings `completion_pending` whose `checked_out_at + RELEASE_TIMEOUT_HOURS` passed become `completed` with `completion="timeout"`, payout created, audit with an empty actor); `close_no_shows(now=None) -> int` (bookings `confirmed` or `address_released` whose end passed with no check-in become `cancelled` with `cancel_reason="no_show"`, their payment becomes `refund_due`, the offer is not reopened; audit with an empty actor); `flag_unclosed(now=None) -> int` (bookings `checked_in` whose end plus `CHECKOUT_GRACE_HOURS` passed become `disputed` with an open `Report(kind=dispute, author=jobber, text="Pas de départ enregistré")`); Celery tasks `complete_overdue_bookings`, `close_no_show_bookings`, `flag_unclosed_bookings`, hourly. A payout is created once per booking (`get_or_create`).

- [ ] **Step 1: Write failing tests**: `test_confirm_completes_the_booking_and_creates_one_payout`, `test_only_the_householder_can_confirm_and_only_while_pending`, `test_timeout_completes_by_itself_and_audits_the_system`, `test_a_booking_just_inside_the_timeout_is_left_alone`, `test_a_paid_booking_nobody_attended_is_cancelled_and_refunded`, `test_an_attended_booking_is_never_a_no_show`, `test_a_jobber_who_never_checks_out_ends_in_a_dispute_not_a_payout`, `test_confirming_twice_makes_one_payout` (sequential), `test_the_sweep_tasks_run`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): confirmation, timeout and sweeps`.

### Task 4: Paying the jobber

**Files:** Create `services/payouts.py`; modify `apps/accounts/api/errors.py`; test `tests/test_payouts.py`.

**Interfaces:**
- Produces (permission `bookings.make_payout`, else `forbidden`; locked rows; audited): `payout_queue()` (status `due`, oldest first); `payout_details(payout, *, staff) -> dict` (`{"amount_xof", "jobber_phone", "category_name", "completed_at"}`; audit `booking.payout.view`); `record_payout(payout, *, staff, reference: str) -> None` (payout `due` else `invalid_state`; reference required, 4 to 40 characters of letters, digits, dashes, dots and spaces, else `reference_invalid`; `paid`, encrypted reference, `paid_by`, `paid_at`; audit `booking.payout.pay`; a booking whose payment is not `confirmed` (refunded or refund due) is refused with `invalid_state`).

- [ ] **Step 1: Write failing tests**: `test_queue_lists_due_payouts_oldest_first`, `test_details_show_the_phone_only_to_the_right_holder_and_audit`, `test_record_payout_stores_an_encrypted_reference_once`, `test_a_refunded_booking_is_never_paid`, `test_reference_rules`, `test_without_the_permission_nothing_works`, `test_double_payout_is_invalid_state`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): pay the jobber`.

### Task 5: Problems and disputes

**Files:** Create `services/reports.py`; modify `services/payments.py` (refund amount), `apps/accounts/api/errors.py`; test `tests/test_reports.py`.

**Interfaces:**
- Produces: `report_problem(user, booking_id, *, text: str, dispute: bool) -> Report` (a party of the booking, else `forbidden`; text 3 to 500 characters, else `report_invalid`; a `dispute` needs the booking in `checked_in` or `completion_pending`, else `invalid_state`, and no open dispute already, else it is recorded as a `concern`; a dispute makes the booking `disputed`; a concern is allowed once the booking is `checked_in` or later, including `completed` within `REVIEW_WINDOW_DAYS`, and never notifies the other side; audit `booking.report`); `resolve_dispute(report, *, staff, outcome: str, note: str, jobber_xof: int | None = None) -> None` (permission `bookings.resolve_dispute`; the report is an open dispute on a `disputed` booking, else `invalid_state`; note required (`reason_required`); `release`: booking `completed` (`completion="staff"`), payout created for `pay_xof`; `refund`: booking `cancelled`, payment `refund_due`; `split`: `jobber_xof` strictly between 0 and `pay_xof` (else `split_invalid`), payout created for `jobber_xof`, payment `refund_due` with `refund_xof = pay_xof - jobber_xof` (the platform keeps its fee); audit `booking.dispute.resolve`). `record_refund` and the refund queue show `refund_xof or pay_xof`.

- [ ] **Step 1: Write failing tests**: `test_a_dispute_freezes_the_booking_and_the_payout`, `test_only_a_party_can_report_and_a_stranger_gets_forbidden`, `test_a_dispute_after_completion_is_refused_but_a_concern_is_kept`, `test_a_second_dispute_becomes_a_concern`, `test_a_concern_does_not_change_the_booking`, `test_release_pays_the_jobber_in_full`, `test_refund_cancels_and_asks_for_a_refund`, `test_split_pays_part_and_refunds_the_rest`, `test_split_amounts_are_validated`, `test_resolving_needs_the_permission_a_note_and_an_open_dispute`, `test_text_rules`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): problems and disputes`.

### Task 6: Reviews and ratings

**Files:** Create `services/reviews.py`; modify `services/applications.py` (`applicants`, `householder_trust` use real ratings), `tasks.py`, `config/settings.py` (beat); test `tests/test_reviews.py`.

**Interfaces:**
- Produces: `submit_review(user, booking_id, *, stars: int, comment: str) -> Review` (a party of a `completed` booking, else `forbidden` / `invalid_state`; one per author, else `already_reviewed`; within `REVIEW_WINDOW_DAYS` of `completed_at`, else `review_closed`; stars 1 to 5, else `stars_invalid`; comment stripped, at most `REVIEW_COMMENT_MAX`, no `contact_in` (`message_contact_details`); about = the other party; when both reviews exist both get `published_at = now`); `publish_due(now=None) -> int` (reviews whose window ended are published alone); `my_review_state(user, booking_id) -> dict` (`{"mine": {stars, comment} | None, "theirs": {stars, comment} | None}`, `theirs` only once published); `rating_of(user) -> {"average": float | None, "count": int}` (published reviews about the user). `applicants()` returns `rating = average` and `householder_trust()` the same; a Celery task `publish_due_reviews`, hourly.

- [ ] **Step 1: Write failing tests**: `test_a_review_is_hidden_until_both_are_in`, `test_both_become_visible_together_with_the_same_time`, `test_the_window_publishes_a_lone_review`, `test_only_completed_bookings_by_a_party_once`, `test_a_disputed_refunded_or_cancelled_booking_cannot_be_reviewed`, `test_comment_with_contact_details_is_refused`, `test_stars_and_length_rules`, `test_rating_averages_published_reviews_only`, `test_the_applicant_card_and_trust_line_carry_the_rating`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): reviews and ratings`.

### Task 7: API

**Files:** Create `apps/bookings/api/jobs_views.py`; modify `apps/bookings/api/{urls,serializers,payments_views,jobber_views}.py`; test `tests/test_jobs_api.py`.

**Interfaces:**
- Produces (jobber): `POST my-bookings/<uuid>/check-in` `{lat?, lng?, accuracy_m?}`, `POST my-bookings/<uuid>/check-out`, `POST my-bookings/<uuid>/report` `{text, dispute}`, `GET/POST my-bookings/<uuid>/review` (`GET` → review state; `POST {stars, comment}` → 201). (householder): `POST my-offers/<uuid>/booking/confirm`, `POST my-offers/<uuid>/booking/report`, `GET/POST my-offers/<uuid>/booking/review`. The booking detail (householder) gains `checked_in_at`, `checked_out_at`, `auto_confirm_at`, `reviewable` and the jobber's `rating`; the jobber's `my-bookings` rows gain `checked_in_at`, `checked_out_at`, `payout` (`none`, `due`, `paid`), `reviewable`. Errors via `error_response`; a foreign id is 404.

- [ ] **Step 1: Write failing tests**: `test_jobber_checks_in_and_out_through_the_api`, `test_householder_confirms_and_the_payout_exists`, `test_report_and_dispute_through_the_api`, `test_review_flow_through_the_api_hides_the_other_side_until_both_are_in`, `test_detail_and_rows_carry_the_new_fields`, `test_no_response_contains_the_other_sides_phone`, `test_roles_and_foreign_ids`, `test_the_schema_validates`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite, ruff, spectacular validate. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): job, report and review API`.

### Task 8: Console for payouts, disputes and reports

**Files:** Modify `apps/bookings/admin.py`, `console_views.py`; create templates `payout_review.html`, `report_review.html`; test `tests/test_jobs_console.py`.

**Interfaces:**
- Produces: `PayoutAdmin` ("Paiements à verser": queue "À verser" default, "Versés"; the page shows the amount, the jobber's phone (audited, `no-store`), the category, and the reference form), `ReportAdmin` ("Signalements": queue "Litiges ouverts" default, "Remarques", "Tous"; the dispute page shows the booking, both sides' first names, the text, the check-in distance and times, the payment state, and the resolution form: outcome, jobber amount for a split, note). Routes `bookings_payout_pay`, `bookings_report_resolve`. Lists show no phone, no text, no reference. Opening a payout or a report audits `booking.payout.view` / `booking.report.view`.

- [ ] **Step 1: Write failing tests**: `test_payout_queue_page_and_recording`, `test_payout_page_shows_the_phone_audits_and_is_no_store`, `test_lists_show_no_phone_text_or_reference`, `test_dispute_page_and_each_resolution`, `test_concerns_are_listed_but_have_no_resolution_form`, `test_without_the_permission_gets_403`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(console): payouts, disputes and reports`.

### Task 9: Flutter models, API and controllers

**Files:** Modify `lib/src/applications/{application_models,applications_api,booking_controller,applications_controller}.dart`; create `lib/src/applications/review_models.dart`; tests `test/job_controller_test.dart`, extended model tests.

**Interfaces:**
- Produces: `BookingDetail` gains `checkedInAt`, `checkedOutAt`, `autoConfirmAt`, `reviewable`, `jobberRating`; `JobberBooking` gains `checkedInAt`, `checkedOutAt`, `payout`, `reviewable`; `ReviewState {mine, theirs}` with `ReviewItem {stars, comment}`. `BookingController` (householder): `confirmDone()`, `report(text, {dispute})`, `loadReview()`, `submitReview(stars, comment)`. `ApplicationsController` (jobber): `checkIn(bookingId)` (reads `positionReaderProvider`; a refused position still checks in without one), `checkOut(id)`, `report(id, text, {dispute})`, `loadReview(id)`, `submitReview(id, stars, comment)`. Errors show the server text; every change reloads.

- [ ] **Step 1: Write failing tests**: models parse the new fields; check-in sends the position and survives a refused permission; check-out, confirm and report send their bodies and reload; a review submit shows the server text on refusal; `theirs` is null until published; offline message.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** package tests and analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): job, report and review models, API and controllers`.

### Task 10: Householder screens

**Files:** Modify `screens/my_booking_screen.dart`, `application_copy.dart`; create `screens/{report_screen,review_screen}.dart`; tests `test/job_householder_screens_test.dart`.

**Interfaces:** The booking screen words the new states ("Le jobber est arrivé à 08:05", "Job à confirmer avant {date}", "Job terminé"), shows "Confirmer que c'est fait" (with a dialog) while `completion_pending`, "Signaler un problème" (to `ReportScreen`: a text field and a choice "Faire geler le paiement et prévenir l'équipe" vs "Remarque privée") from check-in on, and after completion a review card: "Donnez votre avis" (to `ReviewScreen`: five stars, a comment of up to 300 characters, "Publié quand l'autre personne aura donné le sien, ou après 7 jours"), then the state "Avis envoyé" and, once published, both reviews. The applicants card shows the rating when there is one.

- [ ] **Step 1: Write failing tests**: `test_states_are_worded`, `test_confirm_asks_to_confirm_and_calls_the_api`, `test_report_screen_sends_a_dispute_or_a_concern`, `test_review_screen_validates_and_sends`, `test_the_other_review_shows_only_when_published`, `test_applicant_card_shows_the_rating`, `test_screens_fit_320dp_at_double_text_size`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** package and householder tests, analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): householder confirms, reports and reviews`.

### Task 11: Jobber screens

**Files:** Modify `screens/jobber_booking_screen.dart`; reuse `report_screen.dart`, `review_screen.dart`; tests `test/job_jobber_screens_test.dart`.

**Interfaces:** The jobber's job screen shows "Je suis arrivé(e)" from `CHECKIN_EARLY_MINUTES` before the start (reads the position; if it cannot, checks in without and says so), "J'ai terminé" once checked in, the wait "Le ménage a jusqu'à {date} pour confirmer", "Signaler un problème", the payout state ("Paiement en préparation" / "Paiement envoyé"), and the review card after completion. "Mes jobs" words the new states.

- [ ] **Step 1: Write failing tests**: `test_check_in_button_appears_in_time_and_sends_the_position`, `test_check_in_without_a_position_says_so_and_still_works`, `test_check_out_and_the_wait_are_worded`, `test_payout_states_are_worded`, `test_report_and_review_reuse_the_shared_screens`, `test_screens_fit_320dp_at_double_text_size`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** package and jobber tests, analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): jobber checks in, finishes and reviews`.

### Task 12: Docs and whole verification

**Files:** modify `README.md` (a "The job and after" section), `docs/threat-model.md`, `next_steps.md`.

Threat-model rows: a payout made twice or on a refunded booking; a jobber paid without doing the job (check-in distance, householder confirmation, dispute freeze); a householder who never confirms (timeout); a false dispute to avoid paying (one dispute, staff decide, the payout frozen only until then); review blackmail or leak (hidden until both, contact details refused); insider reads a jobber's phone on the payout page (right-holders only, audited, not cached).

- [ ] **Step 1:** Run every suite: backend pytest, ruff, `makemigrations --check`, spectacular validate; analyze and test in `petitgombo_core`, `apps/jobber`, `apps/householder`, `apps/staff`; build the jobber and householder debug APKs. Expected: all pass.
- [ ] **Step 2: Commit** `docs: the job and after`.
