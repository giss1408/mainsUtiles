# Foundation and Device Enrolment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A running petitGombo backend and three Flutter apps (householder, jobber, staff) in which a user can apply to enrol a device, staff approve the application in the staff app or the web console and send a confirmation number by WhatsApp, and the enrolled device can sign in with its own key.

**Architecture:** A Django modular monolith (`backend/`) exposing a versioned REST API and the staff console through Django admin. Three thin Flutter apps (`mobile/apps/jobber`, `mobile/apps/householder`, `mobile/apps/staff`) share one package (`mobile/packages/petitgombo_core`) that holds the API client, device identity and enrolment screens. External services sit behind provider interfaces with mocks.

**Tech Stack:** Python 3.13, Django 5.2, Django REST Framework, drf-spectacular, PostgreSQL 16 (PostGIS image), Redis 7, Celery, PyJWT, cryptography, phonenumbers, pytest. Flutter 3.24 / Dart 3.5, flutter_riverpod, go_router, dio, flutter_secure_storage, cryptography.

**Spec:** `skill.md` (repository root). This plan covers build-order steps 1 and 2 only.

## Global Constraints

- Use `python3.13` for the virtualenv (`python3` on this machine is 3.15, which Django 5.2 does not support).
- PostgreSQL and Redis run from `docker-compose.yml`; nothing is installed on the host.
- Use the plain `django.db.backends.postgresql` engine in this plan. GeoDjango (which needs GDAL on the host) is switched on in the listings plan.
- All user-facing copy is French; code, comments and logs are English.
- Every limit, delay and threshold is a Django setting read from the environment with the default given in this plan. No hard-coded values in services.
- No secrets in source. `.env` is git-ignored; `.env.example` lists every variable.
- Never log or store in plain text: confirmation numbers, tokens, private keys. Store only hashes.
- Staff actions on enrolment write an `AdminAction` row.
- Business rules live in backend services, never in views, admin classes or the Flutter client.
- Phone numbers are stored in E.164. Only regions in `ALLOWED_PHONE_REGIONS` (default `["CI"]`) are accepted.
- Commit after each task, on a branch `feat/foundation-enrolment`.

**Deliberately deferred to later plans** (do not build here): app PIN and fingerprint lock, Play Integrity / fake-GPS checks (the `integrity_verdict` field exists and is always `unchecked`), selfie match for a new device (the gate exists and blocks approval), console two-factor sign-in and four-eyes approval, generated Dart API client, field-level encryption, the generic idempotency-key middleware, iOS builds.

## Review Focus

1. **Local phone formats.** A user types `07 08 09 10 11` or `0708091011` without `+225`; both must be accepted and stored as `+2250708091011`. (Tests in Task 3 and Task 8.)
2. **Confirm retried after a lost response.** The app sends the right number, the server completes, the reply is lost, the app sends again; the second call must succeed, not report a wrong number. (Task 4.)
3. **Staff press "send" twice.** The user may type the first number after a second was issued; the answer must be a clear "number replaced" error, and the newest number must work. (Task 4.)
4. **Re-install on the same phone.** A user with an active device applies again with a new device identifier; this is a `new_device` application, the old device keeps working until the new one is confirmed, then is revoked. (Task 4, Task 6.)
5. **Two staff act on the same application.** The second approval or refusal must be rejected as an invalid state change, with one audit row, not two. (Task 4, Task 7.)

---

## File Structure

```
.gitignore  .env.example  docker-compose.yml  README.md
.github/workflows/ci.yml
docs/threat-model.md
backend/
  pyproject.toml  manage.py  pytest.ini
  config/        __init__.py settings.py urls.py celery.py wsgi.py asgi.py
  apps/core/     views.py (healthz)
  apps/providers/ base.py registry.py mocks.py
  apps/audit/    models.py services.py admin.py
  apps/accounts/
    models.py phones.py permissions.py authentication.py admin.py console_views.py tasks.py
    services/enrolment.py  services/device_auth.py
    api/serializers.py  api/views.py  api/urls.py
    templates/console/enrolment_send.html
    migrations/
  tests/         test_health.py test_providers.py test_phones.py test_models.py
                 test_enrolment_service.py test_enrolment_api.py test_device_auth.py
                 test_console.py test_full_flow.py
mobile/
  packages/petitgombo_core/  lib/petitgombo_core.dart  lib/src/{api,auth,enrolment,app}/...  test/...
  apps/jobber/       lib/main.dart  test/app_test.dart
  apps/householder/  lib/main.dart  test/app_test.dart
  apps/staff/        lib/main.dart  lib/src/{staff_api,staff_session,login,queue,detail}...  test/...
backend/apps/accounts/api/staff_views.py  staff_urls.py  staff_serializers.py
backend/apps/accounts/services/staff_auth.py
backend/tests/test_staff_api.py
```

---

### Task 1: Repository, backend skeleton, services, CI

**Files:**
- Create: `.gitignore`, `.env.example`, `docker-compose.yml`, `README.md`, `.github/workflows/ci.yml`
- Create: `backend/pyproject.toml`, `backend/manage.py`, `backend/pytest.ini`, `backend/config/*`, `backend/apps/core/views.py`
- Test: `backend/tests/test_health.py`

**Interfaces:**
- Produces: `GET /healthz` → `200 {"status": "ok"}`; settings module `config.settings`; Celery app `config.celery.app`; API prefix `/api/v1/`; test command `cd backend && .venv/bin/pytest`.

- [ ] **Step 1: Initialise the repository**

```bash
git init && git checkout -b feat/foundation-enrolment
```
`.gitignore` covers `.venv/`, `__pycache__/`, `.env`, `*.pyc`, `.pytest_cache/`, `mobile/**/build/`, `mobile/**/.dart_tool/`, `.DS_Store`. Keep `skill.original.md` out of git by listing it too.

- [ ] **Step 2: Write `docker-compose.yml`** with two services: `db` (`postgis/postgis:16-3.4`, port 5432, database/user/password `petitgombo`, named volume) and `redis` (`redis:7-alpine`, port 6379). Run `docker compose up -d` and expect both containers healthy.

- [ ] **Step 3: Create the virtualenv and dependencies**

`backend/pyproject.toml` dependencies: `Django>=5.2,<5.3`, `djangorestframework`, `drf-spectacular`, `django-environ`, `psycopg[binary]`, `redis`, `celery`, `phonenumbers`, `PyJWT`, `cryptography`. Dev extras: `pytest`, `pytest-django`, `freezegun`, `ruff`.

```bash
cd backend && python3.13 -m venv .venv && .venv/bin/pip install -e '.[dev]'
```

- [ ] **Step 4: Write the failing test** in `backend/tests/test_health.py`

```python
def test_healthz_ok(client, db):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}

def test_settings_use_postgres(settings):
    assert settings.DATABASES["default"]["ENGINE"] == "django.db.backends.postgresql"
    assert settings.LANGUAGE_CODE == "fr"
    assert settings.TIME_ZONE == "Africa/Abidjan"
```

- [ ] **Step 5: Run** `.venv/bin/pytest tests/test_health.py -v` — expected FAIL (no Django project).

- [ ] **Step 6: Create the project.** `config/settings.py` reads everything through `django-environ` (`DATABASE_URL`, `REDIS_URL`, `SECRET_KEY`, `DEBUG`, `ALLOWED_HOSTS`). Installed apps: Django contrib (admin, auth, contenttypes, sessions, messages, staticfiles), `rest_framework`, `drf_spectacular`, `apps.core`, `apps.providers`, `apps.audit`, `apps.accounts`. `USE_TZ = True`. Cache: Redis from `REDIS_URL`; `pytest.ini` sets `DJANGO_SETTINGS_MODULE=config.settings` and tests override the cache to `LocMemCache` via an autouse fixture in `tests/conftest.py`. `config/celery.py` defines `app = Celery("petitgombo")` configured from settings with `CELERY_BROKER_URL = REDIS_URL`. `config/urls.py` routes `healthz`, `admin/`, `api/v1/` (empty include for now), `api/schema/` (drf-spectacular). `healthz` runs `SELECT 1` and returns the JSON above.

- [ ] **Step 7: Run** `.venv/bin/pytest -v` and `.venv/bin/ruff check .` — expected PASS, no lint errors.

- [ ] **Step 8: Write `.github/workflows/ci.yml`** with two jobs. `backend`: service containers `postgis/postgis:16-3.4` and `redis:7-alpine`, Python 3.13, `pip install -e 'backend[dev]'`, `ruff check backend`, `pytest` in `backend/`. `mobile`: `subosito/flutter-action` pinned to Flutter 3.24.2, then `flutter analyze` and `flutter test` in each of the four Dart packages (the job is allowed to find no packages until Task 8 lands: guard each with `if [ -d ... ]`).

