# Householder Verification (Direct Route) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A householder submits identity, proof of address and home location from the app; staff confirm them in the web console; the account computes as tier H1.

**Architecture:** A new Django app `apps/verification` holds encrypted photos and records, with rules in services (`encryption`, `submissions`, `review`, `tiers`), a householder-only API, and review pages in the Django admin. The Flutter screens live in `petitgombo_core/src/verification/`; camera and GPS sit behind two small interfaces implemented in the householder app.

**Tech Stack:** Django 5.2, DRF, `cryptography` (Fernet, HMAC), Celery beat, pytest; Flutter 3.24.2, Riverpod, Dio, `camera`, `geolocator`, `image`.

**Spec:** `docs/superpowers/specs/2026-11-12-householder-verification-design.md` (product spec: `skill.md`).

## Global Constraints

- Work on branch `feat/householder-verification`, created from `feat/foundation-enrolment`. Commit after each task.
- Backend commands run from `backend/` with `.venv/bin/pytest` and `.venv/bin/ruff check . && .venv/bin/ruff format --check .`. PostgreSQL and Redis come from `docker-compose.yml`.
- Flutter is 3.24.2 (Dart 3.5). Use only APIs of that version. For new packages take the newest version that resolves with it. Run `flutter analyze` and `flutter test` in every Dart package touched; format with `dart format -l 100`.
- All user-facing copy is French; code, comments and logs are English.
- Every limit is a Django setting read from the environment with the default in this plan. No hard-coded values in services.
- Business rules live in services, never in views, admin classes or the Flutter client.
- Never log or return to a non-staff client: photo bytes, document numbers, names, dates of birth, coordinates. Nothing from this app is ever returned to a jobber.
- Every staff decision and every photo view writes an `AdminAction` row (`apps.audit.services.record`).
- Errors returned by the API use `{"error": code, "message": french}` via `apps/accounts/api/errors.py` (add the new codes and messages there).
- Flutter UI follows the existing tokens (`Gaps`, `Radii`, `AppColors`, `ScreenScaffold`, `MessageBanner`): one primary action per screen, no inline font sizes, status never by colour alone, no overflow at 320dp with text scale 2.

**Out of scope (do not build):** third-party bill route, mobile-money name match, a real identity provider, liveness, review from the staff app, a second address, blur or glare detection, resumable uploads, push or SMS on decision, reason-for-access prompts, four-eyes approval, any change to the jobber app, key rotation.

## Review Focus

1. **Refused, then sent again.** A refused step must be sendable again, and the checklist must show the new submission, not the old refusal. (Task 3)
2. **Same number typed differently.** `CI 001-234 567` and `ci001234567` are the same document or customer number and must collide. (Task 1, Task 5)
3. **Birthday edge.** Someone who turns 18 tomorrow is refused today; someone who turned 18 today is accepted. (Task 5)
4. **Upload fails half-way.** A failed identity upload leaves no half-created record on the server, and the app keeps the three photos for "Réessayer". (Task 3, Task 8)
5. **Location re-recorded after staff opened the case.** A new home location replaces the old one until the proof of address is confirmed, and is refused after. (Task 3, Task 5)

---

## File Structure

```
backend/apps/verification/
  apps.py  models.py  admin.py  console_views.py  tasks.py
  migrations/0001_initial.py  0002_verification_agent_group.py
  services/encryption.py  submissions.py  review.py  tiers.py
  api/serializers.py  views.py  urls.py
  templates/admin/verification/identity_review.html  address_review.html
backend/apps/providers/base.py  mocks.py  staff_review.py      (identity interface)
backend/tests/test_encryption.py  test_verification_models.py  test_verification_submissions.py
              test_verification_api.py  test_verification_review.py  test_verification_console.py
mobile/packages/petitgombo_core/lib/src/verification/
  verification_api.dart  verification_models.dart  verification_controller.dart
  verification_copy.dart  capture.dart  (interfaces PhotoCapture, PositionReader)
  screens/checklist_screen.dart  identity_flow.dart  address_flow.dart  home_location_screen.dart
mobile/apps/householder/lib/device_capture.dart   (camera, geolocator, image resize)
```

---

### Task 1: Settings and encryption service

**Files:**
- Create: `backend/apps/verification/__init__.py`, `apps.py`, `services/__init__.py`, `services/encryption.py`
- Modify: `backend/config/settings.py`, `.env.example`, `.env.prod.example`, `docker-compose.prod.yml`
- Test: `backend/tests/test_encryption.py`, `backend/tests/test_production_settings.py`

