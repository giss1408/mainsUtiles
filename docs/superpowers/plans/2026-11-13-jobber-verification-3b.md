# Jobber Verification 3b (trusted contact and safety briefing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A jobber names up to two trusted contacts who confirm by a WhatsApp code that staff send, answers a staff-edited safety briefing, and reaches tier J1 only when identity, guarantor, trusted contact and briefing are all done.

**Architecture:** Same layering as 3a: services in `apps/verification/services/` hold every rule, views only translate HTTP, the tier is computed from `JOBBER_REQUIRED_STEPS`. The contact is confirmed by a code that a staff member sends by WhatsApp from the web console (a one-time `wa.me` link built with `registry.get_messaging().whatsapp_link`, as for device enrolment); the jobber types the code the contact reads out. The briefing is answered in the app, with no review. In the app, the checklist gains two steps, each with its own small controller and flow screens.

**Tech Stack:** Django 5.2 + DRF, pytest, Celery beat; Flutter 3.24.2, Riverpod, Dio.

**Spec:** `docs/superpowers/specs/2026-11-13-jobber-verification-design.md` (section "Plan 3b"). Builds on `docs/superpowers/plans/2026-11-13-jobber-verification-3a.md`.

## Global Constraints

- User-facing copy French: jobber "tu"; console "vous". API error messages stay neutral, like the 3a ones. Code and comments English.
- No new packages. Never commit secrets. Do not push unless asked.
- The jobber API returns statuses and the jobber's own labels only: never a contact's or guarantor's phone, a code or its hash, a briefing answer key (`correct_index`), or any identity field.
- Encrypt with `encrypt_text`; compare numbers with `keyed_hash(normalise_number(...))`; normalise phones with `apps.accounts.phones.normalise` (raises `InvalidPhone`). Codes are 6 digits from `secrets`, shown to staff once and never returned by the API, stored as the HMAC used by `enrolment._hash_code` (key `SECRET_KEY`, message `"{pk}:{code}"`), compared with `hmac.compare_digest`.
- New settings, env-overridable in `config/settings.py` beside `JOBBER_REQUIRED_STEPS`: `TRUSTED_CONTACTS_MAX` = 2; `TRUSTED_CONTACT_CODE_TTL_MINUTES` = 1440 (staff send during the day, the contact may answer later); `TRUSTED_CONTACT_CODE_MAX_ATTEMPTS` = 5; `TRUSTED_CONTACT_RESEND_SECONDS` = 600 (wait between code requests); `TRUSTED_CONTACT_MAX_ADDS_PER_DAY` = 3; `TRUSTED_CONTACT_CHANGE_DELAY_HOURS` = 72. A trusted contact is never deleted, only replaced. `JOBBER_REQUIRED_STEPS` default becomes `identity, guarantor, trusted_contact, briefing`.
- New step statuses in the checklist: `not_started`, `in_progress`, `confirmed` (these two steps have no confirm/refuse review, so no `submitted`/`in_review`/`refused`).
- Mobile: 320dp at text scale 2 must not overflow; lists are non-lazy columns; the repo formats Dart at `dart format -l 100` (format only files you touch).
- Run the full suite of the package you touched before each commit: `cd backend && .venv/bin/pytest && .venv/bin/ruff check .`; `cd mobile/packages/petitgombo_core && flutter test && flutter analyze`; same for `mobile/apps/jobber`.

## Review Focus

- Adding, replacing and resending must not let a jobber spam a third party's phone with WhatsApp messages (staff send each one, so the day cap also protects staff time). (Task 2)
- A contact's phone typed as `+225…`, `00225…` or with spaces must still be refused when it is the jobber's own or the guarantor's. (Task 2)
- A jobber can never end up with no confirmed contact: the current one stays, and counts for J1, until its replacement has confirmed and the delay has passed; an abandoned replacement leaves it untouched; a replacement does not take a second slot. (Tasks 2, 4)
- A card added after J1 does not lower the tier; if staff deactivate every card, nobody is granted J1 by it. (Tasks 3, 4)
- Another jobber's contact id, a householder, staff or anonymous caller must not reach or see contacts or briefing progress; no response contains a phone, a code or `correct_index`. (Task 5)
- A jobber who asks for a code again while staff have not sent the first one must not queue duplicates; a code staff sent but nobody used must not stay valid for ever. (Task 2)
- Wrong codes lock the contact after `TRUSTED_CONTACT_CODE_MAX_ATTEMPTS`; an expired code is refused; only a new code unlocks. (Task 2)
- Existing 3a tests and mobile fixtures assume a two-step J1 and a hard-coded "sur 2"; they must be updated, not skipped. (Tasks 4, 8, 11)

