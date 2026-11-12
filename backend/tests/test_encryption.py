import pytest
from cryptography.fernet import Fernet, InvalidToken

from apps.verification.services.encryption import (
    decrypt_bytes,
    decrypt_text,
    encrypt_bytes,
    encrypt_text,
    keyed_hash,
    normalise_number,
)


def test_bytes_round_trip_and_ciphertext_differs():
    token = encrypt_bytes(b"photo")
    assert token != b"photo" and decrypt_bytes(token) == b"photo"


def test_text_round_trip_and_two_encryptions_differ():
    assert decrypt_text(encrypt_text("Kouassi Aya")) == "Kouassi Aya"
    assert encrypt_text("x") != encrypt_text("x")
    assert encrypt_text("") == "" and decrypt_text("") == ""


def test_same_number_typed_differently_hashes_the_same():
    assert normalise_number(" ci 001-234.567 ") == "CI001234567"
    assert keyed_hash("CI 001-234 567") == keyed_hash("ci001234567")
    assert keyed_hash("ci001234567") != keyed_hash("ci001234568")
    assert "001234567" not in keyed_hash("ci001234567")
    assert len(keyed_hash("x")) == 64


def test_wrong_key_cannot_decrypt(settings):
    token = encrypt_bytes(b"photo")
    hashed = keyed_hash("ci001234567")
    settings.FIELD_ENCRYPTION_KEY = Fernet.generate_key().decode()
    with pytest.raises(InvalidToken):
        decrypt_bytes(token)
    assert keyed_hash("ci001234567") != hashed