**Interfaces:**
- Settings (name, env type, default): `FIELD_ENCRYPTION_KEY` (str; development default `DEV_FIELD_ENCRYPTION_KEY`, a fixed valid Fernet key defined in settings), `MINIMUM_AGE_YEARS` (int, 18), `ADDRESS_PROOF_MAX_AGE_MONTHS` (int, 3), `ADDRESS_PROOF_VALID_MONTHS` (int, 12), `HOME_PIN_MAX_ACCURACY_M` (int, 50), `VERIFICATION_PHOTO_MAX_BYTES` (int, 3000000), `SERVICE_COMMUNES` (list; Abobo, Adjamé, Anyama, Attécoubé, Bingerville, Cocody, Koumassi, Marcory, Plateau, Port-Bouët, Songon, Treichville, Yopougon), `IDENTITY_DOCUMENT_TYPES` (list; `cni`, `passport`, `carte_consulaire`, `permis`), `ADDRESS_PROOF_TYPES` (list; `facture_eau`, `facture_electricite`, `certificat_residence`), `VERIFICATION_STORAGE_DIR` (path; `BASE_DIR / "verification_storage"`, git-ignored), `VERIFICATION_REVIEW_HOURS` (int, 24).
- With `DEBUG` off, loading settings raises `ImproperlyConfigured` mentioning `FIELD_ENCRYPTION_KEY` when it is empty or equals the development default.
- Produces in `encryption`:
  - `encrypt_bytes(data: bytes) -> bytes`, `decrypt_bytes(token: bytes) -> bytes`
  - `encrypt_text(value: str) -> str`, `decrypt_text(token: str) -> str` (empty string stays empty)
  - `normalise_number(value: str) -> str` — upper case, only letters and digits kept
  - `keyed_hash(value: str) -> str` — HMAC-SHA256 hex of `normalise_number(value)` with a key derived from `FIELD_ENCRYPTION_KEY`
- `docker-compose.prod.yml`: `FIELD_ENCRYPTION_KEY: ${FIELD_ENCRYPTION_KEY:?...}`, `VERIFICATION_STORAGE_DIR: /data/verification`, a named volume `verification_data` mounted at `/data/verification` in `web` only; the Dockerfile creates `/data/verification` owned by the `app` user.

- [ ] **Step 1: Write the failing tests**

```python
def test_bytes_round_trip_and_ciphertext_differs():
    token = encrypt_bytes(b"photo")
    assert token != b"photo" and decrypt_bytes(token) == b"photo"

def test_text_round_trip_and_two_encryptions_differ():
    assert decrypt_text(encrypt_text("Kouassi Aya")) == "Kouassi Aya"
    assert encrypt_text("x") != encrypt_text("x")
    assert encrypt_text("") == ""

def test_same_number_typed_differently_hashes_the_same():      # Review Focus 2
    assert keyed_hash("CI 001-234 567") == keyed_hash("ci001234567")
    assert keyed_hash("ci001234567") != keyed_hash("ci001234568")
    assert "001234567" not in keyed_hash("ci001234567")

def test_wrong_key_cannot_decrypt(settings): ...               # change the key -> InvalidToken
# test_production_settings.py
def test_default_encryption_key_is_refused_in_production(monkeypatch): ...   # for "", None and the dev default
```
`prod_settings` in `test_production_settings.py` gains a valid `FIELD_ENCRYPTION_KEY`.

- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_encryption.py tests/test_production_settings.py` — expected FAIL (module missing).
- [ ] **Step 3: Implement** the settings, the app config (added to `INSTALLED_APPS`), the service, the compose and Dockerfile changes.
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS; `docker compose -f docker-compose.prod.yml --env-file .env.prod.example config --quiet` exits 0.
- [ ] **Step 5: Commit** — `feat: verification settings and field encryption`.

---

### Task 2: Models

**Files:**
- Create: `backend/apps/verification/models.py`, `migrations/0001_initial.py`, `migrations/0002_verification_agent_group.py`
- Test: `backend/tests/test_verification_models.py`

**Interfaces:**
- Produces (all with UUID primary keys and `created_at`):
  - `Status` text choices shared by the three records: `submitted`, `in_review`, `confirmed`, `refused`, `expired`. `OPEN = (submitted, in_review, confirmed)`.
  - `VerificationPhoto`: `owner` FK User, `kind` (`id_front|id_back|selfie|address_proof`), `storage_name` (relative file name), `sha256` (hex of the original image), `captured_at`, `capture_position` (encrypted text, blank).
  - `IdentityVerification`: `user`, `status`, `front`/`back`/`selfie` FK `VerificationPhoto` (PROTECT), `document_type`, `full_name`, `date_of_birth`, `document_number` (encrypted text, blank), `document_number_hash` (blank), `document_expires_on` (date, null), `flags` (JSON list), `reason`, `reviewed_by` (FK User, null, PROTECT), `reviewed_at`.
  - `AddressProof`: `user`, `status`, `photo` FK, `document_type`, `commune`, `quartier` (plain), `holder_name`, `reference_number` (encrypted, blank), `reference_hash` (blank), `issued_on` (date, null), `confirmed_at`, `expires_at`, `flags`, `reason`, `reviewed_by`, `reviewed_at`.
  - `HomeLocation`: `user`, `status`, `latitude`, `longitude` (encrypted text), `accuracy_m` (int), `mock_location` (bool), `captured_at`.
- Constraints: one open record per user for each of the three models (`UniqueConstraint(fields=["user"], condition=Q(status__in=OPEN))`); `document_number_hash` unique among confirmed identities; `reference_hash` unique among confirmed address proofs.
- `IdentityVerification.Meta.permissions`: `review_verification`, `view_verification_photo`. Migration `0002` creates the group `verification_agent` with both plus the three `view_*` model permissions, following `accounts/migrations/0002_enrolment_agent_group.py`.
- French `verbose_name`s: "vérification d'identité", "justificatif de domicile", "position du domicile".

- [ ] **Step 1: Write the failing tests** — `test_one_open_identity_per_user` (second `submitted` row raises `IntegrityError`; a `refused` plus a `submitted` is allowed), the same for address and location, `test_confirmed_document_hash_is_unique`, `test_confirmed_reference_hash_is_unique`, `test_verification_agent_group_has_review_and_photo_permissions`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** models and migrations (`makemigrations verification`, then the group migration by hand).
- [ ] **Step 4: Run** `.venv/bin/pytest` and `manage.py makemigrations --check --dry-run` — expected PASS, "No changes detected".
- [ ] **Step 5: Commit** — `feat: verification models`.

---

### Task 3: Submissions, photo storage, tiers, identity provider seam

**Files:**
- Create: `backend/apps/verification/services/submissions.py`, `services/tiers.py`, `backend/apps/providers/staff_review.py`
- Modify: `backend/apps/providers/base.py`, `mocks.py`, `backend/config/settings.py` (`IDENTITY_PROVIDER` default → `apps.providers.staff_review.StaffReviewIdentity`), `backend/tests/test_providers.py`, `backend/tests/conftest.py`
- Test: `backend/tests/test_verification_submissions.py`

**Interfaces:**
- Consumes: Task 1 `encryption`, Task 2 models.
- `IdentityProvider` gains `submit_documents(user_ref: str, front: bytes, back: bytes, selfie: bytes) -> IdentityResult`; `IdentityResult.status` gains the value `human_review`. `StaffReviewIdentity.submit_documents` returns `IdentityResult(status="human_review", full_name=None)`; its other methods behave as `MockIdentity`. `MockIdentity` gets the same method.
- Produces `class VerificationError(Exception)` with `.code`: `forbidden | invalid_state | photo_invalid | photo_too_large | document_type_invalid | commune_invalid | quartier_required | location_inaccurate`.
- Produces in `submissions` (all keyword-only after `user`; `captured_at: datetime`, `position: tuple[float, float] | None`):
  - `store_photo(user, kind: str, data: bytes, captured_at, position) -> VerificationPhoto` — checks JPEG magic bytes (`FF D8 FF`) and the size limit, writes `encrypt_bytes(data)` under `VERIFICATION_STORAGE_DIR/<uuid>.bin`.
  - `read_photo_bytes(photo: VerificationPhoto) -> bytes`
  - `submit_identity(user, *, document_type, front: bytes, back: bytes, selfie: bytes, captured_at, position=None) -> IdentityVerification`
  - `submit_address_proof(user, *, document_type, photo: bytes, commune, quartier, captured_at, position=None) -> AddressProof`
  - `record_home_location(user, *, lat: float, lng: float, accuracy_m: float, mock_location: bool, captured_at) -> HomeLocation`
- Rules: `user.role` must be `householder` (`forbidden`). A step with an open record raises `invalid_state`, except the home location: a new one replaces a `submitted`/`in_review` one (the old row is marked `refused` with reason "Remplacée") while the address proof is not `confirmed`. Everything a submission writes happens in one transaction, and photo files written before a failure are deleted. A photo whose `sha256` already exists for another user adds the flag `photo_reused` to the new record. `submit_identity` calls `registry.get_identity().submit_documents(...)`; any status other than `human_review` is ignored in this plan. `mock_location=True` is stored and adds no error. `accuracy_m > HOME_PIN_MAX_ACCURACY_M` raises `location_inaccurate`.
- Produces in `tiers`:
  - `householder_tier(user) -> str` — `"H1"` when the latest identity, address proof and home location are all `confirmed`; else `"H0"`.
  - `checklist(user) -> dict` — `{"tier", "review_hours", "communes", "identity": {"status", "reason"}, "address": {"status", "reason", "commune", "quartier", "expires_at"}, "home_location": {"status", "reason"}}`, each built from the user's most recent record of that kind; `status` is `"not_started"` when there is none; `reason` only for `refused`.
- `conftest.py` gains: `householder` (an enrolled householder user), `jpeg` (bytes of a tiny valid JPEG), an autouse fixture pointing `VERIFICATION_STORAGE_DIR` at `tmp_path`.

- [ ] **Step 1: Write the failing tests**

```python
def test_identity_submission_stores_three_encrypted_photos(householder, jpeg, settings): ...
    # status submitted; 3 files on disk; no file contains the jpeg bytes; read_photo_bytes returns them
