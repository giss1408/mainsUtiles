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


@pytest.fixture
def bearer_for(db):
    """A real access token for a device, as an Authorization header value."""
    from apps.accounts.services.device_auth import issue_tokens

    return lambda device: f"Bearer {issue_tokens(device).access}"


@pytest.fixture
def householder_bearer(householder_key, bearer_for):
    return bearer_for(householder_key.device)


@pytest.fixture
def verifier(db):
    """A staff member allowed to review verifications and see their photos."""
    from django.contrib.auth.models import Group

    from apps.accounts.models import User

    user = User.objects.create_user(username="verifier", password="pw", role="staff", is_staff=True)
    user.groups.add(Group.objects.get(name="verification_agent"))
    return user


@pytest.fixture
def verifier_client(verifier):
    from django.test import Client

    client = Client()
    client.force_login(verifier)
    return client


def make_verified(user, jpeg):
    """Take a householder through all three verification steps; staff confirm each one."""
    from datetime import date

    from django.contrib.auth.models import Group
    from django.utils import timezone

    from apps.accounts.models import User
    from apps.verification.models import Status
    from apps.verification.services import review, submissions

    now = timezone.now()
    identity = submissions.submit_identity(
        user, document_type="cni", front=jpeg(0), back=jpeg(1), selfie=jpeg(2), captured_at=now
    )
    staff = User.objects.create_user(username=f"verif-{user.pk}", password="pw", role="staff", is_staff=True)
    staff.groups.add(Group.objects.get(name="verification_agent"))
    review.confirm_identity(
        identity,
        staff=staff,
        full_name="Kouassi Aya",
        date_of_birth=date(1990, 5, 17),
        document_number=f"CI {user.pk.hex[:9]}",
        document_expires_on=date(2035, 1, 1),
    )
    submissions.record_home_location(
        user, lat=5.3599, lng=-3.9871, accuracy_m=10, mock_location=False, captured_at=now
    )
    proof = submissions.submit_address_proof(
        user,
        document_type="facture_eau",
        photo=jpeg(10),
        commune="Cocody",
        quartier="Angré",
        captured_at=now,
    )
    review.confirm_address(
        proof,
        staff=staff,
        holder_name="Kouassi Aya",
        reference_number=f"CIE-{user.pk.hex[:8]}",
        issued_on=timezone.localdate(),
        name_matches=True,
        address_consistent=True,
        location_id=submissions_location_id(user),
    )
    assert proof.status == Status.CONFIRMED
    return user


@pytest.fixture
def verified_householder(db, settings, jpeg):
    """A householder at tier H1 with a confirmed address in Cocody, Angré."""
    from apps.accounts.models import User

    user = User.objects.create_user(phone="+2250505050505", role="householder")
    return make_verified(user, jpeg)


def submissions_location_id(user):
    """The position the staff member sees before confirming: the undecided one."""
    from apps.verification.models import UNDECIDED, HomeLocation

    return HomeLocation.objects.get(user=user, status__in=UNDECIDED).pk


@pytest.fixture
def payment_method(db):
    """An active Wave account: without one, nobody can apply or be accepted."""
    from apps.bookings.models import PaymentMethod

    return PaymentMethod.objects.create(
        provider="wave", number="+2250101010101", account_name="petitGombo", active=True
    )
