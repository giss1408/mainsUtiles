# Jobber Verification 3a (identity and guarantor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A jobber sends identity photos and a guarantor's bill, staff confirm both in the web console, and the jobber app shows the progress, the tier J0/J1 and real badges.

**Architecture:** Reuse the householder verification code. `submit_identity` opens to jobbers; a new `Guarantor` model follows the `Reviewed` pattern (services hold every rule, views only translate HTTP). The jobber tier is computed from the setting `JOBBER_REQUIRED_STEPS`. In the app, `VerificationApi`/controller/checklist screen become role-aware; the guarantor flow is new.

**Tech Stack:** Django 5.2 + DRF, pytest, Celery beat; Flutter 3.24.2, Riverpod, Dio.

**Spec:** `docs/superpowers/specs/2026-11-13-jobber-verification-design.md`

## Global Constraints

- User-facing copy French: jobber "tu", console and householder "vous". Code and comments English.
- No new packages. Never commit secrets. Do not push.
- Statuses only in every API response: never the guarantor's name or phone, the bill photo, or any identity field.
- Encrypt with `encrypt_text`; compare numbers with `keyed_hash(normalise_number(...))` (see `apps/verification/services/encryption.py`). Normalise phones with `apps.accounts.phones.normalise` (raises `InvalidPhone`).
- Every staff decision, view and call record leaves an audit row via `apps.audit.services.record`.
- Settings (new, env-overridable like their neighbours in `config/settings.py`): `GUARANTOR_DOCUMENT_TYPES` = `facture_eau, facture_electricite, certificat_residence, abonnement_prepaye`; `GUARANTOR_BILL_MAX_AGE_MONTHS` = 3; `GUARANTOR_VALID_MONTHS` = 12; `GUARANTOR_MAX_JOBBERS` = 3; `JOBBER_REQUIRED_STEPS` = `identity, guarantor`.
- Mobile: 320dp at text scale 2 must not overflow; lists are non-lazy columns; the repo formats Dart at `dart format -l 100` (format only files you touch).
- Run the full suite of the package you touched before each commit: `cd backend && .venv/bin/pytest && .venv/bin/ruff check .`; `cd mobile/packages/petitgombo_core && flutter test && flutter analyze`; same for `mobile/apps/jobber`.

## Review Focus

- The guarantor's phone typed in another form (`+225…`, `00225…`, spaces) must still be refused when it is the jobber's own number. (Task 2)
- A bill reference already backing `GUARANTOR_MAX_JOBBERS` other jobbers, including one whose guarantor expired, must be refused. (Task 3)
- Confirming before the identity is confirmed, or before the call is recorded, must fail with its own code. (Task 3)
- A householder, an anonymous caller, staff and another jobber must not reach, or see, a jobber's checklist or guarantor. (Task 5)
- Two staff confirming the same guarantor at once: one wins, no duplicate and no 500. (Task 3)
- A jobber at J1 whose guarantor expires drops back to J0 and may resubmit. (Task 4)
- A refused step can be restarted; a refused reason is shown to the jobber, a note that mentions the guarantor never contains their phone. (Tasks 5, 9)
- Existing jobber app tests queue exact server replies; the new checklist request on Offres must not break them. (Task 10)

---

## Backend

### Task 1: Settings, model, migrations

**Files:**
- Modify: `backend/config/settings.py` (settings above, next to `ADDRESS_PROOF_TYPES`; beat entry `expire-guarantors` every 3600 s)
- Modify: `backend/apps/verification/models.py`
- Create: `backend/apps/verification/migrations/0003_guarantor.py`, `0004_guarantor_permissions.py`
- Test: `backend/tests/test_guarantor_models.py`

**Interfaces:**
- Produces: `VerificationPhoto.Kind.GUARANTOR_BILL = "guarantor_bill"`; `Guarantor(Reviewed)` with fields `photo` (PROTECT FK), `document_type` (CharField 30), `guarantor_name` and `guarantor_phone` (TextField, encrypted), `guarantor_phone_hash` (CharField 64, indexed), `relationship` (choices `parent`, `relative`, `landlord`, `other`), `holder_name`, `reference_number` (TextField, encrypted), `reference_hash` (CharField 64, blank, indexed), `issued_on` (Date, null), `contacted_at` (DateTime, null), `contacted_by` (FK user, null, PROTECT), `confirmed_at`, `expires_at` (DateTime, null). Constraint `one_open_guarantor_per_user` via `_one_open_per_user`. Permission `view_guarantor` in the `verification_agent` group (migration 0004, same pattern as `0002_verification_agent_group.py`).

