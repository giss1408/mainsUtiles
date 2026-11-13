# Payment and Address Release Implementation Plan (stage 2 of 3 of piece 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After accepting a jobber, the householder pays the platform by mobile money and sends proof; staff confirm it; the booking becomes `confirmed`; the jobber gets the exact pin shortly before the start, and the householder gets the jobber's name and photo. Either side can cancel; unpaid bookings expire; refunds are recorded by staff.

**Architecture:** Same Django app `apps/bookings` (payments are part of a booking's life; one app avoids cross-app imports), new models `PaymentMethod` and `Payment`, services in `services/payments.py` and `services/bookings.py`, thin views, console pages in the Django admin. Flutter code in `petitgombo_core/src/applications/` (renamed concept: bookings) plus a gallery picker implemented in the householder app behind an interface.

**Tech Stack:** Django 5.2, DRF, Celery beat, pytest; Flutter 3.24.2, Riverpod StateNotifier, Dio; `image_picker` in the householder app only.

**Spec:** `docs/superpowers/specs/2026-11-13-applications-and-bookings-design.md` (amended 2026-11-13: payment is manual, checked by staff). Stage 1 plan: `2026-11-13-applications.md`.

## Global Constraints

- Branch `feat/jobber-verification` continues. Commit after each task. Backend commands run from `backend/`: `.venv/bin/python -m pytest`, `.venv/bin/ruff check . && .venv/bin/ruff format --check .`, `makemigrations --check`, `manage.py spectacular --validate` (exit 0). Never edit files while a full-suite run is in progress.
- Flutter 3.24.2; `flutter analyze` and `flutter test` in every package touched; `dart format -l 100`. The only new package is `image_picker` (householder app).
- French copy; the householder app says "vous", the jobber app "tu". Amounts `3 500 FCFA`.
- Rules live in services; every limit is a setting; errors `{"error", "message"}` via `apps/accounts/api/errors.py`; every change and every view of sensitive data writes `apps.audit.services.record(actor, action, obj, **extra)`.
- The platform's receiving numbers are not secret and are shown to householders. A householder's or jobber's phone is never returned to the other side. The screenshot is stored encrypted like the verification photos (`store_photo`, JPEG only) and every staff view is audited.
- The jobber's exact pin is returned only to the booked jobber, only for a `confirmed` or `address_released` booking, only from `ADDRESS_RELEASE_HOURS` before the start, never after cancel or completion, and every read is audited. The pin is the householder's confirmed `HomeLocation`; there is no street text.
- UI: existing tokens, one primary action per screen, loading/empty/error/data states, no overflow at 320dp with text scale 2.

**Out of scope (stage 3 or later):** check-in and check-out, householder confirmation, the jobber payout, disputes, reviews, ratings, strikes for repeated cancellations, SMS and push, the staff-app payments queue, cash and QR, any payment API.

## Review Focus

1. **One transaction reference or one screenshot used for two bookings.** A reference confirms only one booking; the same image sent twice is flagged on the review page. (Tasks 3, 4)
2. **Double submit and double decision.** Two proofs at once, or two staff confirming the same payment: exactly one wins, the other answers `invalid_state`. (Tasks 3, 4)
3. **Time passes during review.** A booking with a proof under review never expires; one without a proof expires at the window or at the release time, whichever is first; a proof sent after the window is refused. (Tasks 3, 5)
4. **Cancelling after payment.** Money that may have been sent shows up as a refund to make, once; the address stops being released; the offer reopens only if it has not started. (Task 5)
5. **No payment method set, or one switched off mid-flow.** Apply and accept are refused; a proof already submitted can still be reviewed. (Task 2)

## File Structure

- Backend: `apps/bookings/models.py` (+ `PaymentMethod`, `Payment`, new statuses), `services/payments.py`, `services/bookings.py` (cancel, expire, address, jobber card), `api/{payments_views,serializers,urls}.py`, `admin.py` + `templates/admin/bookings/`, `tasks.py`, migrations; `apps/verification/models.py` (photo kind `payment_proof`).
- Mobile core: `lib/src/applications/{payment_models,payments_api,payment_controller,booking_controller}.dart`, `screens/{payment_screen,my_booking_screen,jobber_booking_screen}.dart`, interface `ProofPicker` in `lib/src/applications/proof_picker.dart`; householder app `lib/gallery_picker.dart`.

---

### Task 1: Models, settings, statuses, groups

**Files:** Modify `apps/bookings/models.py`, `apps/verification/models.py`, `config/settings.py`; create migrations (`0002_payments.py`, `0003_payment_group.py`); test `tests/test_payment_models.py`.

**Interfaces:**
- Produces: `PaymentMethod(id, provider {wave, mtn_momo, orange_money}, number CharField(30), account_name CharField(80), active bool, position)`; `PaymentMethod.objects.available()` (active, number not blank). `Payment(id uuid, booking FK PROTECT, method FK PROTECT, amount_xof, fee_xof, reference TextField (encrypted), reference_hash CharField(64, indexed), proof FK VerificationPhoto PROTECT, status {submitted, confirmed, refused, refund_due, refunded}, reason, submitted_at, decided_by FK null, decided_at null, refund_reference TextField(blank, encrypted), refunded_by FK null, refunded_at null)`; constraints `one_open_payment_per_booking` unique `booking` where status in (`submitted`, `confirmed`, `refund_due`) and `one_confirmed_reference` unique `reference_hash` where status in (`confirmed`, `refund_due`, `refunded`); permissions `verify_payment`, `manage_paymentmethod` (Django default change perm is enough for methods), `make_refund`. `Booking.Status.PAYMENT_REVIEW = "payment_review", "Paiement à vérifier"` added to `LIVE` and to the `one_live_booking_per_offer` condition; `Booking.cancelled_by FK null, cancelled_at null, cancel_reason`. `VerificationPhoto.Kind.PAYMENT_PROOF = "payment_proof"`. Settings `PAYMENT_WINDOW_HOURS=12`, `ADDRESS_RELEASE_HOURS=3`, `PLATFORM_FEE_PERCENT=0`, `CANCEL_FREE_HOURS=24`. Group `payment_agent` with `verify_payment`, `make_refund`, view and change on `PaymentMethod`, view `Payment`.

- [ ] **Step 1: Write failing tests**: `test_available_methods_need_an_active_method_with_a_number`, `test_one_open_payment_per_booking`, `test_a_reference_confirms_only_one_booking`, `test_payment_review_is_a_live_status_and_blocks_a_second_booking`, `test_group_payment_agent_has_its_permissions`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** models, constraints, the group migration (data migration like `0006_briefing_seed_and_group`), settings.
- [ ] **Step 4: Run** the full backend suite, ruff, `makemigrations --check`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): payment models and statuses`.

### Task 2: Payment methods console and the availability gate

**Files:** Modify `apps/bookings/admin.py`, `services/applications.py`, `apps/accounts/api/errors.py`; create `services/payments.py` (availability part); test `tests/test_payment_methods.py`; update the stage-1 tests to use a `payment_method` fixture (add to `tests/conftest.py`: an active Wave method) via `pytestmark = pytest.mark.usefixtures("payment_method")` in `test_applications.py`, `test_accept.py`, `test_applications_api.py`, `test_applicants_api.py`, `test_review_fixes_applications.py`.

**Interfaces:**
- Produces: `payments.available() -> bool`; `payments.instructions() -> list[dict]` (`{id, provider, provider_label, number, account_name}` for available methods, in `position` order); `PaymentMethodAdmin` ("Moyens de paiement": add, change, no delete; number validated as a phone number via `apps.accounts.phones.normalise`, saved normalised); error `payment_unavailable` 409 "Le paiement n'est pas disponible pour le moment." in `apply` and `accept` (checked first, after the role check). Every create or change of a method is audited (`bookings.payment_method.change`).

- [ ] **Step 1: Write failing tests**: `test_no_active_method_means_apply_and_accept_are_refused`, `test_a_method_without_a_number_does_not_count`, `test_switching_the_last_method_off_stops_new_applications_but_not_a_review`, `test_agent_manages_methods_and_the_number_is_normalised_and_audited`, `test_agent_without_the_permission_gets_403`, `test_instructions_list_only_available_methods_in_order`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): payment methods and the availability gate`.