---

## Backend

### Task 1: Settings, models, migrations

**Files:**
- Modify: `backend/config/settings.py` (settings above; beat entry `apply-contact-replacements` every 3600 s, task `apps.verification.tasks.apply_contact_replacements`)
- Modify: `backend/apps/verification/models.py`
- Create: `backend/apps/verification/migrations/0005_trusted_contacts_briefing.py` (schema), `0006_briefing_seed_and_group.py` (placeholder cards and group `briefing_manager`, pattern of `apps/listings/migrations/0002_seed_catalogue_and_groups.py`)
- Test: `backend/tests/test_trusted_contact_models.py`

**Interfaces:**
- Produces: `TrustedContact` (uuid pk, `user` FK CASCADE, `name` and `phone` TextField encrypted, `phone_hash` CharField 64 indexed, `relationship` choices `parent`/`relative`/`friend`/`other`, `status` choices `ContactStatus` = `pending`/`confirmed`/`replaced`, `replaces` (FK to self, null, PROTECT: the contact this one takes over from), `code_hash` CharField 64 blank, `code_requested_at` (DateTime, set when the contact is added and each time the jobber asks for a code), `code_sent_at` (null), `code_sent_by` (FK user, null, PROTECT), `code_expires_at` (DateTime null), `old_notified_at` (DateTime null) and `old_notified_by` (FK user, null, PROTECT) (used on the contact being replaced), `code_attempts` PositiveSmallInt default 0, `confirmed_at`, `replaced_at` (DateTime null), `created_at`). Constraint `one_live_contact_per_phone`: unique `(user, phone_hash)` where status is not `replaced`. There is no delete and no removed state.
- `BriefingCard` (uuid pk, `title` 80, `body` Text, `question` Text, `choices` JSON list of 2 to 4 non-empty strings, `correct_index` PositiveSmallInt, `explanation` Text, `position` PositiveSmallInt, `active` Bool default True; ordering `position`, `title`; `clean()` enforces the choices and index rules).
- `BriefingCompletion` (`user`, `card` PROTECT, `answered_at`; unique `(user, card)`; only correct answers are stored). `BriefingPass` (`user` OneToOne CASCADE, `completed_at`): kept so a later card does not undo J1.
- Model permission `send_contact_code` on `TrustedContact` (Meta); the `verification_agent` group gets it and `view_trustedcontact` in migration 0006 (same pattern as `0004_guarantor_permissions.py`). Group `briefing_manager` holds add/change/delete/view on `BriefingCard`. Three placeholder cards (tu, safety basics: tell your trusted contact the address and time; stay in the app, never pay or chat outside; you may leave and tell the team if you feel unsafe), marked as placeholders in the README (Task 10).

- [ ] **Step 1: Write failing tests**: `test_one_live_contact_per_phone` (a second live row with the same user and hash raises `IntegrityError`; a replaced one does not block), `test_card_choices_and_correct_index_are_validated` (`clean()` raises for one choice, five choices, a blank choice, index out of range), `test_completion_unique_per_user_and_card`, `test_seeded_cards_and_group_exist` (3 active cards; group has the four permissions), `test_verification_agent_group_can_send_contact_codes`.
- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_trusted_contact_models.py -v`. Expected: FAIL (models missing).
- [ ] **Step 3: Implement** settings, models and both migrations; generate 0005 with `makemigrations verification -n trusted_contacts_briefing`; check `makemigrations --check` is clean.
- [ ] **Step 4: Run** the new tests, then the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): trusted contact and briefing models`.

