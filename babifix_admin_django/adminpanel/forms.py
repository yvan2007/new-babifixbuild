"""Formulaires CRUD pour le dashboard (sans passer par django-admin)."""

from django import forms

from .constants import CATEGORY_ICON_SLUGS
from .models import (
    Actualite,
    Category,
    Client,
    Dispute,
    Notification,
    Payment,
    Provider,
    Reservation,
)


class ProviderForm(forms.ModelForm):
    class Meta:
        model = Provider
        fields = [
            "nom",
            "specialite",
            "category",
            "ville",
            "statut",
            "years_experience",
            "bio",
            "tarif_horaire",
            "disponible",
            "cni_url",
            "photo_portrait_url",
            "refusal_reason",
        ]
        widgets = {
            "bio": forms.Textarea(attrs={"rows": 3}),
            "refusal_reason": forms.Textarea(attrs={"rows": 2}),
        }


class ClientForm(forms.ModelForm):
    class Meta:
        model = Client
        fields = ["nom", "email", "ville", "reservations", "depense"]


class ReservationForm(forms.ModelForm):
    class Meta:
        model = Reservation
        fields = [
            "reference",
            "title",
            "client",
            "prestataire",
            "montant",
            "statut",
            "payment_type",
            "mobile_money_operator",
            "address_label",
        ]
        widgets = {
            "title": forms.TextInput(attrs={"placeholder": "Titre mission"}),
            "address_label": forms.TextInput(
                attrs={"placeholder": "Adresse (optionnel)"}
            ),
        }


class DisputeForm(forms.ModelForm):
    class Meta:
        model = Dispute
        fields = ["reference", "motif", "client", "prestataire", "priorite", "decision"]


class PaymentForm(forms.ModelForm):
    class Meta:
        model = Payment
        fields = [
            "reference",
            "client",
            "prestataire",
            "montant",
            "commission",
            "etat",
            "type_paiement",
            "reference_externe",
            "valide_par_admin",
            "idempotency_key",
            "idempotency_used_at",
        ]


class CategoryForm(forms.ModelForm):
    icone_slug = forms.ChoiceField(
        label="Icône (bibliothèque BABIFIX)",
        choices=[("", "— Choisir —")]
        + [(s, f"{s} — {lb}") for s, lb in CATEGORY_ICON_SLUGS],
        required=False,
    )
    # Devis intelligent (Phase 2). Le template est saisi en JSON brut dans un
    # textarea ; vide = formulaire actuel (rétrocompatible).
    template_exigences = forms.CharField(
        label="Template d’exigences (JSON)",
        required=False,
        widget=forms.Textarea(attrs={"rows": 6, "class": "code-json"}),
        help_text=(
            "Liste JSON de questions dynamiques. Ex. : "
            '[{"key":"surface_m2","label":"Surface (m²)","type":"number"}]. '
            "Laisser vide = formulaire actuel."
        ),
    )

    class Meta:
        model = Category
        fields = [
            "nom",
            "description",
            "icone_slug",
            "icone_url",
            "ordre_affichage",
            "services",
            "reservations",
            "actif",
            "profil_devis",
        ]
        widgets = {"description": forms.Textarea(attrs={"rows": 2})}
        help_texts = {
            "icone_url": "Optionnel : URL d’image externe. Sinon, choisissez un pictogramme dans la grille ci‑dessous (slug).",
            "icone_slug": "Cliquez une vignette dans la bibliothèque pour remplir ce champ automatiquement.",
            "profil_devis": "Oriente les questions posées au client. STANDARD = formulaire actuel inchangé.",
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if "icone_slug" in self.fields:
            cur = (self.instance.icone_slug or "").strip() if self.instance.pk else ""
            if cur and cur not in [s for s, _ in CATEGORY_ICON_SLUGS]:
                self.fields["icone_slug"].choices = list(
                    self.fields["icone_slug"].choices
                ) + [(cur, cur)]
        # Pré-remplir le textarea JSON depuis la valeur stockée (liste/dict).
        if self.instance and self.instance.pk:
            import json as _json
            existing = self.instance.template_exigences
            if existing:
                self.fields["template_exigences"].initial = _json.dumps(
                    existing, ensure_ascii=False, indent=2
                )

    def clean_template_exigences(self):
        """Valide le JSON saisi. Vide → liste vide (comportement actuel)."""
        import json as _json
        raw = (self.cleaned_data.get("template_exigences") or "").strip()
        if not raw:
            return []
        try:
            parsed = _json.loads(raw)
        except (ValueError, TypeError):
            raise forms.ValidationError(
                "JSON invalide. Vérifiez la syntaxe (crochets, virgules, guillemets)."
            )
        if not isinstance(parsed, list):
            raise forms.ValidationError(
                "Le template doit être une LISTE de questions (entre crochets [ ])."
            )
        return parsed

    def save(self, commit=True):
        obj = super().save(commit=False)
        # clean_template_exigences renvoie déjà une liste Python → l'affecter.
        obj.template_exigences = self.cleaned_data.get("template_exigences") or []
        if commit:
            obj.save()
        return obj


class NotificationForm(forms.ModelForm):
    class Meta:
        model = Notification
        fields = ["title", "time"]


class ActualiteForm(forms.ModelForm):
    class Meta:
        model = Actualite
        fields = [
            "titre",
            "description",
            "image",
            "publie",
            "categorie_tag",
            "icone_key",
            "cible",
        ]
        widgets = {
            "description": forms.Textarea(attrs={"rows": 6}),
            "titre": forms.TextInput(attrs={"placeholder": "Titre visible dans l’app"}),
            "cible": forms.Select(attrs={"class": "form-select"}),
        }