### Task 3: Submit proof of payment

**Files:** Modify `services/payments.py`, `apps/accounts/api/errors.py`; test `tests/test_payment_proof.py`.

**Interfaces:**
- Produces: `submit_proof(user, booking_id, *, method_id, reference: str, screenshot: bytes, captured_at) -> Payment` (householder owner of the booking, else `forbidden`; booking `accepted`, else `invalid_state`; `now <= accepted_at + PAYMENT_WINDOW_HOURS` and before the release window opens, else `payment_window_closed`; `payment_unavailable` if no method; the method must be available, else `method_invalid`; reference stripped, 4 to 40 characters of letters, digits, dashes, dots and spaces, else `reference_invalid`; the screenshot through `submissions.store_photo(user, "payment_proof", ...)`; amount = `pay_xof`, fee = `pay_xof * PLATFORM_FEE_PERCENT // 100`; the booking becomes `payment_review`; a refused payment of an earlier attempt does not block; audit `booking.payment.submit`). `payment_amount(booking) -> (amount, fee)`. Error codes with French "vous" messages: `payment_window_closed` 409 "Le délai pour payer est dépassé.", `method_invalid` 400 "Choisissez un moyen de paiement proposé.", `reference_invalid` 400 "Indiquez la référence de la transaction.".

- [ ] **Step 1: Write failing tests**: `test_proof_stores_an_encrypted_photo_and_moves_the_booking_to_review`, `test_amount_and_fee_follow_the_settings`, `test_only_the_householder_of_an_accepted_booking_can_submit`, `test_second_proof_while_one_is_under_review_is_invalid_state`, `test_a_proof_after_the_window_or_the_release_time_is_refused`, `test_reference_and_method_rules_each_have_their_code`, `test_a_png_or_oversized_screenshot_is_refused_with_the_photo_codes`, `test_after_a_refusal_a_new_proof_is_accepted`, `test_two_simultaneous_submissions_make_one_payment` (threads).
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): proof of payment`.

### Task 4: Staff confirm or refuse a payment

**Files:** Modify `services/payments.py`; test `tests/test_payment_review.py`.

**Interfaces:**
- Produces (permission `bookings.verify_payment`, else `forbidden`; row locks; audited): `confirm_payment(payment, *, staff, amount_matches: bool, reference_matches: bool) -> None` (payment `submitted` and booking `payment_review`, else `invalid_state`; both checks true, else `checks_required`; the reference hash not already used by another confirmed, refund-due or refunded payment, else `duplicate_reference`; payment `confirmed`, booking `confirmed`; audit `booking.payment.confirm`); `refuse_payment(payment, *, staff, reason: str) -> None` (reason required; payment `refused`, booking back to `accepted`; audit `booking.payment.refuse`); `read_proof(payment, *, staff) -> bytes` (decrypted screenshot; audit `booking.payment.view_proof`); `proof_seen_before(payment) -> bool` (another photo with the same `sha256`).

- [ ] **Step 1: Write failing tests**: `test_confirm_makes_the_booking_confirmed_and_audits`, `test_both_checks_are_required`, `test_the_same_reference_cannot_confirm_a_second_booking`, `test_refuse_returns_the_booking_to_accepted_with_the_reason`, `test_double_decision_one_wins` (threads), `test_without_the_permission_nothing_works`, `test_every_proof_view_is_audited`, `test_proof_seen_before_flags_the_same_image_on_two_bookings`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): staff decide on a payment`.