### Task 2: Trusted contact service

**Files:**
- Create: `backend/apps/verification/services/contacts.py`
- Modify: `backend/apps/accounts/api/errors.py`, `backend/apps/verification/tasks.py`
- Test: `backend/tests/test_trusted_contacts.py`

**Interfaces:**
- Produces, jobber side (all raise `VerificationError`; the user must be an active jobber, else `forbidden`; a contact id that is not the caller's is `forbidden`):
  `add_contact(user, *, name: str, phone: str, relationship: str) -> TrustedContact` (pending, `code_requested_at = now`, no code yet);
  `replace_contact(user, contact_id, *, name: str, phone: str, relationship: str) -> TrustedContact` (a new pending contact with the same rules);
  `request_code(user, contact_id) -> TrustedContact`;
  `confirm_contact(user, contact_id, code: str) -> TrustedContact`;
  `awaiting_code(contact) -> bool` (pending and `code_sent_at` is null or earlier than `code_requested_at`);
  `live_contacts(user)` (pending or confirmed). There is no function that deletes or retires a contact on its own.
- Produces, staff side (`staff` keyword; permission `verification.send_contact_code`, else `forbidden`; row locked with `select_for_update`; each leaves an audit row via `apps.audit.services.record`):
  `send_code(contact, *, staff) -> str`: pending only (`invalid_state`); creates a code, stores its hash, sets `code_sent_at`, `code_sent_by`, `code_expires_at`, resets attempts, returns the code once; audit `verification.contact.send_code`. The console builds the link with `whatsapp_link(decrypt_text(contact.phone), CONTACT_MESSAGE.format(code=code))`. `CONTACT_MESSAGE` = "petitGombo : quelqu'un vous a choisi comme personne de confiance. Si vous acceptez, donnez-lui ce code : {code}. Sinon, ignorez ce message. Notre équipe ne vous demandera jamais ce code."
  `record_notice(contact, *, staff) -> None`: for a confirmed contact whose replacement is confirmed and `old_notified_at` is null (`invalid_state` otherwise); sets `old_notified_at`, `old_notified_by`; audit `verification.contact.notice`. The console builds the link with `NOTICE_MESSAGE` = "petitGombo : vous serez remplacé(e) dans {n} h comme personne de confiance d'un mini-jobber. Si vous ne connaissez pas cette personne, répondez à ce message."
  `apply_replacements(user=None) -> int`; Celery task `apply_contact_replacements`.
- New codes (add to `STATUS` and `MESSAGES`, neutral French): `contact_name_required` 400 "Indiquez le nom de la personne de confiance."; `contact_phone_invalid` 400 "Numéro de la personne de confiance invalide."; `contact_phone_own` 400 "La personne de confiance doit avoir un autre numéro que le vôtre."; `contact_phone_guarantor` 400 "La personne de confiance doit être différente du garant."; `contact_phone_duplicate` 400 "Ce numéro est déjà dans la liste."; `contact_limit` 409 "Le nombre maximum de personnes de confiance est atteint."; `contact_code_wait` 429 "Le code a déjà été demandé. Patientez avant de le redemander."; `contact_code_invalid` 422 "Code incorrect."; `contact_code_expired` 422 "Ce code a expiré. Demandez-en un nouveau."; `contact_locked` 423 "Trop d'essais. Demandez un nouveau code." Reuse `rate_limited`, `invalid_state`, `forbidden`.
- Rules for `add_contact` and `replace_contact`: name stripped, required, capped at 120; relationship in `TrustedContact.Relationship`; phone normalised, not the jobber's own, not the phone of any non-refused `Guarantor` of the jobber (compare `keyed_hash`), not the phone of another live contact of this jobber; contacts created by the jobber in the last 24 h, replaced ones included, must be fewer than `TRUSTED_CONTACT_MAX_ADDS_PER_DAY` (`rate_limited`). Stored encrypted; nothing is sent.
- Cap: the live contacts that are not the `replaces` target of another live contact must be fewer than `TRUSTED_CONTACTS_MAX` for `add_contact` (`contact_limit`); a replacement takes the slot of the contact it replaces.
- `replace_contact`: the target must be live (`pending` or `confirmed`), else `invalid_state`. A `confirmed` target must have no live contact replacing it (`invalid_state`: replace that one instead); it stays confirmed and the new row has `replaces = target`. A `pending` target becomes `replaced` at once (`replaced_at` set) and the new row inherits its `replaces`, so a mistyped number can be changed without touching the confirmed contact behind it.
- `request_code`: pending only (`invalid_state`). Refused with `contact_code_wait` while `awaiting_code` (staff have not answered the last request) and within `TRUSTED_CONTACT_RESEND_SECONDS` of `code_sent_at`. Otherwise sets `code_requested_at = now`.
- `confirm_contact`: pending only; locked rows; no code sent yet is `contact_code_expired`; attempts at the maximum is `contact_locked`; expired is `contact_code_expired`; a wrong code adds an attempt and is `contact_code_invalid`; success sets `confirmed`, `confirmed_at`, clears the code hash.
- `apply_replacements`: a confirmed contact whose replacement is `confirmed` and whose `old_notified_at` is older than `TRUSTED_CONTACT_CHANGE_DELAY_HOURS` becomes `replaced`. Without a notice the old contact stays for ever (the safe default). Until then both count.

- [ ] **Step 1: Write failing tests** (the mock only builds links, so nothing to clear): `test_add_stores_encrypted_and_sends_nothing` (raw columns hold neither name nor phone; no code hash; `awaiting_code` true), `test_add_refuses_own_and_guarantor_phone_in_any_format` (parametrized `+225…`, `00225 …`, spaced; same for `replace_contact`), `test_invalid_phone_name_and_relationship_each_have_their_code`, `test_duplicate_phone_refused`, `test_cap_counts_pending_but_a_replacement_takes_no_extra_slot`, `test_adds_per_day_cap_counts_replaced_contacts`, `test_send_code_needs_the_permission_stores_only_the_hash_and_audits`, `test_send_code_twice_replaces_the_first_code`, `test_confirm_with_the_code_staff_sent`, `test_confirm_before_any_code_was_sent_is_refused`, `test_wrong_code_counts_attempts_then_locks_until_a_new_code`, `test_expired_code_refused`, `test_request_code_waits_while_staff_have_not_sent_and_then_for_the_delay`, `test_replacing_a_pending_contact_is_immediate_and_keeps_the_confirmed_one`, `test_replacing_a_confirmed_contact_keeps_it_until_the_new_one_confirms_is_noticed_and_the_delay_passes`, `test_record_notice_only_for_a_confirmed_contact_with_a_confirmed_replacement_and_audits`, `test_no_notice_means_the_old_contact_stays`, `test_confirmed_contact_with_a_live_replacement_cannot_be_replaced_again`, `test_no_service_removes_a_contact` (the module has no delete/remove function), `test_other_jobbers_contact_is_forbidden`, `test_householder_and_inactive_user_forbidden`, `test_apply_contact_replacements_task_sweeps_overdue`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Reuse `submissions._require_jobber`; hash codes like `enrolment._hash_code`; locking like `review._locked`.
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): trusted contacts confirmed by a code staff send on WhatsApp`.

### Task 3: Briefing service

**Files:**
- Create: `backend/apps/verification/services/briefing.py`
- Modify: `backend/apps/accounts/api/errors.py`
- Test: `backend/tests/test_briefing.py`

**Interfaces:**
- Produces: `briefing_cards(user) -> list[dict]` (active cards in order, each `{id, title, body, question, choices, answered}`; never `correct_index` or `explanation`); `answer_card(user, card_id, choice: int) -> dict` returning `{"correct": bool, "explanation": str, "complete": bool}`; `sync_pass(user) -> bool` (creates the `BriefingPass` when there is at least one active card and all are answered correctly; idempotent); `briefing_progress(user) -> dict` `{status, reason: "", answered, total, new_cards}` where `status` is `confirmed` once a pass exists, else `in_progress` if any card was answered, else `not_started`; `total` counts active cards, `answered` the active cards the jobber answered, `new_cards` the active cards not answered (calls `sync_pass`).
- New codes: `card_invalid` 400 "Carte introuvable.", `choice_invalid` 400 "Choix invalide."; jobber only (`forbidden` otherwise).

- [ ] **Step 1: Write failing tests**: `test_cards_never_expose_the_answer`, `test_wrong_answer_returns_explanation_and_stores_nothing`, `test_correct_answer_is_stored_once`, `test_all_cards_correct_creates_the_pass`, `test_card_added_after_pass_keeps_confirmed_and_counts_as_new`, `test_no_active_cards_never_confirms`, `test_deactivating_the_last_unanswered_card_completes_on_next_progress`, `test_inactive_card_and_bad_choice_refused`, `test_householder_forbidden`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): safety briefing service`.