def test_second_identity_while_open_is_invalid_state(...)
def test_refused_identity_can_be_sent_again_and_checklist_shows_the_new_one(...)   # Review Focus 1
def test_non_jpeg_and_oversized_photos_are_refused_and_leave_nothing(...)          # Review Focus 4: no rows, no files
def test_failure_on_third_photo_leaves_no_rows_and_no_files(...)                   # selfie invalid
def test_jobber_and_staff_cannot_submit(...)                                       # forbidden
def test_unknown_commune_document_type_and_blank_quartier_are_refused(...)
def test_same_image_on_two_accounts_is_flagged_photo_reused(...)
def test_inaccurate_location_is_refused_at_51_and_accepted_at_50(...)
def test_mock_location_is_recorded(...)
def test_new_location_replaces_the_previous_until_address_is_confirmed(...)        # Review Focus 5
def test_checklist_for_a_new_householder_is_all_not_started_and_h0(...)
def test_checklist_never_contains_names_numbers_or_coordinates(...)                # str(checklist) has none
def test_staff_review_identity_asks_for_human_review(...)
```
- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_verification_submissions.py` — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: verification submissions, encrypted photo storage, tiers`.

---

### Task 4: Householder API

**Files:**
- Create: `backend/apps/verification/api/__init__.py`, `serializers.py`, `views.py`, `urls.py`
- Modify: `backend/config/api_urls.py`, `backend/config/settings.py` (add `MultiPartParser` to `DEFAULT_PARSER_CLASSES`), `backend/apps/accounts/api/errors.py`
- Test: `backend/tests/test_verification_api.py`

**Interfaces:**
- Consumes: Task 3 services; `apps.accounts.permissions.IsHouseholder`.
- Endpoints, all `permission_classes = [IsHouseholder]`, all returning `tiers.checklist(request.user)`:
  - `GET /api/v1/verification`
  - `POST /api/v1/verification/identity` — multipart `document_type`, `front`, `back`, `selfie` (files), `captured_at` (ISO), optional `lat`, `lng` → 201
  - `POST /api/v1/verification/address` — multipart `document_type`, `photo`, `commune`, `quartier`, `captured_at`, optional `lat`, `lng` → 201
  - `POST /api/v1/verification/home-location` — JSON `lat`, `lng`, `accuracy_m`, `mock_location`, `captured_at` → 201
- Error mapping added to `errors.py` (code → status, message):
  - `photo_invalid` 400 "Photo illisible. Reprenez la photo."
  - `photo_too_large` 413 "Photo trop lourde. Reprenez la photo."
  - `document_type_invalid` 400 "Type de document non accepté."
  - `commune_invalid` 400 "Commune non desservie."
  - `quartier_required` 400 "Indiquez le quartier."
  - `location_inaccurate` 422 "Position trop imprécise. Rapprochez-vous d'une fenêtre ou sortez, puis réessayez."
  - `invalid_state` keeps 409; for these endpoints the message is "Cette étape est déjà envoyée."
- Uploaded files larger than the limit are refused before being read into memory (check `UploadedFile.size`).

- [ ] **Step 1: Write the failing tests** — for each of the four endpoints: no token 401, jobber token 403, staff token 403. Then `test_new_householder_sees_empty_checklist_with_communes`, `test_identity_upload_returns_checklist_with_submitted`, `test_identity_upload_twice_is_409`, `test_missing_selfie_is_400`, `test_oversized_photo_is_413`, `test_address_upload_then_checklist_shows_commune_and_quartier`, `test_unknown_commune_is_400_with_french_message`, `test_home_location_inaccurate_is_422`, `test_response_never_contains_storage_names_or_coordinates`, `test_one_householder_never_sees_anothers_status`. Add a `householder_bearer` fixture (sign in through `/api/v1/auth/token` as in `test_device_auth.py`).
- [ ] **Step 2: Run** — expected FAIL (404).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: householder verification API`.

---

### Task 5: Review service and expiry

**Files:**
- Create: `backend/apps/verification/services/review.py`, `backend/apps/verification/tasks.py`
- Modify: `backend/config/settings.py` (`CELERY_BEAT_SCHEDULE` entry `expire-address-proofs`, hourly)
- Test: `backend/tests/test_verification_review.py`

