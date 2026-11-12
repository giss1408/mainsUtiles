import pytest

from apps.accounts.phones import InvalidPhone, normalise


@pytest.mark.parametrize(
    "raw",
    ["07 08 09 10 11", "0708091011", "+2250708091011", "00225 0708091011", "+225 07-08-09-10-11"],
)
def test_local_and_international_forms_normalise(raw):
    assert normalise(raw) == "+2250708091011"


@pytest.mark.parametrize("raw", ["", "12345", "+33612345678", "abcdefghij"])
def test_rejects_invalid_or_foreign_numbers(raw):
    with pytest.raises(InvalidPhone):
        normalise(raw)
