# Jobber Verification 3b (trusted contact and safety briefing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A jobber names up to two trusted contacts who confirm by an SMS code, answers a staff-edited safety briefing, and reaches tier J1 only when identity, guarantor, trusted contact and briefing are all done.

**Architecture:** Same layering as 3a: services in `apps/verification/services/` hold every rule, views only translate HTTP, the tier is computed from `JOBBER_REQUIRED_STEPS`. No staff review for these two steps: the contact confirms with a code sent through `registry.get_messaging().send_sms` (mock in dev), the briefing is answered in the app. In the app, the checklist gains two steps, each with its own small controller and flow screens.

**Tech Stack:** Django 5.2 + DRF, pytest, Celery beat; Flutter 3.24.2, Riverpod, Dio.

**Spec:** `docs/superpowers/specs/2026-11-13-jobber-verification-design.md` (section "Plan 3b"). Builds on `docs/superpowers/plans/2026-11-13-jobber-verification-3a.md`.

## Global Constraints

- User-facing copy French: jobber "tu"; console "vous". API error messages stay neutral, like the 3a ones. Code and comments English.
- No new packages. Never commit secrets. Do not push unless asked.
- The jobber API returns statuses and the jobber's own labels only: never a contact's or guarantor's phone, a code or its hash, a briefing answer key (`correct_index`), or any identity field.
- Encrypt with `encrypt_text`; compare numbers with `keyed_hash(normalise_number(...))`; normalise phones with `apps.accounts.phones.normalise` (raises `InvalidPhone`). Codes are 6 digits from `secrets`, stored as the HMAC used by `enrolment._hash_code` (key `SECRET_KEY`, message `"{pk}:{code}"`), compared with `hmac.compare_digest`.
- New settings, env-overridable in `config/settings.py` beside `JOBBER_REQUIRED_STEPS`: `TRUSTED_CONTACTS_MAX` = 2; `TRUSTED_CONTACT_CODE_TTL_MINUTES` = 60; `TRUSTED_CONTACT_CODE_MAX_ATTEMPTS` = 5; `TRUSTED_CONTACT_RESEND_SECONDS` = 60; `TRUSTED_CONTACT_MAX_ADDS_PER_DAY` = 3; `TRUSTED_CONTACT_CHANGE_DELAY_HOURS` = 72. `JOBBER_REQUIRED_STEPS` default becomes `identity, guarantor, trusted_contact, briefing`.
- New step statuses in the checklist: `not_started`, `in_progress`, `confirmed` (these two steps have no staff review, so no `submitted`/`in_review`/`refused`).
- Mobile: 320dp at text scale 2 must not overflow; lists are non-lazy columns; the repo formats Dart at `dart format -l 100` (format only files you touch).
- Run the full suite of the package you touched before each commit: `cd backend && .venv/bin/pytest && .venv/bin/ruff check .`; `cd mobile/packages/petitgombo_core && flutter test && flutter analyze`; same for `mobile/apps/jobber`.

## Review Focus

- Removing and re-adding the same third-party number, or resending, must not let a jobber spam that phone with SMS. (Task 2)
- A contact's phone typed as `+225…`, `00225…` or with spaces must still be refused when it is the jobber's own or the guarantor's. (Task 2)
- A contact pending removal still counts toward the cap and toward J1 until the delay passes; then J1 drops to J0 and another contact can be added. (Tasks 2, 4)
- A card added after J1 does not lower the tier; if staff deactivate every card, nobody is granted J1 by it. (Tasks 3, 4)
- Another jobber's contact id, a householder, staff or anonymous caller must not reach or see contacts or briefing progress; no response contains a phone, a code or `correct_index`. (Task 5)
- Wrong codes lock the contact after `TRUSTED_CONTACT_CODE_MAX_ATTEMPTS`; an expired code is refused; only a new code unlocks. (Task 2)
- Existing 3a tests and mobile fixtures assume a two-step J1 and a hard-coded "sur 2"; they must be updated, not skipped. (Tasks 4, 7, 10)

