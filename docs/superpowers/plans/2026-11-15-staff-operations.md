# Staff Operations Implementation Plan (stage 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Staff send every user message by WhatsApp from a queue, see alerts for what waits, and work payouts and disputes in the staff app.

**Architecture:** A `Message` model and `services/messages.py` in `apps/bookings`; hooks at the existing audit points and two sweeps; staff API views `staff_ops_views.py` over the existing `payouts` and `reports` services; an `OpsController` beside `StaffController` in the staff app.

**Tech Stack:** Django 5.2, DRF, Celery beat, pytest; Flutter 3.24.2, Riverpod, Dio. No new package.

**Spec:** `docs/superpowers/specs/2026-11-15-staff-operations-design.md`; README "Messages and alerts".

## Global Constraints

- Branch `feat/staff-operations` (stacked on `feat/jobber-verification`). Commit after each task. The owner asked for the full suites once, at the end; each task runs its own tests.
- Backend from `backend/`: `.venv/bin/python -m pytest`, ruff check and format, `makemigrations --check`, `spectacular --validate`. Postgres must be up (`docker compose up -d db`).
- Flutter 3.24.2; `flutter analyze`, `flutter test`, `dart format -l 100`; no new package.
- French copy; householder "vous", jobber "tu". Errors `{"error", "message"}` via `apps/accounts/api/errors.py`. Every send and every view of sensitive data audited.
- A message never contains an address, a full name, a phone number or a payment reference. The recipient's number exists only inside the returned `whatsapp_url`. Every staff response is `no-store`.
- No new money rule: payouts and disputes call `services/payouts.py` and `services/reports.py` unchanged.

## Review Focus

1. **A stale message sent anyway** (the booking was cancelled meanwhile): dropped at send, 409. (Task 2, 4)
2. **Two staff sending the same message:** the second gets `invalid_state`, one link only. (Task 2)
3. **A duplicate message per event** (accept retried, sweep run twice): one pending per offer, recipient and kind. (Task 2, 3)
4. **A message hook breaking a money transition:** a failure to queue never blocks the booking change... the queue write is in the same transaction and must not raise for a missing recipient. (Task 3)
5. **A staff member without the right reading a phone, a text or a count.** (Task 4, 5, 6)

---

### Task 1: Message model, settings, permission
**Files:** `apps/bookings/models.py`, `config/settings.py`, migrations `0006_message.py`, `0007_message_groups.py`; test `tests/test_message_models.py`.
**Produces:** `Message(id uuid, offer FK PROTECT, booking FK null PROTECT, recipient FK PROTECT, kind (16 choices of the spec), urgent bool, status {pending, sent, dropped}, created_at, sent_by FK null, sent_at null)`; constraint `one_pending_message_per_kind` unique (offer, recipient, kind) where status pending; permission `send_message`. Groups `payment_agent` and `enrolment_agent` gain `send_message`, `view_message`. Settings `PAYMENT_REMINDER_HOURS=4`, `MESSAGE_LATE_MINUTES=60`, `MESSAGE_URGENT_LATE_MINUTES=15`, `PAYOUT_LATE_HOURS=24`, `DISPUTE_LATE_HOURS=24`.
- [ ] Tests `test_one_pending_message_per_offer_recipient_and_kind`, `test_a_sent_message_allows_a_new_one`, `test_both_groups_can_send_messages`; run (FAIL); implement; run (PASS); commit `feat(bookings): message model`.

### Task 2: Messages service
**Files:** create `services/messages.py`; `apps/accounts/api/errors.py`; test `tests/test_messages_service.py`.
**Produces:** `queue(kind, *, booking=None, offer=None, to) -> Message | None` (idempotent while one is pending; `None` recipient ignored; urgent for `pay_reminder`, `address_available`); `text_of(message) -> str`; `still_true(message, now=None) -> bool`; `send_queue()` (pending, urgent first then oldest); `is_late(message, now=None) -> bool`; `preview(message, *, staff) -> dict` (`text`, `category_name`; audit `booking.message.view`); `send(message, *, staff) -> str` (permission `bookings.send_message` else `forbidden`; row lock; not pending → `invalid_state`; not still true → status `dropped`, audit `booking.message.drop`, raises `message_stale` **after committing the drop**; else `sent`, `sent_by`, `sent_at`, audit `booking.message.send`, returns the WhatsApp link). Error `message_stale` 409 "Ce message n'est plus d'actualité : il a été retiré.".
- [ ] Tests `test_queue_is_idempotent_while_pending`, `test_every_kind_has_a_text_without_sensitive_data` (no phone, no full name, no reference, no quartier), `test_householder_texts_say_vous_and_jobber_texts_say_tu`, `test_send_returns_a_link_to_the_recipient_and_marks_sent`, `test_a_stale_message_is_dropped_not_sent`, `test_sending_twice_is_invalid_state`, `test_without_the_permission_nothing_is_sent`, `test_urgent_first_then_oldest_and_late_markers`; FAIL; implement; PASS; commit `feat(bookings): messages service`.

### Task 3: Hooks and sweeps
**Files:** `services/{applications,payments,bookings,jobs,payouts,reports}.py`, `tasks.py`, `config/settings.py` (beat); test `tests/test_message_hooks.py`.
**Produces:** each event of the spec's table queues its message(s) inside the same transaction. Sweeps in `messages.py`: `queue_pay_reminders(now=None) -> int`, `queue_address_available(now=None) -> int`; Celery task `queue_due_messages` every 900 s.
- [ ] Tests one per event: `test_first_application_tells_the_householder_once`, `test_accept_tells_the_jobber`, `test_confirm_tells_both_and_refuse_tells_the_householder`, `test_check_out_asks_the_householder_to_confirm`, `test_completion_invites_both_to_review`, `test_payout_tells_the_jobber`, `test_cancel_tells_the_other_side`, `test_no_show_and_expiry_and_refund`, `test_a_dispute_tells_the_other_side_and_a_concern_tells_nobody`, `test_resolution_tells_both`, `test_reminder_and_address_sweeps_queue_once`; FAIL; implement; PASS; commit `feat(bookings): queue messages at each event`.