### Task 5: Cancel, expire, refund

**Files:** Create `services/bookings.py`; modify `apps/listings/services/offers.py` (`_cancel_unpaid_booking` calls the new service; `tidy` unchanged for paid bookings), `services/payments.py` (refunds), `tasks.py`, `config/settings.py` (beat `expire-unpaid-bookings` hourly); test `tests/test_booking_cancel.py`.

**Interfaces:**
- Produces: `cancel(user, booking_id, *, reason: str = "") -> Booking` (the booking's householder or jobber, else `forbidden`; states `accepted`, `payment_review`, `confirmed`, `address_released`, else `invalid_state`; booking `cancelled` with `cancelled_by`, `cancelled_at`, `cancel_reason`; a payment `submitted` or `confirmed` becomes `refund_due`; the offer returns to `published` if its start is still ahead, else `closed`; the cancelled jobber's application stays `accepted`; audit `booking.cancel`); `expire_unpaid(now=None) -> int` (bookings `accepted` whose `accepted_at + PAYMENT_WINDOW_HOURS` or `starts_at - ADDRESS_RELEASE_HOURS` has passed become `expired`, the offer follows the same rule as cancel; bookings in `payment_review` are never touched); Celery task `expire_unpaid_bookings`; `record_refund(payment, *, staff, reference: str) -> None` (permission `bookings.make_refund`; payment `refund_due`, reference required; `refunded`; audit `booking.payment.refund`). The stage-1 rule "withdrawing a booked offer" now calls `cancel` for `accepted` and `payment_review` and keeps refusing later states.

