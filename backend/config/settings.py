"""petitGombo settings. Every value comes from the environment with a development default."""

from pathlib import Path

import environ
from cryptography.fernet import Fernet
from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR.parent / ".env")

DEV_SECRET_KEY = "dev-insecure-change-me-before-any-real-use"

DEBUG = env.bool("DEBUG", default=True)
SECRET_KEY = env.str("SECRET_KEY", default=DEV_SECRET_KEY)
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=["localhost", "127.0.0.1", "10.0.2.2", "testserver"])

if not DEBUG and SECRET_KEY in ("", DEV_SECRET_KEY):
    raise ImproperlyConfigured("SECRET_KEY must be set to a private random value when DEBUG is off.")

# Encrypts identity photos and sensitive fields. Losing it makes them unreadable.
DEV_FIELD_ENCRYPTION_KEY = "ZGV2LW9ubHktcGV0aXRnb21iby1maWVsZC1rZXktMDA="
# An empty value (a line left blank in .env) means "use the development key".
FIELD_ENCRYPTION_KEY = env.str("FIELD_ENCRYPTION_KEY", default="") or DEV_FIELD_ENCRYPTION_KEY
if not DEBUG:
    if FIELD_ENCRYPTION_KEY == DEV_FIELD_ENCRYPTION_KEY:
        raise ImproperlyConfigured(
            "FIELD_ENCRYPTION_KEY must be set to a private Fernet key when DEBUG is off."
        )
    try:
        Fernet(FIELD_ENCRYPTION_KEY.encode())
    except ValueError as exc:
        # Better to refuse to start than to fail on the first photo a user sends.
        raise ImproperlyConfigured(
            "FIELD_ENCRYPTION_KEY is not a valid Fernet key (32 bytes, url-safe base64)."
        ) from exc

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "drf_spectacular",
    "apps.core",
    "apps.providers",
    "apps.audit",
    "apps.accounts",
    "apps.verification",
    "apps.listings",
    "apps.bookings",
]

AUTH_USER_MODEL = "accounts.User"

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.locale.LocaleMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

DATABASES = {
    "default": env.db_url(
        "DATABASE_URL",
        default="postgres://petitgombo:petitgombo@localhost:5432/petitgombo",
        engine="django.db.backends.postgresql",
    ),
}
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REDIS_URL = env.str("REDIS_URL", default="redis://localhost:6379/0")
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.redis.RedisCache",
        "LOCATION": REDIS_URL,
    },
}

CELERY_BROKER_URL = REDIS_URL
CELERY_TIMEZONE = "Africa/Abidjan"
CELERY_BEAT_SCHEDULE = {
    "expire-stale-enrolments": {
        "task": "apps.accounts.tasks.expire_stale_enrolments",
        "schedule": 3600.0,
    },
    "expire-address-proofs": {
        "task": "apps.verification.tasks.expire_address_proofs",
        "schedule": 3600.0,
    },
    "expire-guarantors": {
        "task": "apps.verification.tasks.expire_guarantors",
        "schedule": 3600.0,
    },
    "expire-unpaid-bookings": {
        "task": "apps.bookings.tasks.expire_unpaid_bookings",
        "schedule": 3600.0,
    },
    "close-stale-applications": {
        "task": "apps.bookings.tasks.close_stale_applications",
        "schedule": 3600.0,
    },
    "apply-contact-replacements": {
        "task": "apps.verification.tasks.apply_contact_replacements",
        "schedule": 3600.0,
    },
    "tidy-offers": {
        "task": "apps.listings.tasks.tidy_offers",
        "schedule": 900.0,
    },
}

LANGUAGE_CODE = "fr"
TIME_ZONE = "Africa/Abidjan"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

# Production (DEBUG off): HTTPS everywhere behind the reverse proxy, static files from the app itself.
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])
SECURE_SSL_REDIRECT = not DEBUG
SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG
SECURE_HSTS_SECONDS = 0 if DEBUG else 31536000
# The container healthcheck calls /healthz over plain HTTP from inside the private network.
SECURE_REDIRECT_EXEMPT = [r"^healthz$"]
if not DEBUG:
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    MIDDLEWARE.insert(1, "whitenoise.middleware.WhiteNoiseMiddleware")
    STORAGES = {
        "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
        "staticfiles": {"BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage"},
    }

# Read the client address from X-Forwarded-For. Only behind a reverse proxy that sets it,
# with the application port closed to everything else.
TRUST_PROXY_HEADERS = env.bool("TRUST_PROXY_HEADERS", default=False)

REST_FRAMEWORK = {
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    "UNAUTHENTICATED_USER": None,
    "DEFAULT_AUTHENTICATION_CLASSES": ["apps.accounts.authentication.DeviceJWTAuthentication"],
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
}
SPECTACULAR_SETTINGS = {
    "TITLE": "petitGombo API",
    "VERSION": "1",
    "SERVE_INCLUDE_SCHEMA": False,
    "SERVE_PERMISSIONS": ["rest_framework.permissions.AllowAny"],
    "SERVE_AUTHENTICATION": [],
}