### Task 4: Tier and checklist with four steps

**Files:**
- Modify: `backend/apps/verification/services/tiers.py`, `backend/config/settings.py` (default of `JOBBER_REQUIRED_STEPS`)
- Test: extend `backend/tests/test_jobber_tier.py`; update every 3a test that builds a J1 jobber with two steps (`test_jobber_verification_api.py`, `test_guarantor_*` where they assert the tier)

**Interfaces:**
- Produces: `jobber_tier` knows `trusted_contact` (at least one `confirmed` contact; a confirmed contact being replaced still counts until it is `replaced`) and `briefing` (a `BriefingPass` exists). `jobber_checklist(user)` gains `trusted_contact` `{status, reason: "", confirmed, pending}` (`confirmed` if at least one confirmed contact; `in_progress` if only pending ones; else `not_started`) and `briefing` (from `briefing_progress`). Before building it, call `contacts.apply_replacements(user)`. A step name the version does not know still never grants J1.

- [ ] **Step 1: Write failing tests**: `test_j1_needs_all_four_steps`, `test_replacing_a_contact_never_drops_the_tier` (old one counts while the replacement is pending and during the delay; after the sweep the new one counts), `test_new_card_after_j1_keeps_j1`, `test_checklist_has_the_new_steps_without_phones_codes_or_answers`, `test_required_setting_can_drop_the_new_steps`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement**; set the new default and fix the older tests so they confirm the two new steps (small helper in `tests/helpers.py`: `confirm_contact_and_briefing(user)`).
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): jobber tier needs contact and briefing`.

### Task 5: Jobber API for contacts and briefing

**Files:**
- Modify: `backend/apps/verification/api/jobber_views.py`, `jobber_urls.py`, `serializers.py`
- Test: `backend/tests/test_jobber_contacts_briefing_api.py`

**Interfaces:**
- Produces (all `IsJobber`, JSON, errors via `error_response`):
  `GET /api/v1/jobber/verification/contacts` → `{"max": int, "contacts": [{id, name, relationship, status, replaces, awaiting_code, ends_at}]}` (live contacts only; `awaiting_code` as in the service; `replaces` is the id of the contact a pending or new one takes over from, or null; `ends_at` is set on a confirmed contact whose replacement has confirmed, as that replacement's `confirmed_at` + delay, else null);
  `POST …/contacts` `{name, phone, relationship}` → 201 one contact;
  `POST …/contacts/<uuid>/code` → 200 contact (asks staff for a code, `request_code`);
  `POST …/contacts/<uuid>/confirm` `{code}` → 200 contact;
  `POST …/contacts/<uuid>/replace` `{name, phone, relationship}` → 201 the new contact. There is no DELETE: the route answers 405.
  `GET …/briefing` → `{"progress": {...}, "cards": [...]}`;
  `POST …/briefing/<uuid:card_id>/answer` `{choice}` → 200 `{correct, explanation, complete}`.
  The checklist `GET /api/v1/jobber/verification` carries the new steps (Task 4).

- [ ] **Step 1: Write failing tests** (`enrol_device(phone=..., role="jobber")`, `bearer_for`): `test_contact_roundtrip_add_staff_sends_confirm_replace_confirm_list` (the code comes from `contacts.send_code` called as staff in the test), `test_delete_is_not_allowed` (405 on the contact route), `test_householder_staff_anonymous_get_403_or_401_on_every_new_endpoint`, `test_one_jobber_cannot_see_or_touch_anothers_contact` (404 `forbidden`), `test_no_response_contains_a_phone_a_code_or_correct_index` (scan JSON text for the submitted phone digits, the code `send_code` returned and `correct_index`), `test_error_codes_map_to_status_and_message` (one per new code), `test_briefing_flow_to_complete_then_checklist_confirmed`, `test_wrong_answer_is_200_with_correct_false`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** thin views over `contacts.*` and `briefing.*`, with drf-spectacular `extend_schema`.
- [ ] **Step 4: Run** the full backend suite, ruff and `manage.py spectacular --validate` (exit 0; the listings warnings already exist). Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): jobber contacts and briefing API`.

