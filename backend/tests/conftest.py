import pytest


@pytest.fixture(autouse=True)
def _local_cache(settings):
    settings.CACHES = {"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}}
    # Real password hashing is deliberately slow; tests sign in many times.
    settings.PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
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


@pytest.fixture
def enrol_device(db, staff_user):
    """Enrol a device through the service. Returns the DeviceKey with `.device` attached."""
    from django.utils import timezone

    from apps.accounts.models import DeviceEnrolmentRequest
    from apps.accounts.services import enrolment
    from tests.helpers import DeviceKey

    def _enrol(phone="0708091011", role="jobber"):
        key = DeviceKey()
        req = enrolment.apply(
            phone=phone,
            role=role,
            device_id=key.device_id,
            device_model="Tecno Spark",
            platform="android",
            public_key=key.public_key,
            client_token="tok",
        )
        if req.kind == "new_device":
            DeviceEnrolmentRequest.objects.filter(pk=req.pk).update(selfie_verified_at=timezone.now())
            req.refresh_from_db()
        enrolment.approve(req, staff=staff_user)
        code = enrolment.issue_code(req, staff=staff_user)
        key.device = enrolment.confirm(req, client_token="tok", code=code)
        return key

    return _enrol


@pytest.fixture
def enrolled(enrol_device):
    return enrol_device()


@pytest.fixture
def pending_request(db):
    import uuid

    from apps.accounts.services import enrolment

    return enrolment.apply(
        phone="0708091011",
        role="jobber",
        device_id=uuid.uuid4(),
        device_model="Tecno Spark",
        platform="android",
        public_key="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        client_token="tok",
    )


@pytest.fixture
def agent_client(staff_user):
    from django.test import Client

    client = Client()
    client.force_login(staff_user)
    return client


@pytest.fixture(autouse=True)
def _verification_storage(settings, tmp_path):
    settings.VERIFICATION_STORAGE_DIR = tmp_path / "verification"


@pytest.fixture
def householder_key(enrol_device):
    """An enrolled householder's device identity; `.device.user` is the householder."""
    return enrol_device(phone="0505050505", role="householder")


@pytest.fixture
def householder(householder_key):
    return householder_key.device.user


@pytest.fixture
def jpeg():
    """Bytes that start like a JPEG file. Each call to `jpeg(n)` gives a different image."""

    def _make(seed: int = 0, size: int = 200) -> bytes:
        return b"\xff\xd8\xff\xe0" + bytes([seed % 256]) * size + b"\xff\xd9"

    return _make
