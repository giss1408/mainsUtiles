from apps.providers import registry
from apps.providers.mocks import MockIdentity, MockMap, MockMessaging, MockPayment


def test_whatsapp_link_strips_plus_and_encodes_text():
    link = registry.get_messaging().whatsapp_link("+2250708091011", "Bonjour : 123 456")
    assert link == "https://wa.me/2250708091011?text=Bonjour%20%3A%20123%20456"


def test_registry_loads_class_from_settings(settings):
    settings.MESSAGING_PROVIDER = "apps.providers.mocks.MockMessaging"
    assert isinstance(registry.get_messaging(), MockMessaging)
    assert isinstance(registry.get_payment(), MockPayment)
    assert isinstance(registry.get_identity(), MockIdentity)
    assert isinstance(registry.get_map(), MockMap)


def test_mock_sms_is_recorded():
    MockMessaging.outbox.clear()
    result = registry.get_messaging().send_sms("+2250708091011", "test")
    assert result.accepted
    assert MockMessaging.outbox == [("+2250708091011", "test")]


def test_mock_payment_collect_is_pending_then_verifiable():
    p = registry.get_payment()
    assert p.collect("ref-1", "+2250708091011", 5000).status == "pending"
    assert p.verify_webhook({"X-Mock-Signature": "valid"}, b"{}") is True
    assert p.verify_webhook({}, b"{}") is False


def test_mock_identity_and_map_return_usable_values():
    identity = registry.get_identity()
    session = identity.start_verification("user-1")
    assert identity.get_result(session).status == "pending"
    assert identity.match_selfie("user-1", b"img") is False
    assert registry.get_map().static_area_image_url(5.35, -4.01, 400).startswith("https://")