- [ ] **Step 9: Write `README.md`**: prerequisites, the commands from steps 2, 3 and 7, how to create a superuser, and an "Open decisions" section listing the spec's unresolved items (providers, legal, safety desk, insurance, official WhatsApp number).

- [ ] **Step 10: Commit** — `git add -A && git commit -m "chore: repository, backend skeleton, CI"`

---

### Task 2: Threat model and provider interfaces with mocks

**Files:**
- Create: `docs/threat-model.md`, `backend/apps/providers/base.py`, `backend/apps/providers/mocks.py`, `backend/apps/providers/registry.py`
- Test: `backend/tests/test_providers.py`

**Interfaces:**
- Produces (in `apps/providers/base.py`, as `typing.Protocol` classes with frozen dataclasses for results):
  - `MessagingProvider.whatsapp_link(phone_e164: str, text: str) -> str`
  - `MessagingProvider.send_sms(phone_e164: str, text: str) -> MessageResult` (`MessageResult(provider_ref: str, accepted: bool)`)
  - `PaymentProvider.collect(reference: str, phone_e164: str, amount_xof: int) -> PaymentResult`, `.payout(...)` same parameters, `.refund(reference: str) -> PaymentResult`, `.verify_webhook(headers: dict, body: bytes) -> bool` (`PaymentResult(provider_ref: str, status: str)` with status in `pending|successful|failed`)
  - `IdentityProvider.start_verification(user_ref: str) -> str`, `.get_result(session_ref: str) -> IdentityResult`, `.match_selfie(user_ref: str, image: bytes) -> bool` (`IdentityResult(status: str, full_name: str | None)`)
  - `MapProvider.static_area_image_url(lat: float, lng: float, radius_m: int) -> str`
- Produces (in `registry.py`): `get_messaging() -> MessagingProvider`, `get_payment()`, `get_identity()`, `get_map()`, each importing the dotted path in settings `MESSAGING_PROVIDER`, `PAYMENT_PROVIDER`, `IDENTITY_PROVIDER`, `MAP_PROVIDER` (defaults: the classes in `apps.providers.mocks`).
- Produces (in `mocks.py`): `MockMessaging` (records sent messages in a class-level list `outbox`), `MockPayment`, `MockIdentity`, `MockMap`.

- [ ] **Step 1: Write the failing tests**

```python
from apps.providers import registry
from apps.providers.mocks import MockMessaging

def test_whatsapp_link_strips_plus_and_encodes_text():
    link = registry.get_messaging().whatsapp_link("+2250708091011", "Bonjour : 123 456")
    assert link == "https://wa.me/2250708091011?text=Bonjour%20%3A%20123%20456"

def test_registry_loads_class_from_settings(settings):
    settings.MESSAGING_PROVIDER = "apps.providers.mocks.MockMessaging"
    assert isinstance(registry.get_messaging(), MockMessaging)

def test_mock_sms_is_recorded():
    MockMessaging.outbox.clear()
    result = registry.get_messaging().send_sms("+2250708091011", "test")
    assert result.accepted and MockMessaging.outbox == [("+2250708091011", "test")]

def test_mock_payment_collect_is_pending_then_verifiable():
    p = registry.get_payment()
    assert p.collect("ref-1", "+2250708091011", 5000).status == "pending"
    assert p.verify_webhook({"X-Mock-Signature": "valid"}, b"{}") is True
    assert p.verify_webhook({}, b"{}") is False
```

- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_providers.py -v` — expected FAIL (module missing).
- [ ] **Step 3: Implement** the protocols, mocks and registry as specified in Interfaces. `whatsapp_link` uses `urllib.parse.quote(text, safe="")`.
- [ ] **Step 4: Run** the tests — expected PASS.
- [ ] **Step 5: Write `docs/threat-model.md`.** One table, one row per threat named in spec section 8 (lure listings, account lending, address harvesting, collusion between accounts, forged or reused documents, fake GPS, relayed QR codes, SIM swap and account takeover, fake support agents and cloned apps, payment fraud, harassment, data breach, insider misuse). Columns: threat, who is harmed, controls (cite the spec's safety-rule numbers), status (`planned` / `built` / `tested`), test reference. Mark as `built` only the account-takeover and fake-support controls this plan delivers; everything else is `planned`. Add a short section listing the nine safety rules with a "tests" column, empty for now.
- [ ] **Step 6: Commit** — `git commit -am "feat: provider interfaces with mocks, threat model"` (after `git add`).

---

### Task 3: Accounts and audit models, phone normalisation

**Files:**
- Create: `backend/apps/accounts/models.py`, `backend/apps/accounts/phones.py`, `backend/apps/audit/models.py`, `backend/apps/audit/services.py`, migrations
- Test: `backend/tests/test_phones.py`, `backend/tests/test_models.py`

**Interfaces:**
- Produces `apps.accounts.phones.normalise(raw: str) -> str` — returns E.164 or raises `InvalidPhone`.
- Produces models:
  - `User(AbstractBaseUser, PermissionsMixin)`: `id` UUID pk, `phone` (E.164), `role` (`householder|jobber|staff`), `username` (nullable, unique, staff only, `USERNAME_FIELD`), `is_staff`, `is_active`, `created_at`. Constraint: unique `(phone, role)` where role is not `staff`. `AUTH_USER_MODEL = "accounts.User"`.
  - `Device`: `id` UUID pk (the app-generated device identifier), `user` FK, `public_key` (base64 text), `model`, `platform` (`android|ios`), `status` (`pending|active|revoked`; `pending` is used only for staff devices awaiting activation), `enrolled_at`, `revoked_at`. Constraint: at most one `active` device per user.
  - `DeviceEnrolmentRequest`: `id` UUID pk, `phone`, `role`, `kind` (`new_account|new_device`), `device_id` UUID, `device_model`, `platform`, `public_key`, `integrity_verdict` (default `unchecked`), `approx_lat`/`approx_lng` (`Decimal(5,2)`, nullable), `ip_address` (nullable), `flags` (JSON list), `status` (`pending|held|approved|code_sent|completed|refused|expired|locked`), `reason`, `client_token_hash`, `code_hash`, `code_expires_at`, `code_attempts` (int, default 0), `approved_by`/`sent_by` (FK User, nullable), `approved_at`, `sent_at`, `selfie_verified_at`, `completed_at`, `created_at`. Model permissions: `review_enrolment`, `send_enrolment_code`.
  - `RefreshToken`: `id`, `device` FK, `token_hash` (unique), `expires_at`, `rotated_at`, `revoked_at`, `created_at`.
  - `apps.audit.models.AdminAction`: `id`, `actor` FK User, `action` (str), `target_type`, `target_id`, `reason`, `metadata` JSON, `created_at`. `save()` raises `ValueError` when the row already exists; `delete()` always raises.
- Produces `apps.audit.services.record(actor, action: str, target, reason: str = "", **metadata) -> AdminAction`.
- A data migration creates the group `enrolment_agent` holding `review_enrolment`, `send_enrolment_code` and view permission on `DeviceEnrolmentRequest`.

- [ ] **Step 1: Write the failing tests**

```python
# test_phones.py
import pytest
from apps.accounts.phones import normalise, InvalidPhone

@pytest.mark.parametrize("raw", ["07 08 09 10 11", "0708091011", "+2250708091011", "00225 0708091011", "+225 07-08-09-10-11"])
def test_local_and_international_forms_normalise(raw):
    assert normalise(raw) == "+2250708091011"

@pytest.mark.parametrize("raw", ["", "12345", "+33612345678", "abcdefghij"])
def test_rejects_invalid_or_foreign_numbers(raw):
    with pytest.raises(InvalidPhone):
        normalise(raw)
```

```python
# test_models.py
import pytest
from django.db import IntegrityError
from apps.accounts.models import User, Device
from apps.audit.services import record

def test_same_phone_can_hold_both_roles_but_not_twice(db):
    User.objects.create(phone="+2250708091011", role="jobber")
    User.objects.create(phone="+2250708091011", role="householder")
    with pytest.raises(IntegrityError):
        User.objects.create(phone="+2250708091011", role="jobber")

def test_only_one_active_device_per_user(db, make_device):
    user = User.objects.create(phone="+2250708091011", role="jobber")
    make_device(user)
    with pytest.raises(IntegrityError):
        make_device(user)