**Interfaces:**
- Consumes: Tasks 1–3.
- `VerificationError` gains codes: `under_age | document_expired | duplicate_document | identity_not_confirmed | location_missing | proof_too_old | duplicate_reference | checks_required | reason_required | field_required`. French messages for staff are added to `errors.MESSAGES`.
- Produces in `review` (each: permission check, `select_for_update` on the row, rule checks, write, one `AdminAction`):
  - `open_for_review(record, *, staff) -> None` — `submitted → in_review`; no change and no audit row in any other state. Opening an address proof also moves its `submitted` home location to `in_review`.
  - `confirm_identity(record, *, staff, full_name: str, date_of_birth: date, document_number: str, document_expires_on: date) -> None` — audit `verification.identity.confirm`
  - `refuse_identity(record, *, staff, reason: str) -> None` — `verification.identity.refuse`
  - `confirm_address(record, *, staff, holder_name: str, reference_number: str, issued_on: date, name_matches: bool, address_consistent: bool) -> None` — sets `confirmed_at`, `expires_at = confirmed_at + ADDRESS_PROOF_VALID_MONTHS`, and confirms the user's open home location; `verification.address.confirm`
  - `refuse_address(record, *, staff, reason: str, refuse_location: bool = False) -> None` — `verification.address.refuse`
  - `read_photo(photo, *, staff) -> bytes` — needs `verification.view_verification_photo`; audit `verification.view_photo` with the photo id as target and no reason text.
- Rules: decisions are allowed only from `submitted` or `in_review` (else `invalid_state`). Staff need `is_active`, `is_staff` and `verification.review_verification` (else `forbidden`). Age is computed in whole years on today's date (`under_age` below `MINIMUM_AGE_YEARS`). `document_expires_on` before today → `document_expired`. A confirmed identity with the same `keyed_hash(document_number)` on another user → `duplicate_document`; same for `reference_number` → `duplicate_reference`. `confirm_address` needs the user's latest identity `confirmed` (`identity_not_confirmed`), an open home location (`location_missing`), `issued_on` not older than `ADDRESS_PROOF_MAX_AGE_MONTHS` and not in the future (`proof_too_old`), and both booleans true (`checks_required`). Blank required text → `field_required`; blank reason → `reason_required`. Recorded names and numbers are stored with `encrypt_text`; hashes with `keyed_hash`.
- Produces `tasks.expire_address_proofs() -> int` — confirmed proofs with `expires_at <= now` become `expired`, and that user's confirmed home location becomes `expired` too.

- [ ] **Step 1: Write the failing tests**

```python
def test_confirm_identity_stores_encrypted_fields_and_audits(...)        # raw DB column != "Kouassi Aya"; one AdminAction
def test_turns_18_tomorrow_is_refused_and_turned_18_today_is_accepted(...)   # Review Focus 3, freezegun
def test_expired_document_is_refused(...)
def test_same_document_number_typed_differently_on_another_account_is_duplicate(...)   # Review Focus 2
def test_refuse_needs_a_reason_and_shows_it_in_the_checklist(...)
def test_second_decision_is_invalid_state_with_one_audit_row(...)
def test_staff_without_permission_and_non_staff_are_forbidden(...)
def test_confirm_address_requires_confirmed_identity_location_and_both_checks(...)   # four separate refusals, nothing changed
def test_proof_issued_more_than_three_months_ago_or_in_the_future_is_refused(...)
def test_duplicate_reference_number_is_refused(...)
def test_confirm_address_confirms_location_and_account_becomes_h1(...)
def test_location_cannot_be_replaced_after_address_is_confirmed(...)     # Review Focus 5
def test_expiry_task_returns_account_to_h0_and_step_can_restart(...)     # freezegun +12 months
def test_read_photo_needs_permission_and_audits_every_view(...)          # two reads -> two rows
def test_open_for_review_moves_submitted_to_in_review_once(...)
```
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: verification review rules and address proof expiry`.

---

### Task 6: Web console

**Files:**
- Create: `backend/apps/verification/admin.py`, `console_views.py`, `templates/admin/verification/identity_review.html`, `address_review.html`
- Test: `backend/tests/test_verification_console.py`

**Interfaces:**
- Consumes: Task 5 `review`, Task 3 `read_photo_bytes` (through `review.read_photo` only).
- Admin section "Vérifications" with `IdentityVerificationAdmin` and `AddressProofAdmin`: list columns created date, user phone, status, flags; default list filter on `submitted` and `in_review`; oldest first; no add, change or delete permission (as `DeviceEnrolmentRequestAdmin`). The change page is replaced by the review template.
- Opening a review page calls `review.open_for_review`.
- Custom URLs under each admin (wrapped with `admin_site.admin_view`, POST only for decisions):
  - `<uuid:pk>/confirm/`, `<uuid:pk>/refuse/`
  - `photo/<uuid:photo_id>/` → `image/jpeg`, `Cache-Control: no-store`, through `review.read_photo`; 403 without the permission.
- Identity page: three photos side by side (`<img>` pointing at the photo URL), form fields "Nom complet", "Date de naissance", "Numéro du document", "Date d'expiration", buttons "Confirmer" and "Refuser" (with "Motif"), and the flags in French (`photo_reused` → "Cette photo a déjà été envoyée par un autre compte.").
- Address page: the photo, document type, commune, quartier; home location block with latitude, longitude, accuracy, "Position simulée détectée" when `mock_location`, and a link "Voir sur la carte" to `https://www.openstreetmap.org/?mlat=<lat>&mlon=<lng>#map=17/<lat>/<lng>`; the confirmed identity name (or "Identité non confirmée"); form "Nom du titulaire", "Numéro client ou référence", "Date d'émission"; tick boxes "Le nom correspond à l'identité confirmée" and "L'adresse correspond à la commune, au quartier et à la position"; "Confirmer" / "Refuser".
- Service errors are shown with `messages.error` using `errors.MESSAGES`, then redirect back to the page. `forbidden` → 403.
- Decrypted names and coordinates appear only on these pages, which send `Cache-Control: no-store`.

