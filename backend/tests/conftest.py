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