- [ ] **Step 1: Write failing tests** in `test_guarantor_models.py`: `test_one_open_guarantor_per_user` (second open record raises `IntegrityError`; a refused one does not block a new one), `test_photo_kind_guarantor_bill_exists`, `test_verification_agent_group_can_view_guarantors`.
- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_guarantor_models.py -v`. Expected: FAIL (model missing).
- [ ] **Step 3: Implement** the settings, model and both migrations; generate 0003 with `makemigrations verification -n guarantor` and check `makemigrations --check` is clean.
- [ ] **Step 4: Run** the new tests, then the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): guarantor model and settings`.

### Task 2: Submissions: jobbers send identity, guarantor submission

**Files:**
- Modify: `backend/apps/verification/services/submissions.py`
- Test: `backend/tests/test_guarantor_submissions.py`, extend `backend/tests/test_verification_submissions.py` only where a householder-only assertion changes

**Interfaces:**
- Produces: `submit_identity` accepts role `jobber` too (new `_require_applicant(user)`: active, role in householder/jobber); `submit_address_proof` and `record_home_location` stay householder-only. New:
  `submit_guarantor(user, *, document_type: str, photo: bytes, guarantor_name: str, guarantor_phone: str, relationship: str, captured_at: datetime, position: Position | None = None) -> Guarantor` (jobber only).
- New error codes (add to `STATUS` as 400 and `MESSAGES` in `apps/accounts/api/errors.py`, French "tu" is not used there: console and API messages are neutral): `guarantor_phone_invalid` "Numéro du garant invalide.", `guarantor_phone_own` "Le garant ne peut pas être toi-même : indique le numéro d'une autre personne.", `guarantor_name_required` "Indique le nom du garant.", `relationship_invalid` "Choisis le lien avec le garant."

- [ ] **Step 1: Write failing tests**: `test_jobber_can_submit_identity`, `test_householder_cannot_submit_guarantor` (`forbidden`), `test_guarantor_is_stored_encrypted` (raw DB columns contain neither the name nor the phone), `test_guarantor_phone_same_as_jobber_is_refused_in_any_format` (parametrized `+2250505050505`, `0505050505`, `00225 05 05 05 05 05`), `test_invalid_phone_name_relationship_document_type_refused` (one case per code), `test_second_open_guarantor_is_refused` (`invalid_state`), `test_refused_guarantor_can_be_resubmitted`, `test_failed_submission_leaves_no_file` (the `_submission` contextmanager removes written files), `test_reused_photo_is_flagged` (`photo_reused`).
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** reusing `store_photo`, `_submission`, `_reused`, `_require_no_open`. Name stripped and capped at 120 characters.
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): jobbers send identity and a guarantor`.

### Task 3: Review service for guarantors

**Files:**
- Modify: `backend/apps/verification/services/review.py`, `backend/apps/accounts/api/errors.py`
- Test: `backend/tests/test_guarantor_review.py`

**Interfaces:**
- Produces (all `staff` keyword, permission `REVIEW`, same locking pattern as `confirm_address`):
  `record_call(record: Guarantor, *, staff, knows_jobber: bool, confirms_residence: bool, agrees_contact: bool) -> None` (needs all three true, else `checks_required`; sets `contacted_at`, `contacted_by`; moves a submitted record to in-review; audit `verification.guarantor.call`);
  `confirm_guarantor(record, *, staff, holder_name: str, reference_number: str, issued_on: date, name_matches: bool) -> None`;
  `refuse_guarantor(record, *, staff, reason: str) -> None`. `open_for_review` and `record_view` also accept a `Guarantor` (`_kind` returns `"guarantor"`).
- New codes: `call_required` "Notez d'abord l'appel au garant.", `bill_reference_cap` "Ce justificatif garantit déjà le nombre maximum de mini-jobbers." (400).
- Confirm rules: identity of `record.user` is confirmed (`identity_not_confirmed`); `contacted_at` set (`call_required`); `name_matches` true (`checks_required`); `issued_on` within `GUARANTOR_BILL_MAX_AGE_MONTHS` and not future (`proof_too_old`); the reference hash backs fewer than `GUARANTOR_MAX_JOBBERS` other users among confirmed and expired guarantors (`bill_reference_cap`); on success `confirmed_at = now`, `expires_at = now + GUARANTOR_VALID_MONTHS`; `IntegrityError` maps to `invalid_state`.

- [ ] **Step 1: Write failing tests**: `test_call_requires_all_three_answers`, `test_confirm_requires_identity_confirmed`, `test_confirm_requires_recorded_call`, `test_confirm_requires_name_match`, `test_confirm_sets_dates_and_encrypts_fields`, `test_old_and_future_bills_refused`, `test_reference_cap_counts_expired_and_other_users_only`, `test_same_jobber_can_renew_with_same_reference`, `test_two_confirmations_race_one_wins` (second call raises `invalid_state`), `test_refuse_needs_reason_and_shows_it`, `test_every_step_is_audited`, `test_staff_without_permission_forbidden`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement**, using `_locked`, `_require_undecided`, `_text`, `_reason`, `_shift_months`, `keyed_hash`.
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): staff review of guarantors`.

