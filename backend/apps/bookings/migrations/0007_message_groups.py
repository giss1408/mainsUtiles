from django.contrib.auth.management import create_permissions
from django.db import migrations

GROUPS = ["payment_agent", "enrolment_agent"]
CODENAMES = ["send_message", "view_message"]


def seed(apps, schema_editor):
    app_config = apps.get_app_config("bookings")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None
    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    wanted = Permission.objects.filter(content_type__app_label="bookings", codename__in=CODENAMES)
    for name in GROUPS:
        group, _ = Group.objects.get_or_create(name=name)
        group.permissions.add(*wanted)


def unseed(apps, schema_editor):
    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    for group in Group.objects.filter(name__in=GROUPS):
        group.permissions.remove(*Permission.objects.filter(codename__in=CODENAMES))


class Migration(migrations.Migration):
    dependencies = [
        ("bookings", "0006_message"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(seed, unseed)]
