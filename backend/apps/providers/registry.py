"""Loads the provider classes named in settings."""

from django.conf import settings
from django.utils.module_loading import import_string

from .base import IdentityProvider, MapProvider, MessagingProvider, PaymentProvider


def get_messaging() -> MessagingProvider:
    return import_string(settings.MESSAGING_PROVIDER)()


def get_payment() -> PaymentProvider:
    return import_string(settings.PAYMENT_PROVIDER)()


def get_identity() -> IdentityProvider:
    return import_string(settings.IDENTITY_PROVIDER)()


def get_map() -> MapProvider:
    return import_string(settings.MAP_PROVIDER)()