### Task 4: Jobber tier, checklist, expiry

**Files:**
- Modify: `backend/apps/verification/services/tiers.py`, `submissions.py` (`expire_guarantors`), `tasks.py`
- Test: `backend/tests/test_jobber_tier.py`

**Interfaces:**
- Produces: `jobber_tier(user) -> str` ("J1" when every step named in `settings.JOBBER_REQUIRED_STEPS` is confirmed, else "J0"; non-jobber "J0"); `jobber_checklist(user) -> dict` with keys `tier`, `review_hours`, `identity` and `guarantor` (each `{"status", "reason"}` via `_step`; the guarantor status becomes `confirmed`→`expired` once past `expires_at`, like `_status`), `required` (the setting as a list); `expire_guarantors(user=None) -> int`; Celery task `apps.verification.tasks.expire_guarantors`. `current_record` and `_status` work for `Guarantor` unchanged.

- [ ] **Step 1: Write failing tests**: `test_tier_is_j0_until_all_required_steps_confirmed`, `test_required_steps_setting_changes_the_tier` (override to `["identity"]`), `test_expired_guarantor_drops_to_j0_and_can_be_resubmitted`, `test_checklist_has_statuses_only` (no name, phone, hash or photo anywhere in the dict), `test_expire_task_sweeps_overdue_guarantors`, `test_householder_tier_unchanged`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): jobber tier and checklist`.

### Task 5: Jobber verification API

**Files:**
- Create: `backend/apps/verification/api/jobber_views.py`, `jobber_urls.py`
- Modify: `backend/apps/verification/api/serializers.py`, `backend/apps/verification/api/urls.py` (include under `jobber/`)
- Test: `backend/tests/test_jobber_verification_api.py`

**Interfaces:**
- Produces: `GET /api/v1/jobber/verification` → `{tier, review_hours, required, identity{status,reason}, guarantor{status,reason}}`; `POST /api/v1/jobber/verification/identity` (same multipart fields as the householder one, 201 + checklist); `POST /api/v1/jobber/verification/guarantor` (multipart: `document_type`, `photo`, `guarantor_name`, `guarantor_phone`, `relationship`, `captured_at`, optional `lat`/`lng`; 201 + checklist). Permission `IsJobber`. Errors via `error_response`; `invalid_state` 409 with the householder's `ALREADY_SENT` text. Uploads checked with the same size guard as `_read`.

- [ ] **Step 1: Write failing tests** (use `enrol_device(phone=..., role="jobber")` and `bearer_for`): `test_checklist_for_new_jobber`, `test_identity_then_guarantor_roundtrip_201`, `test_householder_token_gets_403_on_every_jobber_endpoint`, `test_jobber_token_gets_403_on_householder_endpoints`, `test_anonymous_gets_401`, `test_staff_token_refused`, `test_response_never_contains_guarantor_name_phone_or_photo` (scan the JSON text for the submitted name, phone digits and storage name), `test_error_codes_map_to_status_and_french_message` (one per new code), `test_double_submit_returns_409`, `test_oversized_photo_413`, `test_one_jobber_cannot_see_another_jobbers_state`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** thin views over `submissions.*` and `tiers.jobber_checklist`; add drf-spectacular `extend_schema` like the householder views.
- [ ] **Step 4: Run** the full backend suite, ruff and `manage.py spectacular --validate`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): jobber verification API`.

### Task 6: Console queue "Garants"

**Files:**
- Modify: `backend/apps/verification/admin.py`, `backend/apps/verification/console_views.py`
- Create: `backend/apps/verification/templates/admin/verification/guarantor_review.html`
- Test: `backend/tests/test_guarantor_console.py`

