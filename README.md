# petitGombo

Safety-first mini-job marketplace. The product specification is in [skill.md](skill.md);
implementation plans are in [docs/superpowers/plans](docs/superpowers/plans).

## Layout

- `backend/` — Django API, staff web console (Django admin), Celery tasks.
- `mobile/packages/petitgombo_core` — shared Flutter code.
- `mobile/apps/householder`, `mobile/apps/jobber`, `mobile/apps/staff` — the three apps.
- `docs/threat-model.md` — threats, controls and their test status.
- `docs/deployment.md` — running the backend in production with Docker.

## Prerequisites

Docker, Python 3.13, Flutter 3.24 or later.

## Backend: first run

```bash
cp .env.example .env
docker compose up -d                      # PostgreSQL and Redis
cd backend
python3.13 -m venv .venv
.venv/bin/pip install -e '.[dev]'
.venv/bin/python manage.py migrate
.venv/bin/python manage.py createsuperuser
.venv/bin/python manage.py runserver 0.0.0.0:8000
```

The web console is at http://localhost:8000/admin/ and the API schema at
http://localhost:8000/api/schema/.

## Tests and lint

```bash
cd backend
.venv/bin/pytest
.venv/bin/ruff check .
```

## Open decisions

These are not settled by the code and must be supplied by the business:

- Payment provider(s) and whether holding funds needs a licensed partner.
- Identity verification provider.
- SMS and call provider; the official WhatsApp Business number.
- Data-protection registration (ARTCI), biometric processing and hosting location.
- Labour status of mini-jobbers, insurance cover.
- Safety desk staffing and hours, incident protocol, police contact, emergency numbers.
- Trademark, domain and store availability of the name "petitGombo".

## Trying the enrolment flow by hand

Create an application as the app would:

```bash
curl -X POST http://localhost:8000/api/v1/enrolment/applications \
  -H 'Content-Type: application/json' \
  -d '{"phone":"07 08 09 10 11","role":"jobber","device_id":"11111111-1111-4111-8111-111111111111","device_model":"curl","platform":"android","public_key":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=","client_token":"smoke-token"}'
```

Then open the web console, go to "Demandes d'enrôlement", approve the application and press
"Envoyer par WhatsApp". Staff members need the `enrolment_agent` group (superusers have every right).

## Mobile apps

Flutter 3.24 or later. The shared code is in `mobile/packages/petitgombo_core`; each app is a thin
entry point.

| App | Folder | Android id |
|-----|--------|------------|
| petitGombo (householders) | `mobile/apps/householder` | `com.regisse.petitgombo` |
| petitGombo Jobber | `mobile/apps/jobber` | `com.regisse.petitgombo.jobber` |
| petitGombo Staff | `mobile/apps/staff` | `com.regisse.petitgombo.staff` |

```bash
cd mobile/apps/jobber            # or mobile/apps/householder, mobile/apps/staff
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` is the host machine as seen from the Android emulator (the default when the option is
omitted). On a real phone use the computer's address on the local network and start the backend with
`runserver 0.0.0.0:8000`. Debug builds allow plain HTTP for this; release builds must use HTTPS.

Tests and analysis, in each of the four Dart packages (the core package and the three apps):

```bash
flutter test
flutter analyze
```

### Staff app

The staff app shows the enrolment queue (approve, refuse, hold, send the confirmation number by
WhatsApp). It is distributed privately to the operations team, never through a public store, and it
blocks screenshots and screen recording.

A staff member signs in with a username, a password and a phone that an administrator has activated:

1. In the web console (`/admin/`), a superuser creates the staff account under "Utilisateurs" with the
   role "Personnel", "Statut équipe" ticked, and the `enrolment_agent` group.
2. The staff member opens the staff app and signs in. The first attempt registers the phone and shows
   "Appareil en attente d'activation par un administrateur."
3. The superuser opens "Appareils du personnel" in the web console, ticks the phone, and runs the
   action "Activer". A staff member has one active phone: activating a new one revokes the previous.
   "Révoquer" cuts a phone off immediately; a revoked phone registers again as a new device.
4. The staff member signs in again and reaches the queue.

The session is kept in memory only: closing the app signs out, and so do 12 hours without use. After 5
wrong passwords the account is locked for 15 minutes (`STAFF_LOGIN_MAX_FAILURES`,
`STAFF_LOGIN_LOCK_MINUTES`).
