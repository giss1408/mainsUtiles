"""Placeholder briefing cards, the group that edits them, and the staff rights on trusted contacts.

The three cards are placeholders: the product owner replaces them in the console before launch.
"""

from django.contrib.auth.management import create_permissions
from django.db import migrations

CARDS = [
    {
        "title": "Avant de partir",
        "body": "Avant chaque mission, dis à ta personne de confiance où tu vas et à quelle heure.",
        "question": "Que fais-tu avant de partir en mission ?",
        "choices": [
            "Je garde l'adresse pour moi",
            "Je préviens ma personne de confiance",
            "J'attends d'être arrivé(e)",
        ],
        "correct_index": 1,
        "explanation": "Une personne qui sait où tu es peut réagir vite si quelque chose ne va pas.",
    },
    {
        "title": "Tout reste dans l'application",
        "body": "Les échanges et les paiements passent par l'application. Ne donne pas ton numéro et ne "
        "paie jamais en dehors.",
        "question": "Le ménage te propose de continuer sur WhatsApp et de payer en main propre. Que fais-tu ?",
        "choices": [
            "J'accepte, c'est plus simple",
            "Je refuse et je préviens l'équipe",
            "Je donne mon numéro seulement",
        ],
        "correct_index": 1,
        "explanation": "Hors de l'application, plus rien ne te protège : ni l'historique, ni le paiement.",
    },
    {
        "title": "Tu peux partir",
        "body": "Si tu te sens mal à l'aise, tu as le droit de quitter les lieux, même au milieu de la "
        "mission, puis de prévenir l'équipe.",
        "question": "Tu te sens en danger pendant une mission. Que fais-tu ?",
        "choices": [
            "Je reste pour finir le travail",
            "Je pars et je préviens l'équipe",
            "Je ne dis rien à personne",
        ],
        "correct_index": 1,
        "explanation": "Ta sécurité passe avant la mission. Personne ne te reprochera d'être parti(e).",
    },
]

BRIEFING_GROUP = "briefing_manager"
AGENT_GROUP = "verification_agent"


def seed(apps, schema_editor):
    BriefingCard = apps.get_model("verification", "BriefingCard")
    for position, values in enumerate(CARDS):
        BriefingCard.objects.get_or_create(title=values["title"], defaults={**values, "position": position})

    app_config = apps.get_app_config("verification")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None
    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")

    manager, _ = Group.objects.get_or_create(name=BRIEFING_GROUP)
    manager.permissions.add(
        *Permission.objects.filter(
            content_type__app_label="verification",
            codename__in=[f"{action}_briefingcard" for action in ("add", "change", "delete", "view")],
        )
    )
    agent = Group.objects.get(name=AGENT_GROUP)
    agent.permissions.add(
        *Permission.objects.filter(
            content_type__app_label="verification",
            codename__in=["send_contact_code", "view_trustedcontact"],
        )
    )


def unseed(apps, schema_editor):
    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    Group.objects.filter(name=BRIEFING_GROUP).delete()
    agent = Group.objects.filter(name=AGENT_GROUP).first()
    if agent:
        agent.permissions.remove(
            *Permission.objects.filter(codename__in=["send_contact_code", "view_trustedcontact"])
        )
    apps.get_model("verification", "BriefingCard").objects.filter(
        title__in=[card["title"] for card in CARDS]
    ).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("verification", "0005_trusted_contacts_briefing"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(seed, unseed)]