- [ ] **Step 1: Write the failing tests** — `test_verification_agent_sees_both_queues`, `test_enrolment_agent_gets_403_on_queues_and_photos`, `test_opening_identity_page_marks_in_review_and_shows_three_photo_links`, `test_photo_view_returns_the_jpeg_with_no_store_and_audits`, `test_confirm_identity_through_the_form`, `test_under_age_shows_french_error_and_changes_nothing`, `test_refuse_without_reason_shows_error`, `test_address_page_shows_location_map_link_and_mock_warning`, `test_confirm_address_through_the_form_makes_h1`, `test_decisions_via_get_are_405`, `test_review_pages_are_no_store`. Add a `verifier_client` fixture (staff user in `verification_agent`).
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `.venv/bin/pytest` and ruff — expected PASS.
- [ ] **Step 5: Commit** — `feat: verification review in the web console`.

---

### Task 7: Flutter core — verification API, models, controller

**Files:**
- Create: `mobile/packages/petitgombo_core/lib/src/verification/verification_models.dart`, `verification_api.dart`, `verification_controller.dart`, `capture.dart`
- Modify: `lib/src/auth/session.dart`, `lib/src/app/providers.dart`, `lib/petitgombo_core.dart`
- Test: `test/verification_api_test.dart`, `test/verification_controller_test.dart`, `test/session_test.dart`

**Interfaces:**
- Consumes: Task 4 endpoints; existing `ApiError`, `guardApi`, `Session`, `FakeAdapter`.
- `Session.authorized<T>(Future<T> Function(String access) call) -> Future<T>` — runs `call` with the access token; on an `ApiError` with status 401 it refreshes once (shared in-flight refresh, as `StaffSession.refresh` in `mobile/apps/staff/lib/src/staff_session.dart`) and retries; if that fails it rethrows the 401.
- `capture.dart`:
  - `class CapturedPhoto { final Uint8List bytes; final DateTime capturedAt; final (double, double)? position; }`
  - `class DevicePosition { final double lat, lng, accuracyM; final bool mocked; final DateTime capturedAt; }`
  - `enum CaptureFailure { permissionDenied, permissionDeniedForever, unavailable }` and `class CaptureException implements Exception { final CaptureFailure failure; }`
  - `abstract class PhotoCapture { Future<CapturedPhoto?> take(BuildContext context, {required PhotoKind kind}); }` (null when the user backs out); `enum PhotoKind { idFront, idBack, selfie, addressProof }`
  - `abstract class PositionReader { Future<DevicePosition> current(); Future<void> openSettings(); }`
  - Providers `photoCaptureProvider`, `positionReaderProvider`, both throwing `UnimplementedError` until an app overrides them.
- `verification_models.dart`: `enum StepStatus { notStarted, submitted, inReview, confirmed, refused, expired }` (parsed from `not_started`, `in_review`, …; unknown values → `submitted`), `class StepState { status, reason }`, `class AddressState extends StepState { commune, quartier, expiresAt }`, `class VerificationChecklist { tier, reviewHours, communes, identity, address, homeLocation; bool get verified => tier == 'H1'; }` with `fromJson`.
- `VerificationApi(Dio dio)`:
  - `Future<VerificationChecklist> checklist(String access)`
  - `Future<VerificationChecklist> submitIdentity(String access, {required String documentType, required CapturedPhoto front, required CapturedPhoto back, required CapturedPhoto selfie})` — multipart; `captured_at` is the selfie's time; file names `front.jpg`, `back.jpg`, `selfie.jpg`, content type `image/jpeg`
  - `Future<VerificationChecklist> submitAddress(String access, {required String documentType, required CapturedPhoto photo, required String commune, required String quartier})`
  - `Future<VerificationChecklist> recordHomeLocation(String access, DevicePosition position)`
