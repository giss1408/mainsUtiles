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
    # Job offers
    "verification_required": 403,
    "category_invalid": 400,
    "duties_invalid": 400,
    "time_invalid": 400,
    "duration_invalid": 400,
    "pay_invalid": 400,
    "note_too_long": 400,
    "too_many_offers": 409,
    "reason_required": 400,
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
    # Shown to staff in the console when a verification decision breaks a rule.
    "under_age": "La personne a moins de 18 ans. La vérification ne peut pas être confirmée.",
    "document_expired": "Le document d'identité est expiré.",
    "duplicate_document": "Ce numéro de document est déjà utilisé par un autre compte.",
    "identity_not_confirmed": "Confirmez d'abord l'identité de cette personne.",
    "location_missing": "La personne n'a pas encore enregistré la position de son domicile.",
    "location_changed": "La position du domicile a changé. Revérifiez avant de confirmer.",
    "proof_too_old": "Le justificatif est trop ancien ou sa date est dans le futur.",
    "duplicate_reference": "Ce justificatif est déjà utilisé par un autre compte.",
    "checks_required": "Cochez les deux vérifications avant de confirmer.",
    "reason_required": "Le motif est obligatoire.",
    "field_required": "Remplissez tous les champs.",
    # Job offers
    "verification_required": "Faites vérifier votre compte pour publier une offre.",
    "category_invalid": "Cette catégorie n'est plus disponible.",
    "duties_invalid": "Choisissez au moins une tâche de la liste.",
    "time_invalid": "Choisissez une date à venir, entre 06:00 et 19:00.",
    "duration_invalid": "Choisissez une durée proposée.",
    "pay_invalid": "Indiquez un montant entre 1 000 et 100 000 FCFA.",
    "note_too_long": "La précision est trop longue.",
    "too_many_offers": "Vous avez déjà 3 offres en cours. Retirez-en une pour en publier une autre.",
}


def error_response(code: str, status: int | None = None) -> Response:
    return Response(
        {"error": code, "message": MESSAGES.get(code, "")},
        status=status or STATUS.get(code, 400),
    )