---

## Backend

### Task 1: Settings, models, migrations

**Files:**
- Modify: `backend/config/settings.py` (settings above; beat entry `apply-contact-removals` every 3600 s, task `apps.verification.tasks.apply_contact_removals`)
- Modify: `backend/apps/verification/models.py`
- Create: `backend/apps/verification/migrations/0005_trusted_contacts_briefing.py` (schema), `0006_briefing_seed_and_group.py` (placeholder cards and group `briefing_manager`, pattern of `apps/listings/migrations/0002_seed_catalogue_and_groups.py`)
- Test: `backend/tests/test_trusted_contact_models.py`

**Interfaces:**
- Produces: `TrustedContact` (uuid pk, `user` FK CASCADE, `name` and `phone` TextField encrypted, `phone_hash` CharField 64 indexed, `relationship` choices `parent`/`relative`/`friend`/`other`, `status` choices `ContactStatus` = `pending`/`confirmed`/`removed`, `code_hash` CharField 64 blank, `code_sent_at`, `code_expires_at` (DateTime null), `code_attempts` PositiveSmallInt default 0, `confirmed_at`, `removal_requested_at`, `removed_at` (DateTime null), `created_at`). Constraint `one_live_contact_per_phone`: unique `(user, phone_hash)` where status is not `removed`.
- `BriefingCard` (uuid pk, `title` 80, `body` Text, `question` Text, `choices` JSON list of 2 to 4 non-empty strings, `correct_index` PositiveSmallInt, `explanation` Text, `position` PositiveSmallInt, `active` Bool default True; ordering `position`, `title`; `clean()` enforces the choices and index rules).
- `BriefingCompletion` (`user`, `card` PROTECT, `answered_at`; unique `(user, card)`; only correct answers are stored). `BriefingPass` (`user` OneToOne CASCADE, `completed_at`): kept so a later card does not undo J1.
- Group `briefing_manager` holds add/change/delete/view on `BriefingCard`. Three placeholder cards (tu, safety basics: tell your trusted contact the address and time; stay in the app, never pay or chat outside; you may leave and tell the team if you feel unsafe), marked as placeholders in the README (Task 10).

