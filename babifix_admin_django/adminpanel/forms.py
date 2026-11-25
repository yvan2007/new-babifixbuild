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
        choices=[("", "Choisir…")]
        + [(s, f"{s} · {lb}") for s, lb in CATEGORY_ICON_SLUGS],
        required=False,
    )
    # Devis intelligent (Phase 2). Le template est saisi en JSON brut dans un
    # textarea ; vide = formulaire actuel (rétrocompatible).
    template_exigences = forms.CharField(
        label="Template d'exigences client (JSON)",
        required=False,
        widget=forms.Textarea(attrs={"rows": 5, "class": "code-json"}),
        help_text=(
            "Liste JSON de questions dynamiques cote client. Ex. : "
            '[{"key":"surface_m2","label":"Surface (m²)","type":"number"}]. '
            "Laisser vide = formulaire standard."
        ),
    )
    registration_questions = forms.CharField(
        label="Questions d'inscription prestataire (JSON)",
        required=False,
        widget=forms.Textarea(attrs={"rows": 4, "class": "code-json"}),
        help_text=(
            "Liste JSON de questions specifiques posees a l'artisan lors de son inscription."
        ),
    )

    class Meta:
        model = Category
        fields = [
            "nom",
            "groupe",
            "regime_kyc",
            "description",
            "search_keywords",
            "icone_slug",
            "icone_url",
            "ordre_affichage",
            "services",
            "reservations",
            "actif",
            "profil_devis",
        ]
        widgets = {
            "description": forms.Textarea(attrs={"rows": 2}),
            "search_keywords": forms.Textarea(attrs={"rows": 2, "placeholder": "Ex. fuite, robinet, evier, debouchage"}),
        }
        help_texts = {
            "icone_url": "Optionnel : URL d’image externe. Sinon, choisissez un pictogramme dans la grille ci-dessous (slug).",
            "icone_slug": "Cliquez une vignette dans la bibliothèque pour remplir ce champ automatiquement.",
            "profil_devis": "Oriente les questions posées au client. STANDARD = formulaire actuel inchangé.",
            "regime_kyc": "STANDARD_TERRAIN (CNI+Selfie) ou SENSIBLE_CASIER (Casier judiciaire + Reference + Entretien).",
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if "icone_slug" in self.fields:
            cur = (self.instance.icone_slug or "").strip() if self.instance.pk else ""
            if cur and cur not in [s for s, _ in CATEGORY_ICON_SLUGS]:
                self.fields["icone_slug"].choices = list(
                    self.fields["icone_slug"].choices
                ) + [(cur, cur)]
        if self.instance and self.instance.pk:
            import json as _json
            for fname in ("template_exigences", "registration_questions"):
                existing = getattr(self.instance, fname, None)
                if existing:
                    self.fields[fname].initial = _json.dumps(
                        existing, ensure_ascii=False, indent=2
                    )

    @staticmethod
    def _parse_json_list_field(raw_val: str | None) -> list:
        import json as _json
        raw = (raw_val or "").strip()
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
                "Ce champ doit être une LISTE JSON de questions (entre crochets [ ])."
            )
        return parsed

    def clean_template_exigences(self):
        """Valide le JSON saisi. Vide -> liste vide."""
        return self._parse_json_list_field(self.cleaned_data.get("template_exigences"))

    def clean_registration_questions(self):
        """Valide le JSON des questions d'inscription. Vide -> liste vide."""
        return self._parse_json_list_field(self.cleaned_data.get("registration_questions"))

    def save(self, commit=True):
        obj = super().save(commit=False)
        obj.template_exigences = self.cleaned_data.get("template_exigences") or []
        obj.registration_questions = self.cleaned_data.get("registration_questions") or []
        if commit:
            obj.save()
        return obj


class NotificationForm(forms.ModelForm):
    class Meta:
        model = Notification
        fields = ["title", "time"]


ACTUALITE_ICON_CHOICES = [
    ("", "Automatique (selon categorie)"),
    ("megaphone", "Annonce / Megaphone"),
    ("spark", "Nouveaute / Etoile"),
    ("shield", "Securite & Sequestre"),
    ("wrench", "Maintenance & Service"),
    ("wallet", "Mobile Money & Paiements"),
    ("tag", "Offre & Promotion"),
]


class ActualiteForm(forms.ModelForm):
    icone_key = forms.ChoiceField(
        label="Icone d'affichage",
        choices=ACTUALITE_ICON_CHOICES,
        required=False,
        widget=forms.Select(attrs={"class": "form-select"}),
    )

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
            "titre": forms.TextInput(attrs={"placeholder": "Titre visible dans l'app"}),
            "cible": forms.Select(attrs={"class": "form-select"}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        cur = (getattr(self.instance, "icone_key", "") or "").strip() if self.instance and self.instance.pk else ""
        if cur and cur not in {k for k, _ in ACTUALITE_ICON_CHOICES}:
            self.fields["icone_key"].choices = list(self.fields["icone_key"].choices) + [(cur, cur)]
