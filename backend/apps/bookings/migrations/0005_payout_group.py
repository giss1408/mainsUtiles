from django.contrib.auth.management import create_permissions
from django.db import migrations

GROUP = "payment_agent"
CODENAMES = ["make_payout", "resolve_dispute", "view_payout", "view_report"]


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
    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    group = Group.objects.filter(name=GROUP).first()
    if group:
        group.permissions.remove(*Permission.objects.filter(codename__in=CODENAMES))


class Migration(migrations.Migration):
    dependencies = [
        ("bookings", "0004_job_and_after"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(seed, unseed)]