- [ ] **Step 1: Write failing tests**: `test_one_live_contact_per_phone` (a second live row with the same user and hash raises `IntegrityError`; a removed one does not block), `test_card_choices_and_correct_index_are_validated` (`clean()` raises for one choice, five choices, a blank choice, index out of range), `test_completion_unique_per_user_and_card`, `test_seeded_cards_and_group_exist` (3 active cards; group has the four permissions).
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
- Produces (all raise `VerificationError`; the user must be an active jobber, else `forbidden`; a contact id that is not the caller's is `forbidden`):
  `add_contact(user, *, name: str, phone: str, relationship: str) -> TrustedContact` (sends the code);
  `resend_code(user, contact_id) -> TrustedContact`;
  `confirm_contact(user, contact_id, code: str) -> TrustedContact`;
  `remove_contact(user, contact_id) -> TrustedContact`;
  `apply_removals(user=None) -> int`; Celery task `apply_contact_removals`; `live_contacts(user)` (status pending or confirmed).
- New codes (add to `STATUS` and `MESSAGES`, neutral French): `contact_name_required` 400 "Indiquez le nom de la personne de confiance."; `contact_phone_invalid` 400 "Numéro de la personne de confiance invalide."; `contact_phone_own` 400 "La personne de confiance doit avoir un autre numéro que le vôtre."; `contact_phone_guarantor` 400 "La personne de confiance doit être différente du garant."; `contact_phone_duplicate` 400 "Ce numéro est déjà dans la liste."; `contact_limit` 409 "Le nombre maximum de personnes de confiance est atteint."; `contact_code_wait` 429 "Attendez un peu avant de demander un nouveau code."; `contact_code_invalid` 422 "Code incorrect."; `contact_code_expired` 422 "Ce code a expiré. Demandez-en un nouveau."; `contact_locked` 423 "Trop d'essais. Demandez un nouveau code." Reuse `rate_limited` and `invalid_state`.
- Rules: name stripped, required, capped at 120; relationship in `TrustedContact.Relationship`; phone normalised, not the jobber's own, not the phone of any non-refused `Guarantor` of the jobber (compare `keyed_hash`), not already live for this jobber; live contacts (pending, confirmed, including those awaiting removal) must be fewer than `TRUSTED_CONTACTS_MAX` (`contact_limit`); contacts created by the jobber in the last 24 h, removed ones included, must be fewer than `TRUSTED_CONTACT_MAX_ADDS_PER_DAY` (`rate_limited`). The SMS text names no one: "petitGombo : quelqu'un vous a choisi comme personne de confiance. Si vous acceptez, donnez-lui ce code : {code}. Sinon, ignorez ce message."
- `resend_code`: pending only (`invalid_state`); refused within `TRUSTED_CONTACT_RESEND_SECONDS` of `code_sent_at` (`contact_code_wait`); new code, attempts reset.
- `confirm_contact`: pending only; locked rows (`select_for_update`); attempts at the maximum is `contact_locked`; expired is `contact_code_expired`; a wrong code adds an attempt and is `contact_code_invalid`; success sets `confirmed`, `confirmed_at`, clears the code hash.
- `remove_contact`: a pending contact becomes `removed` at once; a confirmed one gets `removal_requested_at = now` and an SMS notice to its own number ("petitGombo : vous allez être retiré(e) de la liste des personnes de confiance d'un mini-jobber dans {n} h."); asking twice is `invalid_state`. `apply_removals` marks `removed` the confirmed contacts whose `removal_requested_at` is older than `TRUSTED_CONTACT_CHANGE_DELAY_HOURS`.

- [ ] **Step 1: Write failing tests** (use `MockMessaging.outbox`; clear it per test): `test_add_stores_encrypted_and_sends_one_code` (raw columns hold neither name nor phone; outbox has one SMS to the contact), `test_add_refuses_own_and_guarantor_phone_in_any_format` (parametrized `+225…`, `00225 …`, spaced), `test_invalid_phone_name_and_relationship_each_have_their_code`, `test_duplicate_phone_refused`, `test_cap_counts_pending_and_removal_requested`, `test_adds_per_day_cap_counts_removed_contacts`, `test_confirm_with_right_code`, `test_wrong_code_counts_attempts_then_locks`, `test_expired_code_refused`, `test_resend_resets_attempts_and_respects_the_wait`, `test_remove_pending_is_immediate`, `test_remove_confirmed_waits_notifies_old_number_and_applies_after_delay`, `test_other_jobbers_contact_is_forbidden`, `test_householder_and_inactive_user_forbidden`, `test_apply_contact_removals_task_sweeps_overdue`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Reuse `submissions._require_jobber`; hash codes like `enrolment._hash_code`.
- [ ] **Step 4: Run** the full backend suite and ruff. Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): trusted contacts confirmed by SMS code`.

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
- Produces: `jobber_tier` knows `trusted_contact` (at least one `confirmed` contact, a removal still pending included) and `briefing` (a `BriefingPass` exists). `jobber_checklist(user)` gains `trusted_contact` `{status, reason: "", confirmed, pending}` (`confirmed` if at least one confirmed contact; `in_progress` if only pending ones; else `not_started`) and `briefing` (from `briefing_progress`). Before building it, call `contacts.apply_removals(user)`. A step name the version does not know still never grants J1.

- [ ] **Step 1: Write failing tests**: `test_j1_needs_all_four_steps`, `test_confirmed_contact_pending_removal_still_counts_then_drops_to_j0`, `test_new_card_after_j1_keeps_j1`, `test_checklist_has_the_new_steps_without_phones_codes_or_answers`, `test_required_setting_can_drop_the_new_steps`.
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
  `GET /api/v1/jobber/verification/contacts` → `{"max": int, "contacts": [{id, name, relationship, status, removal_at}]}` (live contacts only; `removal_at` = `removal_requested_at` + delay, or null);
  `POST …/contacts` `{name, phone, relationship}` → 201 one contact;
  `POST …/contacts/<uuid>/code` → 200 contact (resend);
  `POST …/contacts/<uuid>/confirm` `{code}` → 200 contact;
  `DELETE …/contacts/<uuid>` → 200 contact;
  `GET …/briefing` → `{"progress": {...}, "cards": [...]}`;
  `POST …/briefing/<uuid:card_id>/answer` `{choice}` → 200 `{correct, explanation, complete}`.
  The checklist `GET /api/v1/jobber/verification` carries the new steps (Task 4).

- [ ] **Step 1: Write failing tests** (`enrol_device(phone=..., role="jobber")`, `bearer_for`): `test_contact_roundtrip_add_confirm_list_remove`, `test_householder_staff_anonymous_get_403_or_401_on_every_new_endpoint`, `test_one_jobber_cannot_see_or_touch_anothers_contact` (404 `forbidden`), `test_no_response_contains_a_phone_a_code_or_correct_index` (scan JSON text for the submitted phone digits, the SMS code and `correct_index`), `test_error_codes_map_to_status_and_message` (one per new code), `test_briefing_flow_to_complete_then_checklist_confirmed`, `test_wrong_answer_is_200_with_correct_false`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** thin views over `contacts.*` and `briefing.*`, with drf-spectacular `extend_schema`.
- [ ] **Step 4: Run** the full backend suite, ruff and `manage.py spectacular --validate` (exit 0; the listings warnings already exist). Expected: PASS.
- [ ] **Step 5: Commit** `feat(verification): jobber contacts and briefing API`.

### Task 6: Console: briefing cards

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

### Task 7: Core models, API and controllers

**Files:**
- Modify: `mobile/packages/petitgombo_core/lib/src/verification/verification_models.dart`, `verification_api.dart`
- Create: `lib/src/verification/contacts_controller.dart`, `lib/src/verification/briefing_controller.dart`
- Modify: `lib/petitgombo_core.dart` (exports)
- Test: `test/jobber_models_test.dart`, `test/contacts_controller_test.dart`, `test/briefing_controller_test.dart`; extend `test/support/verification_fixtures.dart` (`jobberChecklistJson` gains `contact`, `briefing`, `required` with the four-step default)

**Interfaces:**
- Produces: `StepStatus.inProgress` (`parse('in_progress')`); `VerificationChecklist` gains `List<String> required` (default `['identity','guarantor']` when absent), `ContactStep trustedContact` and `BriefingStep briefing` (defaults not started when absent); `ContactStep(status, confirmed, pending)`, `BriefingStep(status, answered, total, newCards)`, both `extends VerificationStep`. `TrustedContact {id, name, relationship, status, removalAt}`, `BriefingCard {id, title, body, question, choices, answered}`, `BriefingAnswer {correct, explanation, complete}`.
- `VerificationApi` gains `contacts(access)`, `addContact(access, {name, phone, relationship})`, `resendContactCode(access, id)`, `confirmContact(access, id, code)`, `removeContact(access, id)`, `briefing(access)`, `answerCard(access, cardId, choice)`; the phone is sent normalised with `normaliseIvorianPhone`.
- `ContactsController` (`StateNotifier<ContactsState{contacts, max, loading, sending, error}>`; `load()`, `add(...)` returning the new `TrustedContact?` or null with `VerificationCopy.contactPhoneInvalid` when the phone does not normalise, `resend(id)`, `confirm(id, code)` returning `bool`, `remove(id)`) and `BriefingController` (`BriefingState{cards, progress, loading, sending, error}`; `load()`, `answer(cardId, choice)` returning `BriefingAnswer?`). Both refresh `verificationControllerProvider` after a change that can move the checklist; both map server codes to French like `_message` in `verification_controller.dart`.

- [ ] **Step 1: Write failing tests**: `checklist parses the four jobber steps and required`, `older checklist without the new keys still parses`, `contacts api posts the normalised phone`, `controller add refuses an invalid phone without a request`, `controller confirm success refreshes the checklist`, `controller maps contact_code_invalid and contact_locked to French`, `briefing controller loads cards and reports a wrong answer`, `briefing answer completes and refreshes the checklist`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the package suite and analyzer. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): contacts and briefing models, API and controllers`.

