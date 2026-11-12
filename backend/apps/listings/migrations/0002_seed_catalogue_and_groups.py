"""Starting catalogue and staff groups.

The categories, pay ranges and terms below are placeholders: staff replace them in the console.
"""

from django.contrib.auth.management import create_permissions
from django.db import migrations

CATEGORIES = [
    {
        "name": "Ménage",
        "duties": [
            "Balayer et laver les sols",
            "Dépoussiérer",
            "Nettoyer la cuisine",
            "Nettoyer les sanitaires",
            "Repasser le linge",
        ],
        "durations_minutes": [120, 180, 240],
        "suggested_pay_min": 2000,
        "suggested_pay_max": 5000,
    },
    {
        "name": "Cuisine",
        "duties": ["Préparer un repas", "Faire la vaisselle", "Ranger la cuisine"],
        "durations_minutes": [120, 180],
        "suggested_pay_min": 2000,
        "suggested_pay_max": 5000,
    },
    {
        "name": "Accompagnement d'une personne âgée",
        "duties": [
            "Tenir compagnie",
            "Aider à la marche",
            "Préparer un repas léger",
            "Accompagner pour une sortie à pied",
        ],
        "durations_minutes": [120, 240, 480],
        "suggested_pay_min": 3000,
        "suggested_pay_max": 8000,
    },
]

TERMS = {
    "appearance": ["jeune fille", "jolie", "belle", "célibataire"],
    "travel": ["voyage", "logé", "logée", "nourri logé", "étranger", "Europe"],
    "empty_home": ["maison vide", "personne à la maison", "seul à la maison"],
    "off_platform": ["WhatsApp", "appelle", "appelez", "mon numéro"],
}

GROUPS = {
    "offer_moderator": ["moderate_offer", "view_offer"],
    "catalogue_manager": [
        f"{action}_{model}"
        for model in ("offercategory", "moderationterm")
        for action in ("add", "change", "delete", "view")
    ],
}


def seed(apps, schema_editor):
    OfferCategory = apps.get_model("listings", "OfferCategory")
    ModerationTerm = apps.get_model("listings", "ModerationTerm")
    for position, values in enumerate(CATEGORIES):
        OfferCategory.objects.get_or_create(name=values["name"], defaults={**values, "position": position})
    for kind, texts in TERMS.items():
        for text in texts:
            ModerationTerm.objects.get_or_create(text=text, kind=kind)

    # Permissions are normally created after all migrations; create them now so the groups can hold them.
    app_config = apps.get_app_config("listings")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None
    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    for name, codenames in GROUPS.items():
        group, _ = Group.objects.get_or_create(name=name)
        group.permissions.add(
            *Permission.objects.filter(content_type__app_label="listings", codename__in=codenames)
        )


def unseed(apps, schema_editor):
    apps.get_model("auth", "Group").objects.filter(name__in=GROUPS).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("listings", "0001_initial"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(seed, unseed)]
