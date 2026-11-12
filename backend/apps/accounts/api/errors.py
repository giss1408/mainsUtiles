"""Maps service error codes to HTTP statuses and French messages."""

from rest_framework.response import Response

STATUS = {
    "invalid_phone": 400,
    "forbidden": 404,  # do not reveal that the application exists
    "rate_limited": 429,
    "invalid_state": 409,
    "selfie_required": 409,
    "code_invalid": 422,
    "code_replaced": 422,
    "code_expired": 422,
    "locked": 423,
    # Householder verification
    "photo_invalid": 400,
    "photo_too_large": 413,
    "document_type_invalid": 400,
    "commune_invalid": 400,
    "quartier_required": 400,
    "location_inaccurate": 422,
}

MESSAGES = {
    "invalid_phone": "Numéro de téléphone invalide.",
    "forbidden": "Demande introuvable.",
    "rate_limited": "Trop de demandes. Réessayez demain.",
    "invalid_state": "Cette demande ne peut plus être modifiée.",
    "selfie_required": "Une vérification par selfie est nécessaire avant d'approuver un nouvel appareil.",
    "code_invalid": "Numéro de confirmation incorrect.",
    "code_replaced": "Ce numéro a été remplacé. Utilisez le dernier message WhatsApp reçu.",
    "code_expired": "Ce numéro a expiré. Nous vous en envoyons un nouveau.",
    "locked": "Trop d'essais. Faites une nouvelle demande.",
    "photo_invalid": "Photo illisible. Reprenez la photo.",
    "photo_too_large": "Photo trop lourde. Reprenez la photo.",
    "document_type_invalid": "Type de document non accepté.",
    "commune_invalid": "Commune non desservie.",
    "quartier_required": "Indiquez le quartier.",
    "location_inaccurate": (
        "Position trop imprécise. Rapprochez-vous d'une fenêtre ou sortez, puis réessayez."
    ),
}


def error_response(code: str, status: int | None = None) -> Response:
    return Response(
        {"error": code, "message": MESSAGES.get(code, "")},
        status=status or STATUS.get(code, 400),
    )
