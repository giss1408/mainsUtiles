from django.contrib.auth.management import create_permissions
from django.db import migrations

GROUP = "payment_agent"
CODENAMES = [
    "verify_payment",
    "make_refund",
    "view_payment",
    "add_paymentmethod",
    "change_paymentmethod",
    "view_paymentmethod",
]


def seed(apps, schema_editor):
    app_config = apps.get_app_config("bookings")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None
    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    group, _ = Group.objects.get_or_create(name=GROUP)
    group.permissions.add(
        *Permission.objects.filter(content_type__app_label="bookings", codename__in=CODENAMES)
    )


def unseed(apps, schema_editor):
    apps.get_model("auth", "Group").objects.filter(name=GROUP).delete()


class Migration(migrations.Migration):
    dependencies = [
        ("bookings", "0002_payment_paymentmethod_and_more"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(seed, unseed)]