- [ ] **Step 1: Write failing tests**: `test_householder_and_jobber_can_cancel_before_check_in_others_cannot`, `test_cancel_of_a_paid_booking_makes_the_payment_refund_due_once`, `test_cancel_reopens_the_offer_only_if_it_has_not_started`, `test_expire_unpaid_expires_only_bookings_without_a_proof`, `test_a_booking_under_review_never_expires`, `test_record_refund_needs_the_permission_a_reference_and_happens_once`, `test_withdrawing_a_booked_offer_goes_through_cancel`, `test_a_cancelled_booking_no_longer_releases_the_address` (after Task 6), `test_the_sweep_task_runs`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): cancel, expire and refund`.

### Task 6: Address release and the jobber's name and photo

**Files:** Modify `services/bookings.py`, `apps/bookings/api/serializers.py`; test `tests/test_address_release.py`.

**Interfaces:**
- Produces: `address_for(user, booking_id) -> dict` (the booked jobber only, else `forbidden`; booking `confirmed` or `address_released`, else `invalid_state`; `now >= starts_at - ADDRESS_RELEASE_HOURS` and `now < starts_at + duration`, else `address_not_yet` 409 "L'adresse sera communiquée quelques heures avant le début."; returns `{"latitude", "longitude", "commune", "quartier"}` from the householder's confirmed `HomeLocation` (decrypted), sets the booking `address_released` on the first read; audit `booking.address.release` each time); `available_from(booking)`; `jobber_card(user, booking_id) -> dict` (the booking's householder only; booking `confirmed` or later and not cancelled, else `invalid_state`; `{"full_name", "has_photo": True}`; audit `booking.jobber.view`); `jobber_photo(user, booking_id) -> bytes` (same rules; the confirmed identity selfie; audit `booking.jobber.view_photo`). The jobber's `my-bookings` rows gain `address_available_from` (ISO or null) and `payment` (`pending`, `review`, `confirmed`).

- [ ] **Step 1: Write failing tests**: `test_address_is_refused_before_the_window_and_after_the_job`, `test_address_is_released_to_the_booked_jobber_only_and_audited_each_time`, `test_address_needs_a_confirmed_booking`, `test_the_pin_comes_from_the_confirmed_home_location`, `test_jobber_card_needs_a_confirmed_booking_and_is_for_the_householder_only`, `test_jobber_photo_is_the_confirmed_selfie_and_audited`, `test_nothing_before_payment_contains_the_jobbers_name_or_the_pin` (raw text of every earlier response).
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): address release and the jobber card`.

### Task 7: API

**Files:** Create `apps/bookings/api/payments_views.py`; modify `apps/bookings/api/urls.py`, `serializers.py`, `jobber_views.py`, `views.py`; test `tests/test_payments_api.py`.

**Interfaces:**
- Produces (householder): `GET my-offers/<uuid>/booking` → `{id, status, amount_xof, fee_xof, pay_deadline, methods: [...instructions], payment: {status, reason} | null, jobber: {first_name} | {full_name, has_photo}, cancellable}`; `POST my-offers/<uuid>/booking/payment` multipart (`method_id`, `reference`, `screenshot`, `captured_at`) → 201 payment; `GET my-offers/<uuid>/booking/photo` → `image/jpeg`, `Cache-Control: no-store`; `POST my-offers/<uuid>/booking/cancel` `{reason}`. Jobber: `GET my-bookings/<uuid>/address`; `POST my-bookings/<uuid>/cancel`. Errors via `error_response`; a foreign id is 404.