# External providers (dotted path to a class implementing apps.providers.base).
MESSAGING_PROVIDER = env.str("MESSAGING_PROVIDER", default="apps.providers.mocks.MockMessaging")
PAYMENT_PROVIDER = env.str("PAYMENT_PROVIDER", default="apps.providers.mocks.MockPayment")
IDENTITY_PROVIDER = env.str("IDENTITY_PROVIDER", default="apps.providers.staff_review.StaffReviewIdentity")
MAP_PROVIDER = env.str("MAP_PROVIDER", default="apps.providers.mocks.MockMap")

# Phone numbers
ALLOWED_PHONE_REGIONS = env.list("ALLOWED_PHONE_REGIONS", default=["CI"])

# Device enrolment
ENROLMENT_CODE_TTL_MINUTES = env.int("ENROLMENT_CODE_TTL_MINUTES", default=60)
ENROLMENT_CODE_MAX_ATTEMPTS = env.int("ENROLMENT_CODE_MAX_ATTEMPTS", default=5)
ENROLMENT_MAX_PER_PHONE_PER_DAY = env.int("ENROLMENT_MAX_PER_PHONE_PER_DAY", default=3)
ENROLMENT_MAX_PER_DEVICE_PER_DAY = env.int("ENROLMENT_MAX_PER_DEVICE_PER_DAY", default=3)
ENROLMENT_MAX_PER_IP_PER_DAY = env.int("ENROLMENT_MAX_PER_IP_PER_DAY", default=10)
ENROLMENT_APPLICATION_TTL_DAYS = env.int("ENROLMENT_APPLICATION_TTL_DAYS", default=7)
ENROLMENT_RESPONSE_HOURS = env.int("ENROLMENT_RESPONSE_HOURS", default=24)

# Sign-in and tokens
ACCESS_TOKEN_TTL_MINUTES = env.int("ACCESS_TOKEN_TTL_MINUTES", default=15)
REFRESH_TOKEN_TTL_DAYS = env.int("REFRESH_TOKEN_TTL_DAYS", default=30)
AUTH_CHALLENGE_TTL_SECONDS = env.int("AUTH_CHALLENGE_TTL_SECONDS", default=120)
STAFF_ACCESS_TOKEN_TTL_MINUTES = env.int("STAFF_ACCESS_TOKEN_TTL_MINUTES", default=10)
STAFF_REFRESH_TOKEN_TTL_HOURS = env.int("STAFF_REFRESH_TOKEN_TTL_HOURS", default=12)
STAFF_LOGIN_MAX_FAILURES = env.int("STAFF_LOGIN_MAX_FAILURES", default=5)
STAFF_LOGIN_LOCK_MINUTES = env.int("STAFF_LOGIN_LOCK_MINUTES", default=15)

# Householder verification
MINIMUM_AGE_YEARS = env.int("MINIMUM_AGE_YEARS", default=18)
ADDRESS_PROOF_MAX_AGE_MONTHS = env.int("ADDRESS_PROOF_MAX_AGE_MONTHS", default=3)
ADDRESS_PROOF_VALID_MONTHS = env.int("ADDRESS_PROOF_VALID_MONTHS", default=12)
HOME_PIN_MAX_ACCURACY_M = env.int("HOME_PIN_MAX_ACCURACY_M", default=50)
VERIFICATION_PHOTO_MAX_BYTES = env.int("VERIFICATION_PHOTO_MAX_BYTES", default=3_000_000)
VERIFICATION_REVIEW_HOURS = env.int("VERIFICATION_REVIEW_HOURS", default=24)
VERIFICATION_STORAGE_DIR = Path(
    env.str("VERIFICATION_STORAGE_DIR", default="") or BASE_DIR / "verification_storage"
)
# Uploaded photos stay in memory until they are encrypted: Django must never spool them to a
# temporary file in plain text. A request larger than this limit carries no usable file.
FILE_UPLOAD_HANDLERS = ["django.core.files.uploadhandler.MemoryFileUploadHandler"]
FILE_UPLOAD_MAX_MEMORY_SIZE = 3 * VERIFICATION_PHOTO_MAX_BYTES + 1_000_000
SERVICE_COMMUNES = env.list(
    "SERVICE_COMMUNES",
    default=[
        "Abobo",
        "Adjamé",
        "Anyama",
        "Attécoubé",
        "Bingerville",
        "Cocody",
        "Koumassi",
        "Marcory",
        "Plateau",
        "Port-Bouët",
        "Songon",
        "Treichville",
        "Yopougon",
    ],
)
IDENTITY_DOCUMENT_TYPES = env.list(
    "IDENTITY_DOCUMENT_TYPES", default=["cni", "passport", "carte_consulaire", "permis"]
)
ADDRESS_PROOF_TYPES = env.list(
    "ADDRESS_PROOF_TYPES", default=["facture_eau", "facture_electricite", "certificat_residence"]
)