### Task 6: Console: trusted contacts to send

**Files:**
- Modify: `backend/apps/verification/admin.py`
- Create: `backend/apps/verification/templates/admin/verification/trustedcontact_review.html`, `backend/apps/verification/templates/console/contact_send.html` (pattern of `apps/accounts/templates/console/enrolment_send.html`)
- Test: `backend/tests/test_trusted_contact_console.py`

**Interfaces:**
- Produces: `TrustedContactAdmin` ("Personnes de confiance"), no add or delete, default queue "À envoyer" (pending and `awaiting_code`), other queues "À prévenir" (confirmed contact whose confirmed replacement has `old_notified_at` null) and "Tous"; routes `verification_trustedcontact_send` and `verification_trustedcontact_notice` (POST, like `AddressProofAdmin.get_urls` and `accounts/console_views.py`). The review page shows the contact's name, relationship and the jobber's confirmed identity name, and what to do ("Envoyer le code par WhatsApp" / "Prévenir l'ancienne personne"); the phone appears only inside the link, never as text and never in the list. The send result page shows `Ouvrir WhatsApp` once with the link (`Cache-Control: no-store`) and the warning "Ne recopiez pas ce code : il sera demandé au mini-jobber." Opening the review page audits `verification.contact.view`; the actions audit through the service.