### Task 8: Trusted contact flow

**Files:**
- Create: `lib/src/verification/screens/trusted_contact_flow.dart`
- Modify: `verification_copy.dart` (strings, tu)
- Test: `test/trusted_contact_flow_test.dart`

**Interfaces:**
- Produces: `TrustedContactFlow()`: a list of the jobber's contacts (name, relationship, status in words: "À confirmer" / "Confirmé" / "Retrait le {date}"), an "Ajouter une personne" button (hidden at `max`), per-contact actions (Renvoyer le code, Retirer, with a confirmation for a confirmed one that says the removal takes effect after `n` h and the person is warned by SMS). Add form (keys `contact-name`, `contact-phone`, relationship choice cards parent / famille / ami(e) / autre) then the code screen (key `contact-code`, 6 digits, "Demande à ta personne de confiance de te lire le code reçu par SMS."). `PrivacyNote` on the add form: "On envoie un SMS à cette personne, une seule fois, pour qu'elle confirme. On n'utilise son numéro que pour ça." Validation errors under the fields; "Étape x sur 2" on add and code.

- [ ] **Step 1: Write failing tests** (helpers as in `guarantor_flow_test.dart`): `empty list offers to add a person and shows the privacy note`, `invalid name and phone show errors and send nothing`, `a full run adds then confirms with the code and returns to the list showing Confirmé`, `a wrong code shows its message and keeps the field`, `remove asks first and a confirmed removal states the delay`, `the add button disappears at the maximum`, `does not overflow at 320dp and text scale 2`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** following `guarantor_flow.dart` (`PopScope`, `FlowScaffold`, in-memory state).
- [ ] **Step 4: Run** the package suite and analyzer. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): trusted contact flow`.

### Task 9: Safety briefing flow

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

### Task 10: Checklist, card, badges, docs

**Files:**
- Modify: `screens/checklist_screen.dart` (two new `_StepCard`s for a jobber: "Personne de confiance" and "Consignes de sécurité", with `Commencer`/`Continuer`/`Modifier`; a new card in a passed briefing shows "Nouvelle carte à lire"), `screens/verification_card.dart` (progress "n étape(s) sur `required.length`", done = confirmed required steps), `profile/profile_screen.dart` (badges `Personne de confiance confirmée`, `Consignes de sécurité vues`), `info/info_screens.dart` (privacy section "Informations sur votre personne de confiance"), `docs/threat-model.md`, `README.md`
- Test: extend `test/jobber_checklist_test.dart`, `test/offers_screens_test.dart`, `test/shell_profile_test.dart`

**Interfaces:**
- Produces: nothing new for other tasks. Threat-model rows: SMS pumping of a third party's phone, guessing the confirmation code, a trusted contact who is the jobber's guarantor or the jobber, insider read of contact data (not shown to staff at all; no console view). README: update "Jobber verification" (four steps, settings, the briefing cards in the console, **the three seeded cards are placeholders to replace**, open decisions: lawful basis for a trusted contact's number, what staff do when a contact reports "I did not agree", whether the briefing needs videos).

- [ ] **Step 1: Write failing tests**: `jobber checklist shows four steps`, `briefing step shows Nouvelle carte à lire after J1`, `card progress uses the required steps` ("2 étapes sur 4"), `jobber profile shows only earned badges including the two new ones`, `privacy notice has a section about the trusted contact`.
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement** and update the docs; fix the older fixtures and "sur 2" assertions.
- [ ] **Step 4: Run** all suites (backend, core, jobber, householder, staff) and analyzers; build the jobber debug APK (`flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8000`) and try the flow by hand if a phone is unlocked; say plainly if it was not run. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mobile): contact and briefing steps in the jobber checklist`.