- [ ] **Step 1: Write failing tests**: `test_booking_detail_shows_methods_amount_and_the_first_name_only_until_confirmed`, `test_detail_shows_the_full_name_after_confirmation`, `test_payment_upload_creates_a_submitted_payment_and_validates_the_fields`, `test_photo_endpoint_is_no_store_and_householder_only`, `test_address_endpoint_obeys_the_window`, `test_cancel_from_both_sides`, `test_no_response_contains_the_other_sides_phone` (raw text), `test_foreign_ids_are_404`, `test_the_schema_validates`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite, ruff, spectacular validate. Expected: PASS.
- [ ] **Step 5: Commit** `feat(bookings): payment and booking API`.

### Task 8: Console for payments and refunds

**Files:** Modify `apps/bookings/admin.py`; create `console_views.py`, templates `admin/bookings/payment_review.html`; test `tests/test_payments_console.py`.

**Interfaces:**
- Produces: `PaymentAdmin` ("Paiements"): default queue "À vérifier" (submitted, oldest first, those older than 2 hours marked "en retard"), "Remboursements à faire" (`refund_due`), "Tous"; the review page shows the booking's category, time, amount and fee, provider, the typed reference, the proof image (route `.../proof/`, `no-store`, audited), the "image déjà vue" warning, the checkboxes "Le montant correspond" and "La référence correspond", and "Confirmer" / "Refuser" (reason) buttons; the refund page records the refund reference. Routes `bookings_payment_confirm`, `bookings_payment_refuse`, `bookings_payment_refund`, `bookings_payment_proof` (POST for actions). The list never shows references or names.

- [ ] **Step 1: Write failing tests**: `test_agent_sees_the_queue_oldest_first_with_the_late_marker`, `test_review_page_shows_the_proof_the_amount_and_audits_the_view`, `test_confirm_and_refuse_through_the_console`, `test_refund_queue_and_recording`, `test_list_page_shows_no_reference_or_name`, `test_agent_without_the_permission_gets_403`, `test_pages_are_no_store`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** the full suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(console): payments to check and refunds`.

### Task 9: Flutter models, API and controllers

**Files:** Create `lib/src/applications/{payment_models,payments_api,payment_controller,booking_controller,proof_picker}.dart`; modify `lib/petitgombo_core.dart`; tests `test/payment_models_test.dart`, `test/payment_controller_test.dart`, `test/booking_controller_test.dart`.

**Interfaces:**
- Produces: `PaymentMethodInfo`, `BookingDetail` (status, amounts, deadline, methods, payment state, jobber first or full name, `hasPhoto`, `cancellable`), `JobberBookingDetail` (status, `addressAvailableFrom`, `payment`), `ReleasedAddress {latitude, longitude, commune, quartier}`; `abstract class ProofPicker { Future<CapturedPhoto?> pick(); }` with a provider `proofPickerProvider` that throws until overridden; `BookingController` (family by offer id: `load()`, `submitProof(methodId, reference)`, `cancel(reason)`, `photo()` bytes), `JobberBookingsController` (`load()`, `address(id)`, `cancel(id)`); `ApplicationsApi` gains `booking`, `submitProof` (FormData, built inside the call), `bookingPhoto`, `cancel`, `address`, `cancelJobber`.
- Rules: a refused proof shows the server message and keeps the typed reference; the screenshot bytes are not kept after sending; every change reloads the booking.

- [ ] **Step 1: Write failing tests**: models `fromJson`; `submitProof` sends the multipart fields; a refusal keeps the reference and shows the message; `cancel` reloads; the address is not stored in state longer than the screen needs it (cleared by `clearAddress`); offline message.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** package tests and analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): booking and payment models, API and controllers`.

### Task 10: Householder screens