- [ ] **Step 1: Write failing tests**: `test_agent_sees_the_send_queue_first`, `test_send_shows_the_link_once_with_the_code_and_the_contact_number_and_audits`, `test_second_send_issues_a_new_code_and_the_old_one_stops_working`, `test_review_page_audits_the_view_and_shows_no_phone_as_text`, `test_notice_queue_marks_notified_and_audits`, `test_list_page_shows_no_encrypted_columns`, `test_agent_without_the_permission_gets_403`, `test_pages_are_no_store`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(console): trusted contacts to send`.

### Task 7: Console: briefing cards

**Files:**
- Modify: `backend/apps/verification/admin.py`
- Test: `backend/tests/test_briefing_console.py`

**Interfaces:**
- Produces: `BriefingCardAdmin` ("Cartes de briefing"): list `title`, `position`, `active` (the last two editable in the list); a form with `choices` as a textarea, one per line, and `correct_index` entered as "Bonne réponse (numéro de la ligne, à partir de 1)" stored 0-based; the model's `clean()` errors shown in French. Rights come from the `briefing_manager` group; a `verification_agent` without it gets 403.

- [ ] **Step 1: Write failing tests**: `test_manager_creates_a_card_from_lines_and_a_number`, `test_invalid_card_shows_french_errors` (one choice; number out of range), `test_toggle_active_and_position_in_the_list`, `test_verification_agent_without_group_gets_403`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** following `CategoryForm` and `OfferCategoryAdmin` in `apps/listings/admin.py`.
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(console): briefing cards`.

## Mobile

### Task 8: Core models, API and controllers

