import importlib.util
from pathlib import Path

import pytest
from django.core.exceptions import ImproperlyConfigured
from django.test import RequestFactory

from apps.core.net import client_ip

SETTINGS_FILE = Path(__file__).resolve().parent.parent / "config" / "settings.py"


def load_settings(monkeypatch, **env):
    """Load config/settings.py afresh under the given environment."""
    for name, value in env.items():
        if value is None:
            monkeypatch.delenv(name, raising=False)
        else:
            monkeypatch.setenv(name, value)
    spec = importlib.util.spec_from_file_location("settings_under_test", SETTINGS_FILE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def prod_settings(monkeypatch):
    return load_settings(
        monkeypatch,
        DEBUG="0",
        SECRET_KEY="a-long-random-production-secret-key-for-tests",
        ALLOWED_HOSTS="petitgombo.example",
        CSRF_TRUSTED_ORIGINS="https://petitgombo.example",
    )


def test_production_flags_are_on_when_debug_is_false(prod_settings):
    assert prod_settings.DEBUG is False
    assert prod_settings.SECURE_SSL_REDIRECT
    assert prod_settings.SESSION_COOKIE_SECURE and prod_settings.CSRF_COOKIE_SECURE
    assert prod_settings.SECURE_HSTS_SECONDS == 31536000
    assert prod_settings.SECURE_PROXY_SSL_HEADER == ("HTTP_X_FORWARDED_PROTO", "https")
    assert prod_settings.CSRF_TRUSTED_ORIGINS == ["https://petitgombo.example"]
    assert prod_settings.ALLOWED_HOSTS == ["petitgombo.example"]


def test_healthz_is_not_redirected_to_https(prod_settings):
    # The container healthcheck calls it over plain HTTP from inside the network.
    assert any("healthz" in pattern for pattern in prod_settings.SECURE_REDIRECT_EXEMPT)


def test_static_files_are_served_by_whitenoise_in_production(prod_settings):
    middleware = prod_settings.MIDDLEWARE
    assert "whitenoise.middleware.WhiteNoiseMiddleware" in middleware
    assert middleware.index("whitenoise.middleware.WhiteNoiseMiddleware") == 1
    assert "whitenoise" in prod_settings.STORAGES["staticfiles"]["BACKEND"]


def test_development_keeps_the_flags_off(monkeypatch):
    dev = load_settings(monkeypatch, DEBUG="1", SECRET_KEY=None)
    assert dev.SECURE_SSL_REDIRECT is False
    assert dev.SESSION_COOKIE_SECURE is False
    assert dev.SECURE_HSTS_SECONDS == 0


@pytest.mark.parametrize("secret", [None, "dev-insecure-change-me-before-any-real-use", ""])
def test_default_secret_key_is_refused_in_production(monkeypatch, secret):
    with pytest.raises(ImproperlyConfigured, match="SECRET_KEY"):
        load_settings(monkeypatch, DEBUG="0", SECRET_KEY=secret)


def test_forwarded_ip_is_used_only_when_proxy_is_trusted(settings):
    request = RequestFactory().get("/", REMOTE_ADDR="172.18.0.5", HTTP_X_FORWARDED_FOR="6.6.6.6, 41.207.1.2")
    settings.TRUST_PROXY_HEADERS = False
    assert client_ip(request) == "172.18.0.5"
    settings.TRUST_PROXY_HEADERS = True
    # The last entry is the one our own proxy wrote; earlier ones can be forged by the client.
    assert client_ip(request) == "41.207.1.2"


def test_trusted_proxy_without_the_header_falls_back_to_the_peer(settings):
    settings.TRUST_PROXY_HEADERS = True
    assert client_ip(RequestFactory().get("/", REMOTE_ADDR="172.18.0.5")) == "172.18.0.5"