def test_admin_action_is_append_only(db, staff_user):
    action = record(staff_user, "enrolment.approve", staff_user, reason="ok")
    with pytest.raises(ValueError):
        action.save()
    with pytest.raises(ValueError):
        action.delete()

def test_enrolment_agent_group_exists(db):
    from django.contrib.auth.models import Group
    perms = set(Group.objects.get(name="enrolment_agent").permissions.values_list("codename", flat=True))
    assert {"review_enrolment", "send_enrolment_code"} <= perms
```
Add fixtures `staff_user` (staff role, in `enrolment_agent`) and `make_device(user)` to `tests/conftest.py`.

- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_phones.py tests/test_models.py -v` — expected FAIL.
- [ ] **Step 3: Implement** `normalise` with `phonenumbers.parse(raw, "CI")`, requiring `is_valid_number` and a region in `settings.ALLOWED_PHONE_REGIONS`; then the models, constraints and migrations as listed.
- [ ] **Step 4: Run** the tests, then `python manage.py makemigrations --check` — expected PASS and "No changes detected".
- [ ] **Step 5: Commit** — `feat: accounts and audit models, phone normalisation`.

---

### Task 4: Enrolment service

**Files:**
- Create: `backend/apps/accounts/services/enrolment.py`, `backend/apps/accounts/tasks.py`
- Modify: `backend/config/settings.py` (new settings), `.env.example`
- Test: `backend/tests/test_enrolment_service.py`

**Interfaces:**
- Consumes: models and `normalise` from Task 3, `audit.services.record`.
- Settings (name = default): `ENROLMENT_CODE_TTL_MINUTES=60`, `ENROLMENT_CODE_MAX_ATTEMPTS=5`, `ENROLMENT_MAX_PER_PHONE_PER_DAY=3`, `ENROLMENT_MAX_PER_DEVICE_PER_DAY=3`, `ENROLMENT_MAX_PER_IP_PER_DAY=10`, `ENROLMENT_APPLICATION_TTL_DAYS=7`, `ENROLMENT_RESPONSE_HOURS=24`.
- Produces in `apps.accounts.services.enrolment`:
  - `class EnrolmentError(Exception)` with attribute `code` in `invalid_phone | rate_limited | invalid_state | selfie_required | code_invalid | code_replaced | code_expired | locked | forbidden`.
  - `apply(*, phone: str, role: str, device_id: UUID, device_model: str, platform: str, public_key: str, client_token: str, ip: str | None = None, approx_lat=None, approx_lng=None) -> DeviceEnrolmentRequest`
  - `approve(req, *, staff) -> None`, `refuse(req, *, staff, reason: str) -> None`, `hold(req, *, staff, reason: str) -> None`
  - `issue_code(req, *, staff) -> str` (returns the six-digit number in plain text, once)
  - `confirm(req, *, client_token: str, code: str) -> Device`
  - `check_client_token(req, client_token: str) -> bool`
  - `CONFIRMATION_MESSAGE = "petitGombo : votre numéro de confirmation est {code}. Saisissez-le dans l'application. Ne le partagez avec personne : notre équipe ne vous le demandera jamais."`
- Produces Celery task `apps.accounts.tasks.expire_stale_enrolments() -> int`, scheduled hourly in `CELERY_BEAT_SCHEDULE`.

**Rules the implementation must follow** (each is covered by a test below):
- `apply` normalises the phone. `kind` is `new_device` when an active `User` with that phone and role exists, otherwise `new_account`. If an open application (`pending|held|approved|code_sent`) already exists for the same `device_id` and matching `client_token`, return it instead of creating one. Rate limits count applications created in the last 24 hours per phone, per device and per IP. If the same `device_id` has applied for a different phone before, add the flag `device_multiple_numbers`. Coordinates are rounded to two decimals.
- State changes run inside `select_for_update()`. Allowed: `pending → approved|refused|held`, `held → approved|refused`, `approved|code_sent → code_sent` (issue), `code_sent → completed|locked`. Anything else raises `invalid_state`.
- `approve` on a `new_device` application raises `selfie_required` unless `selfie_verified_at` is set.
- `approve`, `refuse`, `hold` require the staff permission `accounts.review_enrolment`; `issue_code` requires `accounts.send_enrolment_code`; otherwise `forbidden`. Each success writes one `AdminAction` (`enrolment.approve`, `.refuse`, `.hold`, `.send_code`). The number never appears in the audit row.
- `issue_code` generates the number with `secrets.randbelow`, stores `HMAC-SHA256(SECRET_KEY, f"{req.id}:{code}")`, moves the previous hash to a `previous_code_hash` field (add it to the model), resets `code_attempts`, sets `code_expires_at`, `sent_by`, `sent_at`.
- `confirm`: wrong `client_token` → `forbidden`. Status `completed` with the correct number → return the existing device (retry-safe). Status `locked` → `locked`. Number matching `previous_code_hash` → `code_replaced` (does not count as an attempt). Expired → `code_expired`. Wrong → increment attempts, and at the maximum set status `locked` and raise `locked`, else `code_invalid`. Correct → get or create the `User`, revoke the user's other active devices, create the `Device` with the application's `device_id` and `public_key` (if a revoked `Device` with that id already exists for the same user, reactivate it with the new key; if it belongs to another user, raise `invalid_state`), set `completed`.
- `expire_stale_enrolments` sets `expired` on `pending|held|approved|code_sent` applications older than the TTL and returns the count.

- [ ] **Step 1: Write the failing tests.** Use a fixture `application(**overrides)` that calls `apply` with phone `0708091011`, role `jobber`, a fresh `device_id`, `client_token="tok"`. Tests, one behaviour each:

```python
def test_apply_normalises_phone_and_starts_pending(application):
    req = application()
    assert (req.phone, req.status, req.kind, req.integrity_verdict) == ("+2250708091011", "pending", "new_account", "unchecked")

def test_apply_twice_with_same_device_and_token_returns_same_row(application):
    did = uuid4(); assert application(device_id=did).id == application(device_id=did).id

def test_fourth_application_for_a_phone_in_a_day_is_rate_limited(application):
    for _ in range(3): application()
    with pytest.raises(EnrolmentError) as e: application()
    assert e.value.code == "rate_limited"

def test_device_applying_for_second_number_is_flagged(application):
    did = uuid4(); application(device_id=did, client_token="a")
    req = application(device_id=did, client_token="b", phone="0102030405")
    assert "device_multiple_numbers" in req.flags

def test_full_happy_path_creates_user_and_active_device(application, staff_user):
    req = application(); approve(req, staff=staff_user); code = issue_code(req, staff=staff_user)
    device = confirm(req, client_token="tok", code=code)
    req.refresh_from_db()
    assert req.status == "completed" and device.status == "active" and device.user.role == "jobber"
    assert AdminAction.objects.filter(action__in=["enrolment.approve", "enrolment.send_code"]).count() == 2
    assert code not in str(list(AdminAction.objects.values()))

def test_confirm_again_after_success_returns_same_device(...)      # Review Focus 2
def test_older_number_after_resend_is_code_replaced_and_new_one_works(...)  # Review Focus 3
def test_second_approval_is_invalid_state_with_single_audit_row(...)        # Review Focus 5
def test_five_wrong_numbers_lock_the_application(...)                       # then the right number raises "locked"
def test_expired_number_raises_code_expired(...)                            # freezegun, +61 minutes
def test_wrong_client_token_is_forbidden(...)
def test_new_device_cannot_be_approved_without_selfie(...)                  # raises "selfie_required"
def test_new_device_confirmation_revokes_previous_device(...)               # Review Focus 4: old device stays active until confirm
def test_staff_without_permission_cannot_approve_or_send(...)               # "forbidden"
def test_refuse_and_hold_record_reason_and_audit(...)
def test_stale_applications_expire(...)                                     # freezegun, +8 days, task returns 1
def test_revoked_device_id_re_enrolling_is_reactivated_with_new_key(...)    # same device_id, same user
```
Write every listed test in full; each asserts the error `code` or resulting `status` named in the rules above.

- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_enrolment_service.py -v` — expected FAIL (module missing).
- [ ] **Step 3: Implement** the service, the task, the `previous_code_hash` migration and the settings. Compare hashes with `hmac.compare_digest`.
- [ ] **Step 4: Run** the tests — expected PASS (17 tests).
- [ ] **Step 5: Commit** — `feat: device enrolment service`.

---

### Task 5: Enrolment public API

**Files:**
- Create: `backend/apps/accounts/api/serializers.py`, `backend/apps/accounts/api/views.py`, `backend/apps/accounts/api/urls.py`
- Modify: `backend/config/urls.py`
- Test: `backend/tests/test_enrolment_api.py`

**Interfaces:**
- Consumes: Task 4 service functions and `EnrolmentError`.
- Produces (all unauthenticated, JSON):
  - `POST /api/v1/enrolment/applications` body `{phone, role, device_id, device_model, platform, public_key, client_token, approx_lat?, approx_lng?}` → `201` (or `200` when an existing open application is returned) with the status body.
  - `GET /api/v1/enrolment/applications/{id}` with header `X-Enrolment-Token` → status body.
  - `POST /api/v1/enrolment/applications/{id}/confirm` with the same header, body `{code}` → `200 {"status": "completed", "device_id": "..."}`.
  - Status body: `{"id", "status", "kind", "reason", "response_hours"}` where `status` shown to the client is `pending` for internal `pending|approved`, `held`, `awaiting_code` for `code_sent`, and `completed|refused|expired|locked` unchanged. `reason` is only filled for `refused` and `held`.
  - Errors: `{"error": "<code>", "message": "<French sentence>"}`. HTTP status: `invalid_phone` and serializer errors 400, `forbidden` and unknown id 404 (do not reveal existence), `rate_limited` 429, `invalid_state` 409, `code_invalid|code_replaced|code_expired` 422, `locked` 423.
  - French messages (exact): `invalid_phone` "Numéro de téléphone invalide."; `rate_limited` "Trop de demandes. Réessayez demain."; `code_invalid` "Numéro de confirmation incorrect."; `code_replaced` "Ce numéro a été remplacé. Utilisez le dernier message WhatsApp reçu."; `code_expired` "Ce numéro a expiré. Nous vous en envoyons un nouveau."; `locked` "Trop d'essais. Faites une nouvelle demande."; `invalid_state` "Cette demande ne peut plus être modifiée."
- `role` accepts only `householder` or `jobber`. `public_key` must decode from base64 to exactly 32 bytes. The client IP is taken from `REMOTE_ADDR`.

- [ ] **Step 1: Write the failing tests**

```python
def test_create_returns_201_pending_with_response_hours(api_client, payload):
    r = api_client.post("/api/v1/enrolment/applications", payload, format="json")
    assert r.status_code == 201
    assert r.json()["status"] == "pending" and r.json()["response_hours"] == 24

def test_repeat_create_returns_200_same_id(api_client, payload): ...
def test_staff_role_and_bad_public_key_are_rejected_400(api_client, payload): ...
def test_status_requires_matching_token_else_404(api_client, created): ...
def test_approved_is_shown_as_pending_and_code_sent_as_awaiting_code(api_client, created, staff_user): ...
def test_confirm_success_returns_device_id(api_client, created, staff_user): ...
def test_wrong_code_is_422_with_french_message(api_client, created, staff_user):
    ...
    assert r.status_code == 422 and r.json() == {"error": "code_invalid", "message": "Numéro de confirmation incorrect."}
def test_rate_limit_is_429(api_client, payload): ...
def test_refused_application_shows_reason(api_client, created, staff_user): ...
def test_schema_lists_the_three_enrolment_paths(api_client):
    paths = api_client.get("/api/schema/?format=json").json()["paths"]
    assert {"/api/v1/enrolment/applications", "/api/v1/enrolment/applications/{id}", "/api/v1/enrolment/applications/{id}/confirm"} <= set(paths)
```
Write each in full. Fixtures: `api_client` (DRF `APIClient`), `payload` (valid body with a generated Ed25519 public key), `created` (posts the payload and returns the JSON plus token).

- [ ] **Step 2: Run** — expected FAIL (404s).
- [ ] **Step 3: Implement** serializers, three `APIView`s and one exception mapper that turns `EnrolmentError` into the error body. Views contain no rules, only calls into the service.
- [ ] **Step 4: Run** `.venv/bin/pytest tests/test_enrolment_api.py -v` — expected PASS.
- [ ] **Step 5: Commit** — `feat: enrolment API`.

---

### Task 6: Device sign-in, tokens, permissions

**Files:**
- Create: `backend/apps/accounts/services/device_auth.py`, `backend/apps/accounts/authentication.py`, `backend/apps/accounts/permissions.py`
- Modify: `backend/apps/accounts/api/views.py`, `backend/apps/accounts/api/urls.py`, `backend/config/settings.py`
- Test: `backend/tests/test_device_auth.py`, `backend/tests/test_full_flow.py`

**Interfaces:**
- Settings: `ACCESS_TOKEN_TTL_MINUTES=15`, `REFRESH_TOKEN_TTL_DAYS=30`, `AUTH_CHALLENGE_TTL_SECONDS=120`.
- Produces in `device_auth`:
  - `@dataclass TokenPair(access: str, refresh: str)`
  - `class AuthError(Exception)` with `code` in `unknown_device | device_revoked | challenge_invalid | signature_invalid | refresh_invalid`
  - `create_challenge(device_id: UUID) -> str` — random nonce stored in the Django cache under `auth-challenge:{device_id}`, single use.
  - `sign_in(device_id: UUID, nonce: str, signature_b64: str) -> TokenPair` — verifies an Ed25519 signature over the UTF-8 bytes of `petitgombo-auth:{device_id}:{nonce}` with the device's stored public key.
  - `rotate(refresh: str) -> TokenPair` — marks the old token rotated and issues a new pair. Presenting an already-rotated token revokes every refresh token of that device and raises `refresh_invalid`.
  - Access token: HS256 JWT signed with `SECRET_KEY`, claims `sub` (user id), `did` (device id), `role`, `exp`. Refresh token: 32 random bytes, URL-safe, stored only as SHA-256.
- Produces `authentication.DeviceJWTAuthentication` (sets `request.user`, `request.auth = Device`; rejects a revoked device or inactive user with 401) as the default DRF authentication class, with `IsAuthenticated` as the default permission; the enrolment views opt out explicitly.
- Produces `permissions.IsHouseholder`, `permissions.IsJobber`.
- Produces endpoints: `POST /api/v1/auth/challenge {device_id}` → `{nonce}`; `POST /api/v1/auth/token {device_id, nonce, signature}` → `{access, refresh}`; `POST /api/v1/auth/refresh {refresh}` → `{access, refresh}`; `GET /api/v1/me` → `{id, phone, role, device_id}`. All auth failures return `401 {"error": code}`; an unknown device on `challenge` still returns a nonce (no device enumeration).

- [ ] **Step 1: Write the failing tests**

```python
def test_sign_in_with_valid_signature_returns_tokens_and_me_works(api_client, enrolled):
    nonce = api_client.post("/api/v1/auth/challenge", {"device_id": enrolled.device_id}, format="json").json()["nonce"]
    sig = enrolled.sign(f"petitgombo-auth:{enrolled.device_id}:{nonce}")
    tokens = api_client.post("/api/v1/auth/token", {"device_id": enrolled.device_id, "nonce": nonce, "signature": sig}, format="json").json()
    me = api_client.get("/api/v1/me", HTTP_AUTHORIZATION=f"Bearer {tokens['access']}").json()
    assert me["phone"] == "+2250708091011" and me["role"] == "jobber"