- `VerificationController extends StateNotifier<VerificationState>` with `VerificationState { VerificationChecklist? checklist; bool loading; bool sending; String? error; }` and methods `load()`, `sendIdentity(...)`, `sendAddress(...)`, `recordHome()` (reads the position, then posts), each returning `Future<bool>` (true on success). All calls go through `Session.authorized`. Errors become French text: the server `message` when present; `network` → "Pas de connexion. Vos photos sont gardées. Réessayez."; position failures → the `VerificationCopy` texts of Task 8. Provider `verificationControllerProvider`.

- [ ] **Step 1: Write the failing tests**

```dart
// verification_api_test.dart
test('checklist parses statuses, communes and tier', ...);
test('submitIdentity posts multipart with three jpeg parts and the document type', ...);   // FormData fields and files
test('413 becomes ApiError(code: photo_too_large) with the French message', ...);
test('recordHomeLocation sends lat, lng, accuracy_m, mock_location, captured_at', ...);
// verification_controller_test.dart
test('load fills the checklist', ...);
test('sendIdentity success replaces the checklist and returns true', ...);
test('network failure keeps the state, sets the retry message and returns false', ...);   // Review Focus 4
test('refused step can be sent again', ...);                                                // Review Focus 1
test('recordHome maps permissionDenied to the French message', ...);
test('an expired access token is refreshed once and the call retried', ...);
// session_test.dart
test('authorized refreshes on 401 and retries once', ...);
test('authorized rethrows when the refresh is refused', ...);
```
- [ ] **Step 2: Run** `flutter test` in `mobile/packages/petitgombo_core` — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test && flutter analyze` — expected all pass, no issues.
- [ ] **Step 5: Commit** — `feat(mobile): verification API and controller`.

---

### Task 8: Flutter screens and householder app wiring

**Files:**
- Create: `mobile/packages/petitgombo_core/lib/src/verification/verification_copy.dart`, `screens/checklist_screen.dart`, `screens/identity_flow.dart`, `screens/address_flow.dart`, `screens/home_location_screen.dart`; `mobile/apps/householder/lib/device_capture.dart`
- Modify: `mobile/packages/petitgombo_core/lib/src/app/petitgombo_app.dart` (signed-in householder → `ChecklistScreen`; jobber unchanged), `lib/petitgombo_core.dart`, `mobile/apps/householder/lib/main.dart`, `mobile/apps/householder/pubspec.yaml` (`camera`, `geolocator`, `image`), `mobile/apps/householder/android/app/src/main/AndroidManifest.xml` (`CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`), `android/app/build.gradle` (`minSdk` 21 if the default is lower)
- Test: `mobile/packages/petitgombo_core/test/verification_screens_test.dart`, `mobile/apps/householder/test/app_test.dart`

**Interfaces:**
- Consumes: Task 7.
- `VerificationCopy` (exact French):
  - title "Vérification de votre compte"; verified "Compte vérifié"; intro "Trois étapes pour publier vos offres."
  - step titles "Pièce d'identité", "Justificatif de domicile", "Position du domicile"
  - statuses: not started → button "Commencer"; submitted → "Envoyé. Nous vérifions sous {hours} h."; in review → "En cours de vérification."; confirmed → "Confirmé"; refused → the reason + button "Recommencer"; expired → "Justificatif expiré. Envoyez-en un nouveau." + "Recommencer"
  - document types: `cni` "Carte nationale d'identité", `passport` "Passeport", `carte_consulaire` "Carte consulaire", `permis` "Permis de conduire", `facture_eau` "Facture d'eau", `facture_electricite` "Facture d'électricité", `certificat_residence` "Certificat de résidence"
  - capture titles "Recto du document", "Verso du document", "Votre visage"; review buttons "Reprendre", "Utiliser cette photo"; send "Envoyer"
  - address note "Le document doit être à votre nom et dater de moins de 3 mois."; fields "Commune", "Quartier"
  - home "Faites cette étape chez vous." ; button "Enregistrer ma position"; done "Position enregistrée."
  - permission texts "Autorisez l'appareil photo pour continuer." / "Autorisez la localisation pour continuer." + button "Ouvrir les réglages"; "Position indisponible. Activez la localisation et réessayez."
- `ChecklistScreen` (ConsumerStatefulWidget): loads on start, on pull-to-refresh and when the app returns to the foreground; skeleton rows while loading; `MessageBanner` with "Réessayer" on error; three step cards (icon + status text + action button); "Se déconnecter" at the bottom (callback passed by the app root). A step's action opens its flow with `Navigator.push`; the flow pops on success.
- `IdentityFlow`: document-type list → capture front → capture back → capture selfie → summary with three thumbnails and "Envoyer". Each capture calls `PhotoCapture.take` and shows the review step. Photos are held in widget state only.
- `AddressFlow`: type list → capture → form (commune dropdown from `checklist.communes`, quartier field, per-field `errorText`) → "Envoyer".
- `HomeLocationScreen`: explanation, the button, then the result or the error with "Ouvrir les réglages" when denied forever.
- `device_capture.dart` in the householder app: `CameraPhotoCapture implements PhotoCapture` (full-screen `CameraPreview` with a frame overlay, rear camera for documents and front camera for the selfie, shutter button with tooltip "Prendre la photo"; resizes to at most 1600 px on the long side and re-encodes JPEG quality 80 with the `image` package in a background isolate; never saves to the gallery) and `GeolocatorPositionReader implements PositionReader` (`LocationAccuracy.high`, 20 s timeout, `Position.isMocked`). `main.dart` overrides `photoCaptureProvider` and `positionReaderProvider` with them.

- [ ] **Step 1: Write the failing tests** (fakes for `PhotoCapture`, `PositionReader` and the controller, as `test/support/fake_controller.dart`)

```dart
testWidgets('checklist shows three steps with Commencer for a new householder', ...);
testWidgets('each status shows its French text', ...);            // submitted with 24 h, in review, confirmed, expired
testWidgets('refused step shows the reason and Recommencer', ...);
testWidgets('H1 shows Compte vérifié', ...);
testWidgets('identity flow takes three photos then sends them', ...);   // fake capture called with idFront, idBack, selfie
testWidgets('Reprendre takes the photo again', ...);
testWidgets('a failed send keeps the photos and offers Envoyer again', ...);   // Review Focus 4
testWidgets('address form requires commune and quartier before sending', ...);
testWidgets('home location denied forever offers Ouvrir les réglages', ...);
testWidgets('small phone with large text does not overflow', ...);     // checklist, identity summary, address form at 320dp, scale 2
// householder app_test.dart
testWidgets('a signed-in householder lands on the verification checklist', ...);
```
Also assert in `mobile/apps/jobber/test/app_test.dart` that nothing changed (existing test still passes).
- [ ] **Step 2: Run** `flutter test` — expected FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test && flutter analyze` in `petitgombo_core`, `householder`, `jobber`, `staff`; `flutter build apk --debug` in `householder` — expected all pass.
- [ ] **Step 5: Commit** — `feat(mobile): householder verification screens with in-app camera and home position`.