### Task 4: Staff API, messages
**Files:** create `api/staff_ops_views.py`; `api/{serializers,urls}.py`; test `tests/test_staff_messages_api.py`.
**Produces:** the three message routes of the spec; `CanSendMessages`.
- [ ] Tests `test_queue_lists_pending_without_text_or_number`, `test_detail_shows_the_text_and_audits`, `test_send_returns_the_link_once`, `test_a_stale_message_answers_409_and_leaves_the_queue`, `test_without_the_right_403`, `test_responses_are_no_store`; FAIL; implement; PASS; commit `feat(staff): messages queue API`.

### Task 5: Staff API, payouts and disputes
**Files:** `api/{staff_ops_views,serializers,urls}.py`, `services/payouts.py` (`is_late`), `services/reports.py` (`dispute_queue`, `is_late`, `dispute_details`); test `tests/test_staff_payouts_disputes_api.py`.
**Produces:** the six routes of the spec. Payout item `id, category_name, amount_xof, due_at, late`; detail adds `jobber_phone, completed_at, payable`. Dispute item `id, category_name, created_at, late`; detail adds `text, author_side, jobber_name, householder_name, pay_xof, checked_in_at, checked_out_at, distance_m, far, payment_state`. `reports.dispute_details(report, *, staff) -> dict` audits `booking.report.view`; the console page uses it too.
- [ ] Tests `test_payout_queue_detail_and_pay`, `test_payout_detail_audits_and_shows_the_phone_only_there`, `test_a_refunded_booking_cannot_be_paid_from_the_app`, `test_dispute_queue_detail_and_each_resolution`, `test_bad_split_and_missing_note`, `test_rights_are_separate` (make_payout without resolve_dispute and back), `test_lists_carry_no_phone_or_text`; FAIL; implement; PASS; commit `feat(staff): payouts and disputes API`.

### Task 6: Alerts and console
**Files:** create `services/alerts.py`; `api/{staff_ops_views,serializers,urls}.py`, `admin.py`; test `tests/test_staff_alerts.py`.
**Produces:** `alerts.counts(user) -> dict` with the ten keys of the spec, a key present only when the user holds the right; `GET staff/alerts`; `MessageAdmin` (read-only: `created_at, kind, recipient role, status, sent_at`).
- [ ] Tests `test_counts_follow_the_queues_and_the_late_limits`, `test_counts_show_only_what_the_user_may_work`, `test_far_check_in_is_counted_while_the_job_runs`, `test_message_console_is_read_only_and_shows_no_number`; FAIL; implement; PASS; commit `feat(staff): alerts and message console`.

### Task 7: Staff app, API and controller
**Files:** `lib/src/staff_api.dart` (models `MessageItem`, `PayoutItem`, `DisputeItem`, `StaffAlerts`; calls), create `lib/src/ops_controller.dart`, `lib/src/staff_controller.dart` (sections `messages`, `disputes`; payment tab `payout`; public `guard`), `providers.dart`; test `test/ops_controller_test.dart`.
**Produces:** `OpsState {messages, messageSelected, payouts, payoutSelected, disputes, disputeSelected, alerts, busy, error, listError}`; `OpsController`: `refreshMessages/openMessage/closeMessage/sendMessage() -> Uri?`, `refreshPayouts/openPayout/closePayout/payPayout(reference) -> bool`, `refreshDisputes/openDispute/closeDispute/resolveDispute(outcome, note, {jobberXof}) -> bool`, `refreshAlerts()`. Details are dropped on close. A stale message leaves the list and shows the server text.
- [ ] Tests: lists load; open loads the detail; send returns the link and removes the row; stale removes the row and shows the text; pay and resolve send their bodies and remove the row; a refusal keeps the row and shows the text; close drops the detail; alerts parse and missing keys are null; FAIL; implement; PASS; commit `feat(staff-app): operations API and controller`.

### Task 8: Staff app, screens
**Files:** create `screens/{messages_queue_screen,message_detail_screen,payout_detail_screen,disputes_queue_screen,dispute_detail_screen}.dart`; modify `payments_queue_screen.dart` (tab "À verser"), `section_bar.dart` (sections and badges), `main.dart`, `staff_copy.dart`; test `test/ops_screens_test.dart`.
- [ ] Tests `test_messages_queue_marks_urgent_and_late`, `test_message_detail_shows_the_text_and_opens_whatsapp`, `test_a_stale_message_says_so`, `test_payout_tab_and_recording`, `test_dispute_detail_and_the_three_decisions` (split asks for the amount; a note is required), `test_sections_follow_the_rights_and_show_badges`, `test_screens_fit_320dp_at_double_text_size`; FAIL; implement; PASS; commit `feat(staff-app): messages, payouts and disputes screens`.

### Task 9: Docs and whole verification
**Files:** `README.md`, `docs/threat-model.md`, `next_steps.md`.
- [ ] Run every suite (backend pytest, ruff, makemigrations, spectacular; analyze and test in the four Dart packages); build the three debug APKs into `dist/apk/`; commit `docs: staff operations`.
