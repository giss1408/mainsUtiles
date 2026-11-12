import pytest


@pytest.fixture(autouse=True)
def _local_cache(settings):
    settings.CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
    from django.core.cache import cache

    cache.clear()


@pytest.fixture
def staff_user(db):
    from django.contrib.auth.models import Group

    from apps.accounts.models import User

    user = User.objects.create_user(username="agent", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="enrolment_agent"))
    return user


@pytest.fixture
def make_device(db):
    import uuid

    from apps.accounts.models import Device

    def _make(user, **overrides):
        values = {
            "id": uuid.uuid4(),
            "user": user,
            "public_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "model": "Test Phone",
            "platform": "android",
        }
        values.update(overrides)
        return Device.objects.create(**values)

    return _make


@pytest.fixture
def api_client():
    from rest_framework.test import APIClient

    return APIClient()


@pytest.fixture
def device_key():
    from tests.helpers import DeviceKey

    return DeviceKey()


@pytest.fixture
def payload(device_key):
    return {
        "phone": "07 08 09 10 11",
        "role": "jobber",
        "device_id": device_key.device_id,
        "device_model": "Tecno Spark",
        "platform": "android",
        "public_key": device_key.public_key,
        "client_token": "tok",
    }


@pytest.fixture
def created(db, api_client, payload):
    """An application created through the API. Returns its JSON body."""
    response = api_client.post("/api/v1/enrolment/applications", payload, format="json")
    assert response.status_code == 201, response.content
    return response.json()