---

### Task 9: Documentation and end-to-end check

**Files:**
- Modify: `README.md`, `docs/deployment.md`, `docs/threat-model.md`, `.gitignore` (`backend/verification_storage/`)

- [ ] **Step 1: README** — a "Verification" section: the three steps, how to give a staff user the `verification_agent` group, where the queues are in the console, the new settings.
- [ ] **Step 2: `docs/deployment.md`** — `FIELD_ENCRYPTION_KEY` (generate with `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`; losing it makes every photo and encrypted field unreadable; keep a copy outside the server), the `verification_data` volume, a backup command for that volume, and the statement that a database backup without the volume and the key is incomplete. Add "lawful basis for holding identity photos" to "Still open".
- [ ] **Step 3: `docs/threat-model.md`** — "Forged or reused documents" and "Lure listings" → "partly built" with what is covered (in-app capture, reuse flags, duplicate numbers, staff review, proof of address tied to a home position) and what is not (no liveness, no automated document check, third-party route); "Data breach" notes encrypted photos and fields, with the test files.
- [ ] **Step 4: End-to-end manual check on a phone.** With the backend running and a phone connected (`adb reverse tcp:8000 tcp:8000`): complete the three steps in the householder app; in the console confirm identity then address; reopen the app and see "Compte vérifié". Then on a second householder number refuse the identity and see the reason and "Recommencer". Record the result in the ledger, or why it could not be run.
- [ ] **Step 5: Commit** — `docs: verification setup, deployment and threat model`.

---

## Spec coverage

| Spec section | Task |
|--------------|------|
| Three steps, statuses, tier | 2, 3, 5 |
| Server rules and settings | 1, 3, 5 |
| Storage and privacy | 1, 3, 5, 6 |
| Models | 2 |
| Services, identity provider seam | 1, 3, 5 |
| API | 4 |
| Web console, permissions, group | 2, 6 |
| Deployment | 1, 9 |
| Householder app | 7, 8 |
| Tests | each task |
| Threat model | 9 |
