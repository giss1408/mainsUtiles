# Deployment

How to run petitGombo in production on one server with Docker. The mobile apps are built and
distributed separately; this covers the backend (API, staff web console, background tasks).

## What runs

`docker-compose.prod.yml` starts six containers:

| Service | Role | Reachable from the internet |
|---------|------|-----------------------------|
| `caddy` | HTTPS entry point; obtains and renews the certificate by itself | Yes, ports 80 and 443 |
| `web` | Django API and web console (gunicorn) | No, only through `caddy` |
| `worker` | Background tasks (Celery) | No |
| `beat` | Scheduler for periodic tasks, such as expiring old applications | No |
| `db` | PostgreSQL with PostGIS; data in the `pgdata` volume | No |
| `redis` | Cache, sign-in challenges, task queue | No |

`web`, `worker` and `beat` use the same image, built from `backend/Dockerfile`.

Two volumes hold data that cannot be rebuilt: `pgdata` (the database) and `verification_data`
(encrypted identity photos, mounted in `web` only).

## Server requirements

- A Linux server with a public IP address, 2 CPU cores and 4 GB of memory to start.
- Docker Engine with the Compose plugin (`docker compose version` must work).
- Ports 80 and 443 open to the internet. Nothing else needs to be open except SSH.
- A domain name whose DNS record points to the server. Caddy cannot obtain a certificate before this
  is in place.

## First deployment

1. Copy the repository to the server:

   ```bash
   git clone <repository-url> petitgombo && cd petitgombo
   ```

2. Create the settings file. It is git-ignored and must never be committed:

   ```bash
   cp .env.prod.example .env.prod
   chmod 600 .env.prod
   ```

   Fill in every value:

   | Variable | Value |
   |----------|-------|
   | `SITE_DOMAIN` | The public host name, for example `api.petitgombo.ci` |
   | `SECRET_KEY` | Output of `openssl rand -hex 48`. The backend refuses to start without it |
   | `POSTGRES_PASSWORD` | Output of `openssl rand -hex 24` |
   | `FIELD_ENCRYPTION_KEY` | Output of `python3 -c "import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())"`. Protects identity photos and sensitive fields. The backend refuses to start without it |
   | `OFFICIAL_WHATSAPP_NUMBER` | The WhatsApp Business number staff send confirmations from |

   **Keep a copy of `FIELD_ENCRYPTION_KEY` somewhere other than the server.** If it is lost, every
   identity photo and every encrypted field (names, document numbers, home positions) becomes
   unreadable, and nothing can recover them. Never change it once data exists: key rotation is not
   built.

   Changing `SECRET_KEY` later signs every user out. Changing `POSTGRES_PASSWORD` after the first
   start does not change the password inside the existing database.

3. Build and start:

   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
   ```

   The `web` container applies database migrations each time it starts.

4. Create the first administrator:

   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.prod exec web \
     python manage.py createsuperuser
   ```

5. Check:

   ```bash
   curl https://<SITE_DOMAIN>/healthz        # {"status": "ok"}
   docker compose -f docker-compose.prod.yml --env-file .env.prod ps
   ```

   Then open `https://<SITE_DOMAIN>/admin/` and sign in. Staff accounts and staff phones are set up
   as described in the README ("Staff app").

The mobile apps must be built with the production address:

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://<SITE_DOMAIN>
```

## Updating

```bash
git pull
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build
```

Take a database backup first (next section). To see what a service is doing:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod logs -f web
```

## Database backup and restore

Backup, to a compressed file on the server:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod exec -T db \
  pg_dump -U petitgombo -Fc petitgombo > backup-$(date +%Y%m%d-%H%M).dump
```

Restore. This replaces the current data with the content of the file; stop the services that write
to the database first:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod stop web worker beat
docker compose -f docker-compose.prod.yml --env-file .env.prod exec -T db \
  pg_restore -U petitgombo -d petitgombo --clean --if-exists < backup-YYYYMMDD-HHMM.dump
docker compose -f docker-compose.prod.yml --env-file .env.prod start web worker beat
```

A backup holds phone numbers and device records. Store it encrypted and limit who can read it.

### Identity photos

The database backup does not contain the identity photos. They are files in the `verification_data`
volume. Back it up at the same time:

```bash
docker run --rm -v petitgombo-prod_verification_data:/data:ro -v "$PWD":/backup alpine \
  tar czf /backup/verification-$(date +%Y%m%d-%H%M).tar.gz -C /data .
```

Restore into an empty volume, with `web` stopped:

```bash
docker run --rm -v petitgombo-prod_verification_data:/data -v "$PWD":/backup alpine \
  tar xzf /backup/verification-YYYYMMDD-HHMM.tar.gz -C /data
```

A complete backup is three things together: the database dump, the photo archive, and
`FIELD_ENCRYPTION_KEY`. The photo files are already encrypted, but the archive is useless without
the key and the key must not be stored next to it.

Never run `docker compose ... down -v` on the production server: `-v` deletes the database volume.

## How the security settings work

- With `DEBUG=0` (set by the compose file) the backend redirects HTTP to HTTPS, marks cookies as
  HTTPS-only and sends the HSTS header for one year.
- The backend trusts the `X-Forwarded-For` and `X-Forwarded-Proto` headers because
  `TRUST_PROXY_HEADERS=1` and only Caddy can reach it. Do not publish the `web` port, and do not put
  a second proxy or CDN in front without reviewing `backend/apps/core/net.py`: enrolment limits per
  network rely on the address Caddy reports.
- `/healthz` answers over plain HTTP so that the container healthcheck works from inside the network.

## Still open

- **Identity photos.** Until an identity provider is contracted, identity documents and selfies
  are stored by the backend. The lawful basis for holding them (data-protection registration,
  biometric processing) has not been confirmed and must be before launch.
- **Key rotation.** `FIELD_ENCRYPTION_KEY` cannot be changed once data exists.
- **Hosting location.** Where the server may be located depends on the data-protection decision
  (personal data of users in Côte d'Ivoire). No provider has been chosen.
- **Off-server backups.** The commands above write to the server's own disk. A scheduled backup
  copied to separate, encrypted storage, with a tested restore, is not set up.
- **Monitoring and alerts.** There is no uptime check, error reporting or log collection yet. The
  containers restart on failure, but nobody is told.
- **Real providers.** WhatsApp sending, payment, identity and map providers are still the built-in
  mocks; confirmations are sent by staff through WhatsApp links.
- **Single server.** Database, cache and application share one machine; there is no failover.
