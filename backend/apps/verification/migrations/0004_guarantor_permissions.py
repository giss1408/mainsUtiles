from django.contrib.auth.management import create_permissions
from django.db import migrations

GROUP = "verification_agent"


def add_permission(apps, schema_editor):
    app_config = apps.get_app_config("verification")
    app_config.models_module = True
    create_permissions(app_config, apps=apps, verbosity=0)
    app_config.models_module = None

    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    group = Group.objects.get(name=GROUP)
    group.permissions.add(
        *Permission.objects.filter(content_type__app_label="verification", codename="view_guarantor")
    )


def remove_permission(apps, schema_editor):
    Group = apps.get_model("auth", "Group")
    Permission = apps.get_model("auth", "Permission")
    group = Group.objects.filter(name=GROUP).first()
    if group:
        group.permissions.remove(*Permission.objects.filter(codename="view_guarantor"))


class Migration(migrations.Migration):
    dependencies = [
        ("verification", "0003_guarantor"),
        ("auth", "0012_alter_user_first_name_max_length"),
        ("contenttypes", "0002_remove_content_type_name"),
    ]

    operations = [migrations.RunPython(add_permission, remove_permission)]