**Files:**
- Modify: `mobile/packages/petitgombo_core/lib/src/verification/verification_models.dart`, `verification_api.dart`
- Create: `lib/src/verification/contacts_controller.dart`, `lib/src/verification/briefing_controller.dart`
- Modify: `lib/petitgombo_core.dart` (exports)
- Test: `test/jobber_models_test.dart`, `test/contacts_controller_test.dart`, `test/briefing_controller_test.dart`; extend `test/support/verification_fixtures.dart` (`jobberChecklistJson` gains `contact`, `briefing`, `required` with the four-step default)

**Interfaces:**
- Produces: `StepStatus.inProgress` (`parse('in_progress')`); `VerificationChecklist` gains `List<String> required` (default `['identity','guarantor']` when absent), `ContactStep trustedContact` and `BriefingStep briefing` (defaults not started when absent); `ContactStep(status, confirmed, pending)`, `BriefingStep(status, answered, total, newCards)`, both `extends VerificationStep`. `TrustedContact {id, name, relationship, status, replaces, awaitingCode, endsAt}`, `BriefingCard {id, title, body, question, choices, answered}`, `BriefingAnswer {correct, explanation, complete}`.
- `VerificationApi` gains `contacts(access)`, `addContact(access, {name, phone, relationship})`, `requestContactCode(access, id)`, `confirmContact(access, id, code)`, `replaceContact(access, id, {name, phone, relationship})`, `briefing(access)`, `answerCard(access, cardId, choice)`; the phone is sent normalised with `normaliseIvorianPhone`.
- `ContactsController` (`StateNotifier<ContactsState{contacts, max, loading, sending, error}>`; `load()`, `add(...)` returning the new `TrustedContact?` or null with `VerificationCopy.contactPhoneInvalid` when the phone does not normalise, `replace(id, ...)` returning the new `TrustedContact?` (same phone check as `add`), `requestCode(id)`, `confirm(id, code)` returning `bool`) and `BriefingController` (`BriefingState{cards, progress, loading, sending, error}`; `load()`, `answer(cardId, choice)` returning `BriefingAnswer?`). Both refresh `verificationControllerProvider` after a change that can move the checklist; both map server codes to French like `_message` in `verification_controller.dart`.

- [ ] **Step 1: Write failing tests**: `checklist parses the four jobber steps and required`, `older checklist without the new keys still parses`, `contacts api posts the normalised phone`, `controller add refuses an invalid phone without a request`, `controller confirm success refreshes the checklist`, `controller maps contact_code_invalid and contact_locked to French`, `briefing controller loads cards and reports a wrong answer`, `briefing answer completes and refreshes the checklist`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the package suite and analyzer. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): contacts and briefing models, API and controllers`.

### Task 9: Trusted contact flow

**Files:**
- Create: `lib/src/verification/screens/trusted_contact_flow.dart`
- Modify: `verification_copy.dart` (strings, tu)
- Test: `test/trusted_contact_flow_test.dart`

**Interfaces:**
- Produces: `TrustedContactFlow()`: a list of the jobber's contacts (name, relationship, status in words: "En attente d'envoi du code" (awaiting) / "Code envoyé, à saisir" (pending) / "Confirmé" / "Remplacé le {date}" on the old one once its replacement has confirmed), an "Ajouter une personne" button (hidden at `max`), per-contact actions (Demander un nouveau code for a pending one; Changer for any, which opens the same add form and code screens, with a note for a confirmed one: "Ta personne actuelle reste en place jusqu'à ce que la nouvelle ait confirmé, puis encore {n} h. Notre équipe la préviendra par WhatsApp."). There is no Retirer button anywhere. Add form (keys `contact-name`, `contact-phone`, relationship choice cards parent / famille / ami(e) / autre) then the code screen (key `contact-code`, 6 digits, "Notre équipe envoie un code par WhatsApp à cette personne, en général sous {review_hours} h. Demande-le-lui, puis saisis-le ici."). `PrivacyNote` on the add form: "Notre équipe envoie un message WhatsApp à cette personne, une seule fois, pour qu'elle confirme. On n'utilise son numéro que pour ça." Validation errors under the fields; "Étape x sur 2" on add and code.

- [ ] **Step 1: Write failing tests** (helpers as in `guarantor_flow_test.dart`): `empty list offers to add a person and shows the privacy note`, `invalid name and phone show errors and send nothing`, `a full run adds then confirms with the code and returns to the list showing Confirmé`, `a wrong code shows its message and keeps the field`, `Changer on a confirmed contact states that it stays until the new one confirms, then after the delay, and a full run shows both until the swap`, `there is no remove action`, `the add button disappears at the maximum`, `does not overflow at 320dp and text scale 2`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** following `guarantor_flow.dart` (`PopScope`, `FlowScaffold`, in-memory state).
- [ ] **Step 4: Run** the package suite and analyzer. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): trusted contact flow`.