**Files:** Create `screens/{payment_screen,my_booking_screen}.dart`; modify `offers/screens/my_offer_detail_screen.dart`, `applicants_screen.dart` (the unavailable banner); tests `test/payment_screens_test.dart`.

**Interfaces:** The booked offer's card opens `MyBookingScreen`: status line in words ("Paiement à envoyer avant 18:00", "Paiement en cours de vérification", "Réservation confirmée", "Paiement refusé : {motif}"), the jobber's first name (full name and photo once confirmed), "Payer" (to `PaymentScreen`), "Annuler la réservation" with a confirm dialog. `PaymentScreen`: the amount, each method's provider, number and account name (copyable), a method choice, the reference field, "Choisir la capture d'écran" (via `ProofPicker`), a preview, "Envoyer la preuve". When no method is available the applicants screen shows "Le paiement n'est pas disponible pour le moment." instead of the Accept buttons.

- [ ] **Step 1: Write failing tests**: `test_booking_screen_words_each_state`, `test_payment_screen_shows_methods_and_sends_the_proof`, `test_a_refused_proof_keeps_the_reference_and_shows_the_reason`, `test_confirmed_booking_shows_the_full_name_and_the_photo`, `test_cancel_asks_to_confirm`, `test_payment_unavailable_replaces_the_accept_buttons`, `test_screens_fit_320dp_at_double_text_size`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** package and householder tests, analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): householder pays and follows the booking`.

### Task 11: Jobber screens

**Files:** Create `screens/jobber_booking_screen.dart`; modify `applications/screens/my_applications_screen.dart` (a "Mes jobs" section), `offers/screens/offers_screen.dart`; tests `test/jobber_booking_screen_test.dart`.

**Interfaces:** "Mes jobs" lists the jobber's bookings with the state in words ("En attente du paiement du ménage", "Confirmé : l'adresse arrive à 06:00", "Adresse disponible"). A booking opens `JobberBookingScreen`: the commune and quartier; once released, the pin as two coordinates with "Copier"; "Annuler ma participation" with a confirm dialog and the line "Le ménage sera remboursé."; when the window has not opened, "L'adresse sera communiquée le {date} à {heure}.".

- [ ] **Step 1: Write failing tests**: `test_my_jobs_words_each_state`, `test_address_is_hidden_until_released_then_shown_with_copy`, `test_cancel_asks_to_confirm`, `test_screens_fit_320dp_at_double_text_size`.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement.** **Step 4: Run** package and jobber tests, analyze. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): jobber follows the booking and gets the address`.

### Task 12: Gallery picker, docs, whole-stage verification

**Files:** Create `mobile/apps/householder/lib/gallery_picker.dart`; modify `apps/householder/pubspec.yaml`, `lib/main.dart`, `README.md`, `docs/threat-model.md`, `next_steps.md`; test `mobile/apps/householder/test/gallery_picker_test.dart`.

**Interfaces:** `GalleryProofPicker implements ProofPicker` using `image_picker` (`ImageSource.gallery`), decoding any image with the `image` package and re-encoding JPEG (long side 1600, quality 80) in a background isolate; returns `CapturedPhoto(bytes, capturedAt: now, position: null)`; cancelled pick returns null. A pure function `toJpeg(Uint8List) -> Uint8List?` is unit-tested with a small PNG and a JPEG. Threat-model rows: fake or reused screenshot, double confirmation of one reference, staff approving an unpaid booking, address leak before the window, refund never made, receiving numbers changed by an insider (audited). README: a "Payment" section (methods, the staff routine, the queues, settings, the manual refund and payout note).

- [ ] **Step 1: Write failing tests**: `toJpeg` of a PNG returns JPEG bytes; of a JPEG returns JPEG bytes within the size cap; of garbage returns null.
- [ ] **Step 2: Run** them. Expected: FAIL. **Step 3: Implement**, add the dependency (`flutter pub get`), wire the provider override in `main.dart`.
- [ ] **Step 4: Run** every suite (backend pytest, ruff, `makemigrations --check`, spectacular; analyze and test in core, jobber, householder, staff) and build the jobber and householder debug APKs. Expected: all pass.
- [ ] **Step 5: Commit** `feat(householder): gallery picker for payment proof, docs`.
