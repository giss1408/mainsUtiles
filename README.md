# petitGombo

Safety-first mini-job marketplace. The product specification is in [skill.md](skill.md);
implementation plans are in [docs/superpowers/plans](docs/superpowers/plans).

## Layout

- `backend/` — Django API, staff web console (Django admin), Celery tasks.
- `mobile/packages/petitgombo_core` — shared Flutter code.
- `mobile/apps/householder`, `mobile/apps/jobber`, `mobile/apps/staff` — the three apps.
- `docs/threat-model.md` — threats, controls and their test status.

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
