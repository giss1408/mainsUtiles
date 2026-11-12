"""petitGombo settings. Every value comes from the environment with a development default."""

from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR.parent / ".env")

DEV_SECRET_KEY = "dev-insecure-change-me"

DEBUG = env.bool("DEBUG", default=True)
SECRET_KEY = env.str("SECRET_KEY", default=DEV_SECRET_KEY)
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=["localhost", "127.0.0.1", "10.0.2.2", "testserver"])

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
CELERY_BEAT_SCHEDULE = {}

LANGUAGE_CODE = "fr"
TIME_ZONE = "Africa/Abidjan"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"

REST_FRAMEWORK = {
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": ["rest_framework.parsers.JSONParser"],
    "UNAUTHENTICATED_USER": None,
}
SPECTACULAR_SETTINGS = {
    "TITLE": "petitGombo API",
    "VERSION": "1",
    "SERVE_INCLUDE_SCHEMA": False,
}

# External providers (dotted path to a class implementing apps.providers.base).
MESSAGING_PROVIDER = env.str("MESSAGING_PROVIDER", default="apps.providers.mocks.MockMessaging")
PAYMENT_PROVIDER = env.str("PAYMENT_PROVIDER", default="apps.providers.mocks.MockPayment")
IDENTITY_PROVIDER = env.str("IDENTITY_PROVIDER", default="apps.providers.mocks.MockIdentity")
MAP_PROVIDER = env.str("MAP_PROVIDER", default="apps.providers.mocks.MockMap")

# Phone numbers
ALLOWED_PHONE_REGIONS = env.list("ALLOWED_PHONE_REGIONS", default=["CI"])