**Interfaces:**
- Produces: `GuarantorAdmin(ReviewAdmin)` ("Garants", default filter "À traiter"), routes `verification_guarantor_call`, `_confirm`, `_refuse`, `_photo` (same pattern as `AddressProofAdmin.get_urls`); `review_context` returns the bill URL, the guarantor's decrypted name, phone, relationship, the jobber's confirmed identity name, `contacted_at`, and `flag_texts`. The template shows the script prompts ("Connaît-il le jeune ?", "Confirme son identité et son domicile ?", "Accepte d'être contacté ?"), a call form, then the confirm form (holder name, reference, issue date, name-match checkbox) and the refuse form (reason). A page view audits `verification.guarantor.view` (already done by `change_view`). The pages are `no-store`.

- [ ] **Step 1: Write failing tests**: `test_verifier_sees_guarantor_queue_todo_first`, `test_review_page_shows_name_phone_and_audits_the_view`, `test_call_confirm_refuse_flow_through_the_console`, `test_confirm_before_call_shows_the_french_error`, `test_photo_is_served_no_store_and_audited`, `test_enrolment_agent_without_permission_gets_403`, `test_list_page_shows_no_encrypted_columns`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(console): guarantor review queue`.

## Mobile

### Task 7: Core models, API and controller made role-aware

**Files:**
- Modify: `mobile/packages/petitgombo_core/lib/src/verification/verification_models.dart`, `verification_api.dart`, `verification_controller.dart`
- Test: extend `test/verification_api_test.dart`, `test/verification_controller_test.dart`; extend `test/support/verification_fixtures.dart` (`jobberChecklistJson({String tier='J0', identity, guarantor})`)

**Interfaces:**
- Produces: `VerificationChecklist` gains `guarantor` (`VerificationStep`, default not started when absent) and `bool get forJobber => tier.startsWith('J')`; `verified` becomes `tier == 'H1' || tier == 'J1'`; `address` and `homeLocation` default to not-started when absent (keeps every householder caller unchanged). `VerificationApi(Dio dio, {String base = '/api/v1/verification'})`; new `submitGuarantor(String access, {required String documentType, required CapturedPhoto photo, required String guarantorName, required String guarantorPhone, required String relationship}) -> Future<VerificationChecklist>`. `verificationApiProvider` picks base `/api/v1/jobber/verification` when `appRoleProvider == AppRole.jobber`. `VerificationController.sendGuarantor(...)` (same parameters, returns `Future<bool>`, same `_send` handling, offline copy keeps the photo).

- [ ] **Step 1: Write failing tests**: `jobber checklist parses guarantor and J0/J1`, `householder checklist still parses and has no guarantor step`, `api posts guarantor multipart to the jobber base` (fields and a `guarantor_phone` equal to the normalised `+225` form), `api uses the jobber base only for the jobber role`, `controller sendGuarantor stores the new checklist`, `controller treats 409 invalid_state as already sent`.
- [ ] **Step 2: Run** `flutter test test/verification_api_test.dart test/verification_controller_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** Normalise the phone with `normaliseIvorianPhone` before sending; the controller refuses (sets `VerificationCopy.guarantorPhoneInvalid`) when it returns null.
- [ ] **Step 4: Run** the package suite and analyzer. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): role-aware verification API and controller`.

### Task 8: Voice (tu/vous) and a role-aware checklist

**Files:**
- Modify: `verification_copy.dart`, `screens/checklist_screen.dart`, `screens/identity_flow.dart`, `screens/photo_step.dart`
- Test: extend `test/verification_screens_test.dart`

**Interfaces:**
- Produces: `abstract final class VerificationVoice` with `vous` and `tu` const instances of one class holding the strings that differ: `title` ("Vérification de votre compte" / "Vérifie ton compte"), `intro` (3 steps / "Deux étapes pour pouvoir postuler."), `verifiedBody`, `chooseIdentityDocument` ("Quel document vas-tu utiliser ?"), `captureSelfie` ("Ton visage"), `selfieHint`, `summaryTitle`, `identityPrivacy` (the existing note / "Tes photos sont chiffrées et vues seulement par notre équipe de vérification. Chaque consultation est enregistrée."). `final verificationVoiceProvider = Provider<VerificationVoice>` from `appRoleProvider`. `ChecklistScreen` shows identity and guarantor for a jobber (`guarantorTitle` = "Garant", with a `Commencer` button opening `GuarantorFlow`, built in Task 9) and the three householder steps otherwise; the existing householder wording is unchanged.

- [ ] **Step 1: Write failing tests**: `jobber checklist shows identity and guarantor in tu`, `householder checklist is unchanged`, `identity flow for a jobber asks for the document in tu`, `jobber verified note shown at J1`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Until Task 9, the Garant button opens a placeholder `Scaffold` so the test of the card compiles; replace it there.
- [ ] **Step 4: Run** the package suite and analyzer. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): checklist and identity flow in the jobber voice`.