# Jobber verification
GUARANTOR_DOCUMENT_TYPES = env.list(
    "GUARANTOR_DOCUMENT_TYPES",
    default=["facture_eau", "facture_electricite", "certificat_residence", "abonnement_prepaye"],
)
GUARANTOR_BILL_MAX_AGE_MONTHS = env.int("GUARANTOR_BILL_MAX_AGE_MONTHS", default=3)
GUARANTOR_VALID_MONTHS = env.int("GUARANTOR_VALID_MONTHS", default=12)
# How many jobbers one bill (customer number) may vouch for.
GUARANTOR_MAX_JOBBERS = env.int("GUARANTOR_MAX_JOBBERS", default=3)
# Steps a jobber must have confirmed to reach tier J1.
JOBBER_REQUIRED_STEPS = env.list(
    "JOBBER_REQUIRED_STEPS", default=["identity", "guarantor", "trusted_contact", "briefing"]
)
# Trusted contacts: a code is sent by staff on WhatsApp; a contact is replaced, never removed.
TRUSTED_CONTACTS_MAX = env.int("TRUSTED_CONTACTS_MAX", default=2)
TRUSTED_CONTACT_CODE_TTL_MINUTES = env.int("TRUSTED_CONTACT_CODE_TTL_MINUTES", default=1440)
TRUSTED_CONTACT_CODE_MAX_ATTEMPTS = env.int("TRUSTED_CONTACT_CODE_MAX_ATTEMPTS", default=5)
# Wait between two requests for a code.
TRUSTED_CONTACT_RESEND_SECONDS = env.int("TRUSTED_CONTACT_RESEND_SECONDS", default=600)
TRUSTED_CONTACT_MAX_ADDS_PER_DAY = env.int("TRUSTED_CONTACT_MAX_ADDS_PER_DAY", default=3)
# A replaced contact stays this long after its old number has been warned.
TRUSTED_CONTACT_CHANGE_DELAY_HOURS = env.int("TRUSTED_CONTACT_CHANGE_DELAY_HOURS", default=72)

# Job offers. Categories and moderation terms are edited in the console, not here.
OFFER_EARLIEST_START = env.str("OFFER_EARLIEST_START", default="06:00")
OFFER_LATEST_END = env.str("OFFER_LATEST_END", default="19:00")
OFFER_MIN_PAY_XOF = env.int("OFFER_MIN_PAY_XOF", default=1000)
OFFER_MAX_PAY_XOF = env.int("OFFER_MAX_PAY_XOF", default=100000)
# Pay above this many times the category's suggested maximum is looked at by staff.
OFFER_PAY_FLAG_FACTOR = env.float("OFFER_PAY_FLAG_FACTOR", default=2)
OFFER_MAX_DAYS_AHEAD = env.int("OFFER_MAX_DAYS_AHEAD", default=30)
OFFER_MAX_OPEN_PER_HOUSEHOLDER = env.int("OFFER_MAX_OPEN_PER_HOUSEHOLDER", default=3)

# Applications: how many a jobber may have waiting, how many an offer may collect, message length.
APPLICATIONS_MAX_OPEN = env.int("APPLICATIONS_MAX_OPEN", default=5)
APPLICATIONS_MAX_PER_OFFER = env.int("APPLICATIONS_MAX_PER_OFFER", default=20)
APPLICATION_MESSAGE_MAX = env.int("APPLICATION_MESSAGE_MAX", default=200)

# Payment and address release: how long to pay, when the exact pin is shown, the platform fee, and the
# notice after which a cancellation is no longer free (a business decision; the fee is 0 until set).
PAYMENT_WINDOW_HOURS = env.int("PAYMENT_WINDOW_HOURS", default=12)
ADDRESS_RELEASE_HOURS = env.int("ADDRESS_RELEASE_HOURS", default=3)
PLATFORM_FEE_PERCENT = env.int("PLATFORM_FEE_PERCENT", default=0)
CANCEL_FREE_HOURS = env.int("CANCEL_FREE_HOURS", default=24)
PAYMENT_REVIEW_LATE_HOURS = env.int("PAYMENT_REVIEW_LATE_HOURS", default=2)

# The job and after: the householder's time to confirm, how early the jobber may check in, how far
# from the home pin a check-in is flagged, the grace before an unfinished job goes to staff, and the
# reviews' window and length.
RELEASE_TIMEOUT_HOURS = env.int("RELEASE_TIMEOUT_HOURS", default=24)
CHECKIN_EARLY_MINUTES = env.int("CHECKIN_EARLY_MINUTES", default=30)
CHECKIN_FLAG_METERS = env.int("CHECKIN_FLAG_METERS", default=500)
CHECKOUT_GRACE_HOURS = env.int("CHECKOUT_GRACE_HOURS", default=6)
REVIEW_WINDOW_DAYS = env.int("REVIEW_WINDOW_DAYS", default=7)
REVIEW_COMMENT_MAX = env.int("REVIEW_COMMENT_MAX", default=300)
OFFER_NOTE_MAX_LENGTH = env.int("OFFER_NOTE_MAX_LENGTH", default=300)
OFFER_REVIEW_HOURS = env.int("OFFER_REVIEW_HOURS", default=24)

# Staff console
OFFICIAL_WHATSAPP_NUMBER = env.str("OFFICIAL_WHATSAPP_NUMBER", default="")