### Task 10: Safety briefing flow

**Files:**
- Create: `lib/src/verification/screens/briefing_flow.dart`
- Modify: `verification_copy.dart`
- Test: `test/briefing_flow_test.dart`

**Interfaces:**
- Produces: `BriefingFlow()`: one card per screen ("Carte x sur y" using `FlowScaffold` progress), title, body, the question, choice cards; after an answer, a correct one shows "Bien vu." and `Continuer`; a wrong one shows the explanation and `Réessayer` (same card). Cards already answered are skipped; after the last one a "Briefing terminé" screen and pop. With no active cards it shows an empty state ("Rien à lire pour le moment.").

- [ ] **Step 1: Write failing tests**: `shows the first unanswered card with progress`, `a wrong answer shows the explanation and Réessayer on the same card`, `a correct answer moves on and the last one shows the end screen`, `answered cards are skipped`, `no cards shows the empty state`, `does not overflow at 320dp and text scale 2`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the package suite and analyzer. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): safety briefing flow`.

### Task 11: Checklist, card, badges, docs

**Files:**
- Modify: `screens/checklist_screen.dart` (two new `_StepCard`s for a jobber: "Personne de confiance" and "Consignes de sécurité", with `Commencer`/`Continuer`/`Modifier`; a new card in a passed briefing shows "Nouvelle carte à lire"), `screens/verification_card.dart` (progress "n étape(s) sur `required.length`", done = confirmed required steps), `profile/profile_screen.dart` (badges `Personne de confiance confirmée`, `Consignes de sécurité vues`), `info/info_screens.dart` (privacy section "Informations sur votre personne de confiance"), `docs/threat-model.md`, `README.md`
- Test: extend `test/jobber_checklist_test.dart`, `test/offers_screens_test.dart`, `test/shell_profile_test.dart`

**Interfaces:**
- Produces: nothing new for other tasks. Threat-model rows: WhatsApp spam to a third party's number, guessing the confirmation code, a trusted contact who is the jobber's guarantor or the jobber, swapping contacts to evade the check (replacement only, with the same WhatsApp confirmation, a delay and a notice to the old number), insider read of contact data (staff see the name and, only inside the one-time WhatsApp link, the number; each view and send is audited; the code is shown once). README: update "Jobber verification" (four steps, settings, the briefing cards in the console, **the three seeded cards are placeholders to replace**, open decisions: lawful basis for a trusted contact's number, who sends the WhatsApp messages and from which number (`OFFICIAL_WHATSAPP_NUMBER`) and the staff workload of sending each code, how a contact who says "I did not agree" gets off the list, since a contact can be replaced by the jobber but never removed, whether the briefing needs videos).

- [ ] **Step 1: Write failing tests**: `jobber checklist shows four steps`, `briefing step shows Nouvelle carte à lire after J1`, `card progress uses the required steps` ("2 étapes sur 4"), `jobber profile shows only earned badges including the two new ones`, `privacy notice has a section about the trusted contact`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** and update the docs; fix the older fixtures and "sur 2" assertions.
- [ ] **Step 4: Run** all suites (backend, core, jobber, householder, staff) and analyzers; build the jobber debug APK (`flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8000`) and try the flow by hand if a phone is unlocked; say plainly if it was not run. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): contact and briefing steps in the jobber checklist`.
