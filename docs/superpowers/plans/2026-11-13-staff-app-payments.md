# Staff App Payments Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Staff check payments and record refunds from the staff app, on the phone that holds the platform's mobile-money account, with the same rules as the console.

**Architecture:** Thin staff endpoints over the existing `payments` service (`apps/bookings/api/staff_views.py`, like the trusted-contact ones); in the staff app a third section "Paiements" in `StaffController`, with a queue screen and a detail screen that shows the proof image, the two checks and the decision buttons.

**Tech Stack:** Django 5.2, DRF, pytest; Flutter 3.24.2, Riverpod StateNotifier, Dio. No new package.

**Spec:** `docs/superpowers/specs/2026-11-13-applications-and-bookings-design.md` ("Console (staff)": payments to check, refunds; the staff app gets the payments queue). Console behaviour to match: `apps/bookings/admin.py` (`PaymentAdmin`), services in `apps/bookings/services/payments.py`.

## Global Constraints

- Same as the payment plan: rules in services, errors `{"error", "message"}`, every view of sensitive data audited, responses with a reference or an image `Cache-Control: no-store`. Backend commands from `backend/`; never edit files while a full-suite run is in progress. Flutter 3.24.2, `dart format -l 100`, French copy, no new package, 320dp at text scale 2.
- The list never shows a reference or a name. The detail (reference, proof) is only for payments in a queue: `submitted` (needs `bookings.verify_payment`) or `refund_due` (needs `bookings.make_refund`); any other payment is 404. The app never stores the proof or the reference after the screen closes.
- The staff app already blocks screenshots and screen recording; the proof image is shown only there.

**Out of scope:** the payout queue (stage 3), payment-method editing from the phone (console only), push alerts for a late review.

## Review Focus

1. **A staff member with only one of the two rights.** A check-only agent sees no refund queue and cannot record a refund; a refund-only agent cannot confirm. (Tasks 1, 3)
2. **Opening a payment that is already decided or not in a queue.** 404, never its reference or image. (Task 1)
3. **Two phones deciding the same payment.** The second shows the server's message and the list reloads. (Tasks 2, 3)
4. **The proof or reference left in memory or on screen after leaving.** Cleared when the detail closes. (Task 2)

---

### Task 1: Staff payments API

**Files:** Create `apps/bookings/api/staff_views.py`; modify `apps/bookings/api/urls.py`, `apps/bookings/api/serializers.py`, `apps/bookings/services/payments.py` (queue helpers); test `tests/test_staff_payments_api.py`.

**Interfaces:**
- Produces: `payments.check_queue()` (status `submitted`, oldest first) and `payments.refund_queue()` (status `refund_due`, oldest first). Routes (staff, `IsStaffMember`; rights checked per route): `GET staff/payments?file=check|refund` (default `check`; needs `verify_payment` for `check`, `make_refund` for `refund`; paginated 20; items `{id, category_name, starts_at, amount_xof, method_label, submitted_at, late, action}` with `action` `check` or `refund`); `GET staff/payments/<uuid>` (items plus `fee_xof`, `reference` decrypted, `method_number`, `seen_before`, `status`; audit `booking.payment.view`; 404 unless in the queue the staff member may see); `GET staff/payments/<uuid>/proof` (`image/jpeg`, `no-store`, audited by `read_proof`); `POST staff/payments/<uuid>/confirm` `{amount_matches, reference_matches}`; `POST .../refuse` `{reason}`; `POST .../refund` `{reference}`. Each action returns the payment's item shape. Errors through `error_response`; `forbidden` from a service is 403 here.
- `late` is true for a `submitted` payment older than `PAYMENT_REVIEW_LATE_HOURS`.