def test_nonce_cannot_be_reused(...)                 # second token call → 401 challenge_invalid
def test_signature_from_another_key_is_rejected(...) # 401 signature_invalid
def test_expired_challenge_is_rejected(...)          # freezegun +121 s
def test_expired_access_token_is_401(...)            # freezegun +16 min
def test_refresh_rotates_and_old_refresh_revokes_family(...)
def test_revoked_device_cannot_sign_in_or_use_old_access_token(...)   # Review Focus 4
def test_me_without_token_is_401(...)
def test_role_permissions(rf, ...):                  # IsJobber allows jobber, denies householder; IsHouseholder the reverse
def test_unknown_device_challenge_still_returns_nonce(...)
```
Fixture `enrolled` runs the Task 4 flow with a generated Ed25519 key and exposes `device_id` and `sign(message) -> base64`.

`test_full_flow.py` holds one test, `test_apply_approve_send_confirm_sign_in`, that goes through HTTP only for the client side (create → status → confirm → challenge → token → me) and through the service for the staff side, asserting the final `me` body and that exactly one active device exists.

- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the service, authentication class, permissions and views.
- [ ] **Step 4: Run** `.venv/bin/pytest -v` (whole suite) — expected PASS.
- [ ] **Step 5: Update `docs/threat-model.md`**: set the SIM-swap / account-takeover row to `tested` with these test names.
- [ ] **Step 6: Commit** — `feat: device-key sign-in, tokens, role permissions`.

---

### Task 7: Operations console — enrolment queue and WhatsApp send

**Files:**
- Create: `backend/apps/accounts/admin.py`, `backend/apps/accounts/console_views.py`, `backend/apps/accounts/templates/console/enrolment_send.html`, `backend/apps/audit/admin.py`
- Modify: `backend/config/settings.py` (`OFFICIAL_WHATSAPP_NUMBER`, admin site titles), `.env.example`
- Test: `backend/tests/test_console.py`

**Interfaces:**
- Consumes: Task 4 service, `registry.get_messaging().whatsapp_link`, `CONFIRMATION_MESSAGE`.
- Produces:
  - Admin list for `DeviceEnrolmentRequest` titled "Demandes d'enrôlement": columns created, phone, role, kind, status, flags, integrity verdict; filters status, kind, role; default ordering oldest pending first. All fields read-only; no add, no delete. Hash and token fields are not displayed.
  - Custom admin URLs, POST only, CSRF protected, each calling the matching service function with `request.user`: `enrolment/<uuid>/approve/`, `.../refuse/` (form field `reason`, required), `.../hold/` (`reason`, required), `.../send/`.
  - The change page shows buttons according to status: `pending|held` → Approuver, Refuser, Mettre en attente; `approved` → "Envoyer par WhatsApp"; `code_sent` → "Renvoyer par WhatsApp".
  - `send` renders `enrolment_send.html` with one link "Ouvrir WhatsApp" (`target="_blank" rel="noopener"`) whose `href` is `whatsapp_link(req.phone, CONFIRMATION_MESSAGE.format(code=code))`, plus the reminder "Envoyez uniquement depuis le numéro officiel : {OFFICIAL_WHATSAPP_NUMBER}". Response header `Cache-Control: no-store`. The number is not shown anywhere else and is not stored in the session.
  - `EnrolmentError` is shown as a Django admin error message and redirects back to the change page.
  - Read-only admin for `AdminAction` (no add, change or delete).

- [ ] **Step 1: Write the failing tests**

```python
def test_agent_sees_queue_without_secret_fields(agent_client, pending_request):
    html = agent_client.get(f"/admin/accounts/deviceenrolmentrequest/{pending_request.id}/change/").content.decode()
    assert "Approuver" in html and "code_hash" not in html and "client_token_hash" not in html

def test_approve_then_send_shows_whatsapp_link_with_working_code(agent_client, pending_request):
    agent_client.post(f"/admin/accounts/deviceenrolmentrequest/{pending_request.id}/approve/")
    r = agent_client.post(f"/admin/accounts/deviceenrolmentrequest/{pending_request.id}/send/")
    html = r.content.decode()
    assert r["Cache-Control"] == "no-store"
    assert "https://wa.me/2250708091011?text=petitGombo" in html
    code = re.search(r"confirmation%20est%20(\d{6})", html).group(1)
    assert confirm(pending_request, client_token="tok", code=code).status == "active"

def test_send_via_get_is_405(...)
def test_staff_outside_group_gets_403_on_approve_and_send(...)
def test_refuse_requires_reason(...)                       # empty reason → no state change, error message shown
def test_second_agent_approving_sees_error_and_single_audit_row(...)   # Review Focus 5
def test_new_device_approval_shows_selfie_required_message(...)
def test_requests_cannot_be_added_or_deleted_in_admin(...)  # add and delete URLs → 403
def test_admin_actions_are_read_only(...)
```

- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the admin classes, views and template.
- [ ] **Step 4: Run** `.venv/bin/pytest -v` and `.venv/bin/ruff check .` — expected PASS.
- [ ] **Step 5: Manual check.** `python manage.py migrate && python manage.py createsuperuser && python manage.py runserver`; create an application with `curl` (command recorded in the README), then approve and send it in `/admin/` and confirm the WhatsApp link opens a chat with the prefilled French message.
- [ ] **Step 6: Commit** — `feat: console enrolment queue with WhatsApp confirmation`.

---

### Task 8: Flutter core package — API client, device identity, enrolment logic

**Files:**
- Create: `mobile/packages/petitgombo_core/pubspec.yaml`, `lib/petitgombo_core.dart`
- Create: `lib/src/api/api_client.dart`, `lib/src/api/api_error.dart`, `lib/src/auth/key_value_store.dart`, `lib/src/auth/device_identity.dart`, `lib/src/auth/session.dart`, `lib/src/enrolment/phone_format.dart`, `lib/src/enrolment/enrolment_state.dart`, `lib/src/enrolment/enrolment_controller.dart`
- Test: `test/phone_format_test.dart`, `test/device_identity_test.dart`, `test/api_client_test.dart`, `test/enrolment_controller_test.dart`

**Interfaces:**
- Consumes: the HTTP contract of Tasks 5 and 6.
- Dependencies: `flutter_riverpod ^2.5.1`, `go_router ^14.2.0`, `dio ^5.5.0`, `flutter_secure_storage ^9.2.2`, `cryptography ^2.7.0`, `uuid ^4.4.0`, `device_info_plus ^10.1.0`; dev: `flutter_test`, `flutter_lints`, `http_mock_adapter ^0.6.1`.
- Produces:
  - `enum AppRole { householder, jobber }`
  - `String? normaliseIvorianPhone(String input)` — returns `+225` followed by 10 digits, or `null`.
  - `abstract class KeyValueStore { Future<String?> read(String key); Future<void> write(String key, String value); Future<void> delete(String key); }` with `SecureKeyValueStore` (flutter_secure_storage) and `InMemoryKeyValueStore`.
  - `class DeviceIdentity { DeviceIdentity(KeyValueStore store); Future<String> deviceId(); Future<String> clientToken(); Future<String> publicKeyBase64(); Future<String> sign(String message); Future<void> reset(); }` — creates and persists a UUID, a 32-byte random token and an Ed25519 key pair on first use.
  - `class ApiError implements Exception { final String code; final String message; final int? status; }` — `code` is the server's `error` value, or `network` when there is no response.
  - `class ApiClient { ApiClient(Dio dio); Future<EnrolmentStatus> apply({required String phone, required AppRole role, required String deviceId, required String deviceModel, required String platform, required String publicKey, required String clientToken}); Future<EnrolmentStatus> status(String id, String clientToken); Future<void> confirm(String id, String clientToken, String code); Future<String> challenge(String deviceId); Future<TokenPair> token(String deviceId, String nonce, String signature); Future<TokenPair> refresh(String refreshToken); Future<Me> me(String accessToken); }`
  - `class EnrolmentStatus { final String id; final String status; final String? reason; final int responseHours; }`, `class TokenPair { final String access; final String refresh; }`, `class Me { final String id; final String phone; final String role; }`
  - `class Session { Session(ApiClient api, DeviceIdentity identity, KeyValueStore store); Future<Me?> restore(); Future<Me> signIn(); Future<void> signOut(); }` — `signIn` does challenge → sign → token → me and stores the refresh token; `restore` uses the stored refresh token and returns `null` when there is none or it is rejected.
  - `sealed class EnrolmentState` with `EnrolmentInitial`, `EnrolmentSubmitting`, `EnrolmentPending(int responseHours)`, `EnrolmentHeld(String? reason)`, `EnrolmentAwaitingCode({String? errorMessage})`, `EnrolmentRefused(String? reason)`, `EnrolmentLocked`, `EnrolmentExpired`, `EnrolmentDone(Me me)`, `EnrolmentFailure(String message)`.
  - `class EnrolmentController extends StateNotifier<EnrolmentState> { EnrolmentController({required ApiClient api, required DeviceIdentity identity, required Session session, required KeyValueStore store, required AppRole role, required String deviceModel}); Future<void> resume(); Future<void> submitPhone(String input); Future<void> refresh(); Future<void> submitCode(String code); Future<void> startOver(); }`
- Behaviour: the application id is persisted under `enrolment.application_id` so `resume()` restores the right state after the app is closed. `submitPhone` with an invalid number sets `EnrolmentFailure("Numéro de téléphone invalide.")` without a network call. Server status maps `pending → EnrolmentPending`, `held → EnrolmentHeld`, `awaiting_code → EnrolmentAwaitingCode`, `refused`, `locked`, `expired` likewise. `submitCode` on success calls `session.signIn()` and sets `EnrolmentDone`; on `code_invalid|code_replaced|code_expired` it stays in `EnrolmentAwaitingCode` with the server's message; on `locked` it sets `EnrolmentLocked`. A `network` error sets `EnrolmentFailure("Pas de connexion. Réessayez.")` and keeps the stored application id. `startOver` deletes the stored application id and returns to `EnrolmentInitial` (the device identity is kept).

- [ ] **Step 1: Create the package** — `flutter create --template=package mobile/packages/petitgombo_core`, then set the dependencies above.

- [ ] **Step 2: Write the failing tests**

```dart
// phone_format_test.dart
test('local and international forms normalise', () {
  for (final raw in ['07 08 09 10 11', '0708091011', '+2250708091011', '00225 0708091011']) {
    expect(normaliseIvorianPhone(raw), '+2250708091011');
  }
});
test('invalid input returns null', () {
  for (final raw in ['', '12345', '+33612345678', 'abc']) { expect(normaliseIvorianPhone(raw), isNull); }
});

