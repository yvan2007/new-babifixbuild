from django.db import migrations


SOS_KEYWORDS = (
    "plomb",
    "electr",
    "serrur",
    "clim",
    "froid",
    "vitrer",
    "fuite",
)


def enable_sos_categories(apps, schema_editor):
    Category = apps.get_model("adminpanel", "Category")
    for cat in Category.objects.all():
        name_low = (cat.nom or "").lower()
        # Normaliser accents simples
        for a, b in (("é", "e"), ("è", "e"), ("ê", "e"), ("à", "a"), ("ô", "o"), ("î", "i")):
            name_low = name_low.replace(a, b)
        if any(kw in name_low for kw in SOS_KEYWORDS):
            if not cat.supports_sos:
                cat.supports_sos = True
                cat.save(update_fields=["supports_sos"])


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("adminpanel", "0101_sos_247_and_config"),
    ]

    operations = [
        migrations.RunPython(enable_sos_categories, noop_reverse),
    ]