- [ ] **Step 1: Write failing tests**: `test_check_queue_lists_submitted_payments_oldest_first_with_the_late_flag_and_no_reference_or_name`, `test_refund_queue_needs_the_refund_right_and_check_queue_the_verify_right`, `test_detail_shows_the_reference_and_audits_the_view`, `test_a_decided_or_unqueued_payment_is_404`, `test_proof_is_no_store_and_audited`, `test_confirm_and_refuse_and_refund_through_the_api`, `test_both_checks_are_required`, `test_second_decision_is_409_with_the_message`, `test_a_jobber_or_householder_token_gets_403`, `test_the_schema_validates`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full backend suite, ruff, spectacular validate. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): staff API for payments`.

### Task 2: Staff app models, API and controller

**Files:** Modify `mobile/apps/staff/lib/src/{staff_api,staff_controller,staff_copy}.dart`; tests `test/payments_controller_test.dart`, fixtures in `test/support/fixtures.dart`.

**Interfaces:**
- Produces: `PaymentItem {id, categoryName, startsAt, amountXof, methodLabel, submittedAt, late, action, reference?, methodNumber?, feeXof?, seenBefore?}`; `StaffApi.payments(access, {file})`, `.payment(access, id)`, `.paymentProof(access, id) -> Uint8List`, `.confirmPayment(access, id, {amountMatches, referenceMatches})`, `.refusePayment(access, id, reason)`, `.refundPayment(access, id, reference)`. `StaffSection.payments`; state gains `payments`, `paymentTab` (`check`/`refund`), `paymentSelected`, `proof` (bytes). Controller: `selectPaymentTab`, `refreshPayments`, `openPayment` (loads detail then the proof), `closePayment` (clears reference and proof), `confirmPayment(amountMatches, referenceMatches)`, `refusePayment(reason)`, `refundPayment(reference)`; a decision removes the row from the list; a 409 reloads the list and shows the message. A staff member with only payment rights starts on `payments`; with several rights, enrolments first.

- [ ] **Step 1: Write failing tests**: `test_a_payment_agent_lands_on_the_payments_section`, `test_the_refund_tab_asks_for_the_refund_queue`, `test_open_loads_the_detail_and_the_proof_and_close_clears_them`, `test_confirm_sends_the_checks_and_drops_the_row`, `test_refuse_and_refund_send_their_fields`, `test_a_409_reloads_the_list_and_shows_the_message`, `test_state_and_storage_never_hold_the_reference_after_close`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the staff app tests and analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(staff): payments controller`.

### Task 3: Staff app screens

**Files:** Create `lib/src/screens/{payments_queue_screen,payment_detail_screen}.dart`; modify `lib/src/screens/section_bar.dart`, `lib/main.dart`, `lib/src/staff_copy.dart`; tests `test/payments_screens_test.dart`.

**Interfaces:** `sectionBar` shows one destination per right the staff member holds (enrolments, contacts, payments) and nothing when only one. `PaymentsQueueScreen`: tabs "À vérifier" / "Remboursements" (the refund tab only with the refund right), rows with the category, when, amount, method, "En retard" marker. `PaymentDetailScreen`: amount (and fee), method and number, the typed reference, the proof image (with an error fallback), "Image déjà envoyée" warning, checkboxes "Le montant correspond" and "La référence correspond", "Confirmer le paiement" (disabled until both are ticked), "Refuser" (reason dialog); for a refund: "Enregistrer le remboursement" with a reference dialog. Copy says to check the platform account's history, not the picture.

- [ ] **Step 1: Write failing tests**: `test_rows_show_category_amount_method_and_the_late_marker_and_no_reference`, `test_detail_shows_reference_proof_and_the_history_warning`, `test_confirm_is_disabled_until_both_checks_are_ticked`, `test_confirm_refuse_and_refund_flows_call_the_api`, `test_refund_tab_hidden_without_the_refund_right`, `test_section_bar_has_one_destination_per_right`, `test_screens_fit_320dp_at_double_text_size`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** staff tests and analyze, build nothing else. Expected: PASS.
- [ ] **Step 5: Commit** `feat(staff): payments screens`.

### Task 4: Docs and whole verification

**Files:** modify `README.md` (Staff app and Payment sections), `docs/threat-model.md` (a row: "Insider reads a payment reference or receipt": shown only to the right holders, audited, not cached, not kept on the phone), `next_steps.md`.

- [ ] **Step 1:** Run every suite: backend pytest, ruff, `makemigrations --check`, spectacular validate; analyze and test in `petitgombo_core`, `apps/jobber`, `apps/householder`, `apps/staff`; build the staff debug APK. Expected: all pass.
- [ ] **Step 2: Commit** `docs: staff app payments queue`.