// device_identity_test.dart
test('identity is created once and persists', () async {
  final store = InMemoryKeyValueStore();
  final a = DeviceIdentity(store); final b = DeviceIdentity(store);
  expect(await a.deviceId(), await b.deviceId());
  expect(await a.publicKeyBase64(), await b.publicKeyBase64());
  expect(base64Decode(await a.publicKeyBase64()).length, 32);
});
test('signature verifies with the public key', () async { /* verify with Ed25519().verify */ });

// api_client_test.dart (http_mock_adapter)
test('apply posts the snake_case body and parses the status', ...);   // asserts body keys: phone, role, device_id, device_model, platform, public_key, client_token
test('status and confirm send X-Enrolment-Token', ...);
test('422 body becomes ApiError(code: code_invalid, message: server text)', ...);
test('connection failure becomes ApiError(code: network)', ...);

// enrolment_controller_test.dart (fake ApiClient)
test('invalid phone fails without calling the API', ...);
test('valid phone goes to EnrolmentPending(24) and stores the application id', ...);
test('resume restores EnrolmentAwaitingCode from the stored id', ...);
test('wrong code stays in EnrolmentAwaitingCode with the server message', ...);
test('correct code signs in and ends in EnrolmentDone', ...);
test('locked response ends in EnrolmentLocked', ...);
test('network error keeps the stored application id', ...);
test('startOver clears the application id but keeps the device id', ...);
```
Write each in full.

- [ ] **Step 3: Run** `cd mobile/packages/petitgombo_core && flutter test` — expected FAIL (symbols missing).
- [ ] **Step 4: Implement** the files listed.
- [ ] **Step 5: Run** `flutter test && flutter analyze` — expected all tests pass, no issues.
- [ ] **Step 6: Commit** — `feat(mobile): core package with API client, device identity, enrolment logic`.

---

### Task 9: Flutter apps — enrolment screens in both apps

**Files:**
- Create: `mobile/packages/petitgombo_core/lib/src/app/petitgombo_app.dart`, `lib/src/app/theme.dart`, `lib/src/app/providers.dart`, `lib/src/enrolment/screens/phone_entry_screen.dart`, `waiting_screen.dart`, `code_entry_screen.dart`, `outcome_screen.dart`, `lib/src/home/home_placeholder_screen.dart`
- Create: `mobile/apps/jobber` and `mobile/apps/householder` (`lib/main.dart`, `test/app_test.dart`)
- Modify: `README.md`, `docs/threat-model.md`
- Test: `mobile/packages/petitgombo_core/test/enrolment_screens_test.dart`, the two `app_test.dart`

**Interfaces:**
- Consumes: everything Task 8 produces.
- Produces: `class PetitGomboApp extends StatelessWidget { const PetitGomboApp({required AppRole role, List<Override> overrides = const []}); }` — builds the `ProviderScope`, router and theme. Riverpod providers in `providers.dart`: `keyValueStoreProvider`, `dioProvider` (base URL from `String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000')`, 15 s timeouts), `apiClientProvider`, `deviceIdentityProvider`, `sessionProvider`, `enrolmentControllerProvider`.
- Each app's `main.dart` is only `runApp(const PetitGomboApp(role: AppRole.jobber))` (or `.householder`). Android application ids: `com.regisse.petitgombo.jobber` and, for the householder app, `com.regisse.petitgombo` (set `applicationId` and `namespace` by hand in `android/app/build.gradle` after `flutter create`). App names: "petitGombo Jobber", "petitGombo".
- Theme: Material 3, light only, white background, primary deep green `#1B5E20`, accent warm orange `#F57C00` (the spec's logo colours), minimum touch target 48 dp, system font, text scaling respected. Follow the `flutter-mobile-ui` skill when building the theme and screens.
- Routing: on start the app calls `session.restore()`; a restored session goes to the home placeholder, otherwise `enrolmentController.resume()` decides the screen from the state.
- Screens and exact copy:
  - Phone entry — title "Votre numéro de téléphone", field with fixed prefix "+225" and numeric keyboard, hint "07 08 09 10 11", button "Continuer", note "Nous vous enverrons un numéro de confirmation par WhatsApp."
  - Waiting (`EnrolmentPending`) — "Demande reçue", "Confirmation par WhatsApp sous {responseHours} h.", button "Actualiser". `EnrolmentHeld` shows "Votre demande est en cours de vérification." and the reason when present.
  - Code entry — title "Numéro de confirmation", six-digit numeric field, button "Valider", note "Notre équipe ne vous demandera jamais ce numéro.", error text under the field from `errorMessage`.
  - Outcome — refused: "Demande refusée" plus reason; locked: "Trop d'essais. Faites une nouvelle demande."; expired: "Votre demande a expiré."; each with the button "Nouvelle demande" calling `startOver()`.
  - Failure — a banner with the failure message and "Réessayer"; typed input is preserved.
  - Tone by role: the strings above are the householder ("vous") versions. For `AppRole.jobber` use "Ton numéro de téléphone", "On t'envoie un numéro de confirmation par WhatsApp.", "Ta demande est en cours de vérification.", "Ta demande a expiré."; all other strings are shared. Keep the two sets in one `EnrolmentCopy.forRole(AppRole)` class.
  - Home placeholder — "Bienvenue" and the role label ("Mini-jobber" / "Particulier"), button "Se déconnecter".
- The waiting screen refreshes when "Actualiser" is pressed and when the app returns to the foreground. No timer-based polling.

- [ ] **Step 1: Create the apps**

```bash
cd mobile/apps && flutter create --org com.regisse.petitgombo --platforms android --project-name jobber jobber
flutter create --org com.regisse.petitgombo --platforms android --project-name householder householder
```
Add `petitgombo_core` as a path dependency in both; delete the generated counter code and test.

- [ ] **Step 2: Write the failing widget tests** (controller replaced through `overrides` with a fake holding a fixed state)

```dart
testWidgets('initial state shows the phone screen with the WhatsApp note', (t) async {
  await pumpWith(t, EnrolmentInitial());
  expect(find.text('Votre numéro de téléphone'), findsOneWidget);
  expect(find.text('Nous vous enverrons un numéro de confirmation par WhatsApp.'), findsOneWidget);
});
testWidgets('Continuer sends the typed number to submitPhone', ...);          // types 0708091011, expects fake.submitted == '0708091011'
testWidgets('pending shows the response time', (t) async {
  await pumpWith(t, EnrolmentPending(24));
  expect(find.text('Confirmation par WhatsApp sous 24 h.'), findsOneWidget);
});
testWidgets('awaiting code shows the server error under the field', ...);     // 'Numéro de confirmation incorrect.'
testWidgets('Valider is disabled until six digits are entered', ...);
testWidgets('locked shows Nouvelle demande and calls startOver', ...);
testWidgets('failure keeps the typed phone number', ...);
testWidgets('done shows the home placeholder with the role label', ...);      // 'Mini-jobber' for AppRole.jobber
```
Each `app_test.dart` pumps `PetitGomboApp` with in-memory overrides and expects the phone screen; the householder test also expects no "Mini-jobber" text.

- [ ] **Step 3: Run** `flutter test` in the three packages — expected FAIL.
- [ ] **Step 4: Implement** the theme, providers, screens and the two `main.dart` files.
- [ ] **Step 5: Run** `flutter test && flutter analyze` in `mobile/packages/petitgombo_core`, `mobile/apps/jobber`, `mobile/apps/householder` — expected all pass, no issues.
- [ ] **Step 6: End-to-end manual check.** With the backend running, start the jobber app on an Android emulator (`flutter run`), enter `0708091011`, approve and send in `/admin/`, read the number from the WhatsApp link, type it in the app, and reach "Bienvenue". Close and reopen the app: it opens on "Bienvenue" without asking again. Record the result (or the reason it could not be run, for example no emulator) in the task notes.
- [ ] **Step 7: Update the documents.** README: how to run each app and pass `API_BASE_URL`. Threat model: mark fake-support wording (the "never ask for this number" messages) as `built`.
- [ ] **Step 8: Commit** — `feat(mobile): householder and jobber apps with device enrolment`.

---

### Task 10: Staff API — staff device activation, sign-in, enrolment queue

**Files:**
- Create: `backend/apps/accounts/services/staff_auth.py`, `backend/apps/accounts/api/staff_serializers.py`, `backend/apps/accounts/api/staff_views.py`, `backend/apps/accounts/api/staff_urls.py`
- Modify: `backend/apps/accounts/permissions.py`, `backend/apps/accounts/admin.py` (staff device admin), `backend/config/urls.py`, `backend/config/settings.py`, `.env.example`
- Test: `backend/tests/test_staff_api.py`

**Interfaces:**
- Consumes: Task 4 service functions, Task 6 `create_challenge`, token issuing and `DeviceJWTAuthentication`, Task 7 `CONFIRMATION_MESSAGE` usage and `whatsapp_link`.
- Settings: `STAFF_ACCESS_TOKEN_TTL_MINUTES=10`, `STAFF_REFRESH_TOKEN_TTL_HOURS=12`, `STAFF_LOGIN_MAX_FAILURES=5`, `STAFF_LOGIN_LOCK_MINUTES=15`.
- Produces in `staff_auth`:
  - `register_device(*, username: str, password: str, device_id: UUID, device_model: str, platform: str, public_key: str) -> Device` — checks the password, creates the device as `pending` (or returns the existing one unchanged).
  - `activate_device(device, *, admin) -> None` — superuser only; revokes the staff member's other active device; writes `AdminAction` `staff_device.activate`. `revoke_device(device, *, admin) -> None` likewise (`staff_device.revoke`).
  - `login(*, username: str, password: str, device_id: UUID, nonce: str, signature_b64: str) -> TokenPair` — requires correct password, an `active` device belonging to that staff user, and a valid signature (same message format as Task 6). Uses the staff token lifetimes.
  - Errors reuse `AuthError` with extra codes `bad_credentials | device_pending | locked`. Failures are counted per username in the cache; after the maximum, every attempt returns `locked` until the lock expires. Wrong username and wrong password are indistinguishable.
- Produces `permissions.HasStaffPermission(perm: str)` — a factory returning a DRF permission class that requires `role == "staff"`, `is_staff`, and the Django permission.
- Produces endpoints:
  - `POST /api/v1/staff/devices` body `{username, password, device_id, device_model, platform, public_key}` → `201|200 {"status": "pending"|"active"|"revoked"}`
  - `POST /api/v1/staff/auth/login` body `{username, password, device_id, nonce, signature}` → `{access, refresh}`; errors `401 {"error": code}`, `locked` → `423`.
  - `GET /api/v1/staff/me` → `{id, username, permissions: [codenames]}`
  - `GET /api/v1/staff/enrolments?status=pending|held|approved|code_sent` (default `pending`, oldest first, page size 20) → items `{id, phone, role, kind, status, flags, device_model, platform, integrity_verdict, created_at}`
  - `GET /api/v1/staff/enrolments/{id}` → the item plus `reason`, `approved_at`, `sent_at`
  - `POST /api/v1/staff/enrolments/{id}/approve`, `.../refuse` `{reason}`, `.../hold` `{reason}` → the updated item
  - `POST /api/v1/staff/enrolments/{id}/send` → `{"whatsapp_url": "https://wa.me/..."}` with `Cache-Control: no-store`
  - Queue endpoints require `HasStaffPermission("accounts.review_enrolment")`; `send` requires `accounts.send_enrolment_code`. `EnrolmentError` maps as in Task 5.
- Web console: an admin page for staff devices ("Appareils du personnel") listing pending devices with actions "Activer" and "Révoquer", visible to superusers only.
- A user access token (householder or jobber) must get `403` on every `/api/v1/staff/` endpoint.

- [ ] **Step 1: Write the failing tests**

```python
def test_register_staff_device_is_pending_and_login_refused_until_activated(api_client, staff_user, staff_key):
    r = api_client.post("/api/v1/staff/devices", staff_key.registration(password="pw"), format="json")
    assert r.status_code == 201 and r.json() == {"status": "pending"}
    assert staff_login(api_client, staff_key, "pw").json() == {"error": "device_pending"}

def test_activated_device_logs_in_and_lists_pending_queue(api_client, active_staff, pending_request):
    r = api_client.get("/api/v1/staff/enrolments", HTTP_AUTHORIZATION=active_staff.bearer)
    assert [i["id"] for i in r.json()["results"]] == [str(pending_request.id)]
    assert "code_hash" not in r.json()["results"][0]

def test_approve_then_send_returns_whatsapp_url_with_working_code(...)   # no-store header, code confirms via service
def test_wrong_password_and_unknown_user_give_same_error(...)            # both 401 bad_credentials
def test_sixth_failed_login_is_423_locked_even_with_right_password(...)
def test_staff_without_permission_gets_403_on_queue_and_send(...)
def test_jobber_token_gets_403_on_all_staff_endpoints(...)
def test_activation_is_superuser_only_and_revokes_previous_staff_device(...)
def test_revoked_staff_device_token_is_401(...)
def test_staff_access_token_expires_after_ten_minutes(...)               # freezegun +11 min
def test_refuse_without_reason_is_400(...)
def test_second_approve_is_409_invalid_state(...)                        # Review Focus 5
```
Write each in full. Fixtures: `staff_key` (Ed25519 key plus helpers), `active_staff` (registered, activated, logged in; exposes `bearer`).

- [ ] **Step 2: Run** `.venv/bin/pytest tests/test_staff_api.py -v` — expected FAIL.
- [ ] **Step 3: Implement** the service, permission factory, serializers, views, URLs and the staff-device admin page. Views only call services.
- [ ] **Step 4: Run** `.venv/bin/pytest -v` and `.venv/bin/ruff check .` — expected PASS.
- [ ] **Step 5: Commit** — `feat: staff API with activated devices and enrolment queue`.

---

### Task 11: Staff app (Flutter)

**Files:**
- Create: `mobile/apps/staff` — `lib/main.dart`, `lib/src/staff_api.dart`, `lib/src/staff_session.dart`, `lib/src/staff_controller.dart`, `lib/src/screens/login_screen.dart`, `device_pending_screen.dart`, `queue_screen.dart`, `enrolment_detail_screen.dart`, `reason_dialog.dart`
- Modify: `mobile/apps/staff/android/app/src/main/kotlin/.../MainActivity.kt`, `README.md`, `.github/workflows/ci.yml`
- Test: `mobile/apps/staff/test/staff_api_test.dart`, `staff_controller_test.dart`, `screens_test.dart`

**Interfaces:**
- Consumes: Task 10 endpoints; from `petitgombo_core`: `DeviceIdentity`, `KeyValueStore`, `ApiError`, `TokenPair`, theme, `dioProvider`.
- Extra dependency: `url_launcher ^6.3.0`.
- Android application id `com.regisse.petitgombo.staff`, app name "petitGombo Staff".
- Produces:
  - `class StaffApi { StaffApi(Dio dio); Future<String> registerDevice({required String username, required String password, required String deviceId, required String deviceModel, required String platform, required String publicKey}); Future<TokenPair> login({required String username, required String password, required String deviceId, required String nonce, required String signature}); Future<String> challenge(String deviceId); Future<StaffMe> me(String access); Future<List<EnrolmentItem>> enrolments(String access, {String status = 'pending'}); Future<EnrolmentItem> enrolment(String access, String id); Future<EnrolmentItem> approve(String access, String id); Future<EnrolmentItem> refuse(String access, String id, String reason); Future<EnrolmentItem> hold(String access, String id, String reason); Future<Uri> send(String access, String id); }`
  - `class EnrolmentItem { id, phone, role, kind, status, flags, deviceModel, platform, integrityVerdict, createdAt, reason }`, `class StaffMe { id, username, permissions }`
  - `class StaffSession` — `signIn(username, password)` registers the device when needed, then challenge → sign → login; holds tokens in memory only (the password is never stored; closing the app signs out); exposes `access`.
  - `typedef UrlOpener = Future<bool> Function(Uri uri);` injected into the detail screen (default: `launchUrl` with `LaunchMode.externalApplication`), so tests can capture the URL.
- Behaviour and exact copy:
  - Login — fields "Identifiant", "Mot de passe", button "Se connecter". Errors: `bad_credentials` "Identifiant ou mot de passe incorrect."; `locked` "Trop d'essais. Réessayez dans 15 minutes."; `device_pending` opens the pending screen.
  - Device pending — "Appareil en attente d'activation par un administrateur.", button "Réessayer".
  - Queue — title "Demandes d'enrôlement"; three tabs "En attente" (`pending`), "À envoyer" (`approved`), "Envoyées" (`code_sent`); each row shows phone, role label, age of the request, and a warning icon when `flags` is not empty; pull to refresh; empty state "Aucune demande."
  - Detail — all item fields, flags in plain French (`device_multiple_numbers` → "Cet appareil a demandé plusieurs numéros."). Buttons by status: `pending|held` → "Approuver", "Refuser", "Mettre en attente"; `approved` → "Envoyer par WhatsApp"; `code_sent` → "Renvoyer par WhatsApp". Refuse and hold open a dialog requiring a reason ("Motif", button disabled while empty).
  - "Envoyer par WhatsApp" calls `send`, opens the returned URL with the `UrlOpener`, and shows "Envoyez uniquement depuis le WhatsApp officiel." The URL is not displayed, logged or kept after opening. If WhatsApp cannot be opened: "WhatsApp n'est pas installé sur cet appareil."
  - Buttons the staff member lacks permission for (from `StaffMe.permissions`) are hidden. A `401` anywhere returns to the login screen. Server error messages are shown in a banner.
  - `MainActivity.onCreate` sets `WindowManager.LayoutParams.FLAG_SECURE` so screenshots and screen recording are blocked.

- [ ] **Step 1: Create the app** — `cd mobile/apps && flutter create --org com.regisse.petitgombo --platforms android --project-name staff staff`; add the dependencies; remove the generated counter code.
- [ ] **Step 2: Write the failing tests**

```dart
// staff_api_test.dart
test('send returns the WhatsApp Uri from whatsapp_url', ...);
test('enrolments passes the status query and parses items', ...);
test('423 becomes ApiError(code: locked)', ...);

// staff_controller_test.dart
test('first sign-in registers the device then reports device_pending', ...);
test('sign-in on an active device stores tokens in memory and loads the queue', ...);
test('approve moves the item out of the pending list', ...);
test('401 during an action signs the user out', ...);

// screens_test.dart
testWidgets('login shows the French error for bad credentials', ...);
testWidgets('queue shows three tabs and the empty state', ...);
testWidgets('flagged request shows the warning and the French flag text', ...);
testWidgets('refuse dialog keeps the button disabled until a reason is typed', ...);
testWidgets('Envoyer par WhatsApp opens the returned URL once and does not display it', (t) async {
  ...
  expect(opened, [Uri.parse('https://wa.me/2250708091011?text=x')]);
  expect(find.textContaining('wa.me'), findsNothing);
});
testWidgets('send button is hidden without the send_enrolment_code permission', ...);
```
Write each in full.

- [ ] **Step 3: Run** `cd mobile/apps/staff && flutter test` — expected FAIL.
- [ ] **Step 4: Implement** the API class, session, controller, screens and the `FLAG_SECURE` line.
- [ ] **Step 5: Run** `flutter test && flutter analyze` — expected all pass, no issues. Add the staff app to the `mobile` CI job.
- [ ] **Step 6: End-to-end manual check.** Create a staff user in the `enrolment_agent` group in the web console; sign in on the staff app (expect the pending screen); activate the device in the web console; sign in again; apply from the jobber app; approve and send from the staff app; confirm WhatsApp opens with the French message; type the number in the jobber app and reach "Bienvenue". Record the result, or why it could not be run.
- [ ] **Step 7: Update the README** (running the staff app, activating a staff device, note that the staff app is distributed privately) and commit — `feat(mobile): staff app with enrolment queue and WhatsApp send`.

---

### Task 12: Production Docker deployment

**Files:**
- Create: `backend/Dockerfile`, `backend/.dockerignore`, `backend/entrypoint.sh`, `docker-compose.prod.yml`, `deploy/Caddyfile`, `.env.prod.example`, `docs/deployment.md`
- Modify: `backend/pyproject.toml` (add `gunicorn`, `whitenoise`), `backend/config/settings.py`, `.github/workflows/ci.yml`
- Test: `backend/tests/test_production_settings.py`

**Interfaces:**
- Produces one backend image (`python:3.13-slim`, non-root user, dependencies installed from `pyproject.toml`, `collectstatic` at build) used by three services with different commands: `web` (`gunicorn config.wsgi --bind 0.0.0.0:8000 --workers 3`), `worker` (`celery -A config worker`), `beat` (`celery -A config beat`). `entrypoint.sh` runs `migrate --noinput` only when `RUN_MIGRATIONS=1` (set on `web`).
- `docker-compose.prod.yml` services: `web`, `worker`, `beat`, `db` (`postgis/postgis:16-3.4`, named volume, not published to the host), `redis` (not published), `caddy` (`caddy:2`, ports 80/443, automatic HTTPS for `SITE_DOMAIN`, reverse proxy to `web:8000`). Healthchecks on `db`, `redis` and `web` (`/healthz`); `restart: unless-stopped`.
- Settings when `DEBUG` is false: `SECURE_SSL_REDIRECT`, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `SECURE_HSTS_SECONDS=31536000`, `SECURE_PROXY_SSL_HEADER=("HTTP_X_FORWARDED_PROTO", "https")`, `CSRF_TRUSTED_ORIGINS` from the environment, static files through WhiteNoise. Startup fails with a clear error if `SECRET_KEY` is missing or equals the development default while `DEBUG` is false.
- The client IP used for enrolment rate limits comes from the proxy's `X-Forwarded-For` only when `TRUST_PROXY_HEADERS=1`.

- [ ] **Step 1: Write the failing tests**

```python
def test_production_flags_are_on_when_debug_is_false(prod_settings):
    assert prod_settings.SECURE_SSL_REDIRECT and prod_settings.SESSION_COOKIE_SECURE and prod_settings.CSRF_COOKIE_SECURE
    assert prod_settings.SECURE_HSTS_SECONDS == 31536000

def test_default_secret_key_is_refused_in_production(...)      # loading settings raises ImproperlyConfigured
def test_forwarded_ip_is_used_only_when_proxy_is_trusted(...)
```
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the settings, Dockerfile, entrypoint, compose file and Caddyfile.
- [ ] **Step 4: Verify** — `.venv/bin/pytest -v`; `docker build -t petitgombo-backend backend`; `docker compose -f docker-compose.prod.yml --env-file .env.prod.example config` exits 0; start the stack locally with a throwaway env file and expect `curl -k https://localhost/healthz` (or the `web` container's `/healthz`) to return `{"status": "ok"}`. Add the `docker build` to CI.
- [ ] **Step 5: Write `docs/deployment.md`**: server requirements, first deployment, updating (pull, build, `up -d`), database backup and restore commands, what is still open (hosting location pending the data-protection decision, off-server backups, monitoring).
- [ ] **Step 6: Commit** — `feat: production Docker deployment`.

---

## Spec coverage of this plan

| Spec item | Task |
|-----------|------|
| Build step 1: repository layout, CI | 1 |
| Build step 1: threat model document | 2 (updated in 6, 9) |
| Build step 1: provider interfaces with mocks | 2 |
| Staff-approved device enrolment, steps 1 to 4 | 4, 5, 7 |
| Number generated by console, single use, per device, expiry, lock | 4 |
| Audit of who approved and who sent | 3, 4, 7 |
| Limits per number, device and network; multi-number flag | 4 |
| Plain status with response time | 5, 9 |
| "Never share this number" wording | 4, 9 |
| Sending behind `MessagingProvider` | 2, 7 |
| Device-bound key sign-in, rotating refresh tokens | 6, 8 |
| New device needs selfie match | 4 (gate only; match built in the verification plan) |
| Roles and permissions | 3, 6, 7 |
| Two user apps sharing packages | 8, 9 |
| Staff app with staff API, activated devices, screenshot blocking | 10, 11 |

Next plans, in order: verification and trust tiers (identity, proof of address, guarantor, trusted contacts); listings and moderation; bookings and payments including cash QR; safety (handshake, tracking, timers, SOS); console live board and incidents; website and learning videos; launch hardening.
