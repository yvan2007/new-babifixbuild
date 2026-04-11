"""
BABIFIX — Nouveaux modèles v2 (champs supplémentaires + nouveaux modèles)

Migration à créer :
  python manage.py makemigrations adminpanel --name="v2_features"
  python manage.py migrate

Nouveaux champs ajoutés :
  Provider       : portfolio_photos (JSONField)
  Notification   : user (FK), body, notif_type, reference, lu
  UserProfile    : reset_token, reset_token_created_at, email_verified, email_verify_token
  Dispute        : reservation (FK)

Nouveau modèle :
  ClientRating   : notation prestataire → client
"""
from django.contrib.auth.models import User
from django.db import models

from .models import Provider, Reservation


class ClientRating(models.Model):
    """Évaluation d'un client par un prestataire après prestation (bidirectionnel)."""

    reservation = models.OneToOneField(
        Reservation,
        on_delete=models.CASCADE,
        related_name='client_rating',
    )
    prestataire_user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='babifix_client_ratings_given',
    )
    client_user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='babifix_client_ratings_received',
    )
    note = models.PositiveSmallIntegerField()   # 1–5
    commentaire = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Évaluation client'
        verbose_name_plural = 'Évaluations clients'

    def __str__(self):
        return f'ClientRating {self.note} — {self.reservation_id}'
