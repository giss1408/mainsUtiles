def test_healthz_ok(client, db):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_settings_use_postgres(settings):
    assert settings.DATABASES["default"]["ENGINE"] == "django.db.backends.postgresql"
    assert settings.LANGUAGE_CODE == "fr"
    assert settings.TIME_ZONE == "Africa/Abidjan"
