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
            'nom',
            'specialite',
            'category',
            'ville',
            'statut',
            'years_experience',
            'bio',
            'tarif_horaire',
            'disponible',
            'cni_url',
            'photo_portrait_url',
            'refusal_reason',
        ]
        widgets = {
            'bio': forms.Textarea(attrs={'rows': 3}),
            'refusal_reason': forms.Textarea(attrs={'rows': 2}),
        }


class ClientForm(forms.ModelForm):
    class Meta:
        model = Client
        fields = ['nom', 'email', 'ville', 'reservations', 'depense']


class ReservationForm(forms.ModelForm):
    class Meta:
        model = Reservation
        fields = [
            'reference',
            'title',
            'client',
            'prestataire',
            'montant',
            'statut',
            'payment_type',
            'mobile_money_operator',
            'address_label',
        ]
        widgets = {
            'title': forms.TextInput(attrs={'placeholder': 'Titre mission'}),
            'address_label': forms.TextInput(attrs={'placeholder': 'Adresse (optionnel)'}),
        }


class DisputeForm(forms.ModelForm):
    class Meta:
        model = Dispute
        fields = ['reference', 'motif', 'client', 'prestataire', 'priorite', 'decision']


class PaymentForm(forms.ModelForm):
    class Meta:
        model = Payment
        fields = [
            'reference',
            'client',
            'prestataire',
            'montant',
            'commission',
            'etat',
            'type_paiement',
            'reference_externe',
            'valide_par_admin',
        ]


class CategoryForm(forms.ModelForm):
    icone_slug = forms.ChoiceField(
        label='Icône (bibliothèque BABIFIX)',
        choices=[('', '— Choisir —')] + [(s, f'{s} — {lb}') for s, lb in CATEGORY_ICON_SLUGS],
        required=False,
    )

    class Meta:
        model = Category
        fields = [
            'nom',
            'description',
            'icone_slug',
            'icone_url',
            'ordre_affichage',
            'services',
            'reservations',
            'actif',
        ]
        widgets = {'description': forms.Textarea(attrs={'rows': 2})}
        help_texts = {
            'icone_url': 'Optionnel : URL d’image externe. Sinon, choisissez un pictogramme dans la grille ci‑dessous (slug).',
            'icone_slug': 'Cliquez une vignette dans la bibliothèque pour remplir ce champ automatiquement.',
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if 'icone_slug' in self.fields:
            cur = (self.instance.icone_slug or '').strip() if self.instance.pk else ''
            if cur and cur not in [s for s, _ in CATEGORY_ICON_SLUGS]:
                self.fields['icone_slug'].choices = list(self.fields['icone_slug'].choices) + [(cur, cur)]


class NotificationForm(forms.ModelForm):
    class Meta:
        model = Notification
        fields = ['title', 'time']


class ActualiteForm(forms.ModelForm):
    class Meta:
        model = Actualite
        fields = ['titre', 'description', 'image', 'publie', 'categorie_tag', 'icone_key']
        widgets = {
            'description': forms.Textarea(attrs={'rows': 6}),
            'titre': forms.TextInput(attrs={'placeholder': 'Titre visible dans l’app'}),
        }