### Task 9: Guarantor flow

**Files:**
- Create: `lib/src/verification/screens/guarantor_flow.dart`
- Modify: `verification_copy.dart` (guarantor strings), `petitgombo_core.dart` (export)
- Test: `test/guarantor_flow_test.dart`

**Interfaces:**
- Produces: `GuarantorFlow()` with `FlowScaffold` steps "Étape x sur 4": 1 who vouches (keys `guarantor-name`, `guarantor-phone`, relationship choice cards parent / famille / propriétaire / autre), 2 document type choice cards (`VerificationCopy.guarantorDocumentTypes`: facture d'eau, d'électricité, certificat de résidence, abonnement prépayé), 3 bill photo via `PhotoStep` with a new `PhotoKind.guarantorBill`, 4 summary with a `BusyButton` "Envoyer" calling `sendGuarantor`, then pops. A `PrivacyNote` on step 1: "On appelle ton garant pour confirmer. On utilise son numéro seulement pour ça, et la facture n'est vue que par notre équipe de vérification." Validation: name non-empty; phone via `normaliseIvorianPhone` with error text under the field.

- [ ] **Step 1: Write failing tests** (reuse `settle`, `FakeAdapter`, `SignedInSession` helpers like `verification_screens_test.dart`): `shows progress and the privacy note on step 1`, `empty name and invalid phone show their errors and do not advance`, `a full run posts one multipart request with a normalised phone and pops`, `back keeps typed text and removes the last photo`, `an offline error keeps the photo and shows Réessayer`, `does not overflow at 320dp and text scale 2`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** following `identity_flow.dart` (`PopScope`, in-memory photos, `FlowScaffold`).
- [ ] **Step 4: Run** the package suite and analyzer. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): guarantor flow`.

### Task 10: Jobber app integration, badges, docs

**Files:**
- Modify: `offers/screens/offers_screen.dart` (a `VerificationCard` above the list), `profile/profile_screen.dart` (jobber badges), `info/info_screens.dart` (privacy section on the guarantor), `docs/threat-model.md`, `README.md`
- Test: extend `test/offers_screens_test.dart`, `test/shell_profile_test.dart`, `mobile/apps/jobber/test/app_test.dart`

**Interfaces:**
- Produces: `VerificationCard` (card with `IconTile`, "Fais vérifier ton compte" + "1 étape sur 2" progress, tap pushes `ChecklistScreen(onBack: ...)`; at J1 it shows "Compte vérifié" and is not tappable-heavy: still opens the checklist; while the checklist loads or fails it renders nothing, so Offres never blocks). Profil badges for a jobber: `Téléphone confirmé`, `Identité vérifiée`, `Garant confirmé`, driven by `verificationControllerProvider.checklist`, nothing earned that is not confirmed. Privacy notice gains an "Informations sur votre garant" section (what is collected about a guarantor, why, who sees it). Threat-model rows: lure/identity of jobber, forged guarantor bill, guarantor phone equal to jobber's number, reused bill across accounts, insider read of guarantor data. README: "Jobber verification" section (flow, console queue, settings, open decisions).

- [ ] **Step 1: Write failing tests**: `offers screen shows the verification card with progress`, `the card opens the checklist and a failed load hides it without blocking offers`, `jobber profile shows only the confirmed badges`, `jobber app lands on Offres and the new request does not break the existing flows` (update the reply queues of `app_test.dart` where the extra `GET /jobber/verification` is made).
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** and update the docs.
- [ ] **Step 4: Run** all suites (backend, core, jobber, householder, staff) and analyzers. Expected: PASS. Build the debug APK of the jobber app (`flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8000`) and try the flow by hand if a phone is unlocked; say plainly if it was not run.
- [ ] **Step 5: Commit** `feat(mobile): verification card, badges and docs for jobbers`.
