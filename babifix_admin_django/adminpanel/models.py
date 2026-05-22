from decimal import Decimal, InvalidOperation

from django.db import models
from django.contrib.auth.models import User
from django.core.validators import MaxLengthValidator
from django.utils import timezone


class Provider(models.Model):
    """Aligné diagramme UML : Prestataire (validation, tarif, notes)."""

    class Status(models.TextChoices):
        PENDING = "En attente", "En attente"
        VALID = "Valide", "Valide"
        SUSPENDED = "Suspendu", "Suspendu"
        REFUSED = "Refuse", "Refuse"

    user = models.OneToOneField(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="provider_profile",
    )
    nom = models.CharField(max_length=120)
    specialite = models.CharField(max_length=80)
    ville = models.CharField(max_length=80)
    statut = models.CharField(
        max_length=20, choices=Status.choices, default=Status.PENDING
    )
    years_experience = models.PositiveSmallIntegerField(default=0)
    bio = models.TextField(blank=True, default="")
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    # UML : tarifHoraire, noteMoyenne, nombreAvis, cniUrl, disponible
    tarif_horaire = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True
    )
    average_rating = models.FloatField(default=0.0)
    rating_count = models.PositiveIntegerField(default=0)
    disponible = models.BooleanField(default=True)
    cni_url = models.TextField(blank=True, default="")
    cni_recto_url = models.TextField(
        blank=True, default="", help_text="CNI face avant"
    )
    cni_verso_url = models.TextField(
        blank=True, default="", help_text="CNI face arrière"
    )
    selfie_url = models.TextField(
        blank=True,
        default="",
        help_text="Selfie avec CNI - validation identité",
    )
    video_intro_url = models.TextField(
        blank=True,
        default="",
        help_text="Vidéo intro 30-60s - filtre qualité",
    )
    photo_portrait_url = models.TextField(
        blank=True,
        default="",
        help_text="Photo de profil (URL) — visible après validation admin",
    )
    refusal_reason = models.TextField(
        blank=True,
        default="",
        help_text="Motif affiche au prestataire si dossier refuse",
    )
    # Moteur KYC automatique — score 0-100 calculé à la soumission du dossier
    auto_check_score = models.IntegerField(
        default=0,
        help_text="Score de vérification automatique 0–100 (moteur KYC engine)",
    )
    auto_check_result = models.JSONField(
        default=dict,
        blank=True,
        help_text="Résultat détaillé du moteur KYC (checks, confiance, visages)",
    )
    auto_check_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Date/heure du dernier passage du moteur de vérification automatique",
    )
    category = models.ForeignKey(
        "Category",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="providers",
        help_text="Catégorie métier (icône / filtre client)",
    )
    is_approved = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Aligne sur statut Valide — visible apps client",
    )
    is_certified = models.BooleanField(
        default=False,
        help_text="Badge 'Prestataire Certifie' — validation apres review admin",
    )
    certified_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Date de certification Admin",
    )
    # M2: Premium abonnement
    is_premium = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Abonnement premium actif (bronze/silver/gold)",
    )
    premium_tier = models.CharField(
        max_length=20,
        blank=True,
        default="",
        choices=[
            ("silver", "Argent"),
            ("gold", "Or"),
        ],
    )
    premium_since = models.DateTimeField(
        null=True,
        blank=True,
    )
    premium_until = models.DateTimeField(
        null=True,
        blank=True,
    )
    has_used_premium_trial = models.BooleanField(
        default=False,
        help_text="True dès qu'un essai gratuit 7j a été consommé (à vie).",
    )
    is_premium_annual = models.BooleanField(
        default=False,
        help_text="Abonnement annuel (vs mensuel). Verrouillé jusqu'à premium_until.",
    )
    # v2 — Galerie réalisations (max 12 photos, data URL base64)
    portfolio_photos = models.JSONField(
        default=list,
        blank=True,
        help_text="Liste de {photo, caption, added_at} — max 12 entrées",
    )
    # v2 — Photos avant/après intervention
    before_photos = models.JSONField(
        default=list,
        blank=True,
        help_text="Liste photos avant intervention",
    )
    after_photos = models.JSONField(
        default=list,
        blank=True,
        help_text="Liste photos après intervention",
    )
    is_deleted = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Soft delete - prestataire supprime si True",
    )
    # Wallet prestataire
    solde_fcfa = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Solde disponible pour retrait (FCFA)",
    )
    wallet_phone = models.CharField(
        max_length=20,
        blank=True,
        default="",
        help_text="Numéro Mobile Money pour les retraits (MTN/Orange/Wave)",
    )
    wallet_operator = models.CharField(
        max_length=20,
        blank=True,
        default="",
        choices=[
            ("mtn", "MTN Mobile Money"),
            ("orange", "Orange Money"),
            ("wave", "Wave"),
            ("moov", "Moov Money"),
        ],
        help_text="Opérateur Mobile Money préféré",
    )
    # Signature numérique du contrat BABIFIX (serveur)
    contrat_accepte_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Horodatage de l'acceptation du contrat BABIFIX",
    )
    contrat_version = models.CharField(
        max_length=10,
        blank=True,
        default="",
        help_text="Version du contrat signé (ex: '1.0', '1.1')",
    )

    # KYC — Vérification identité prestataire
    kyc_status = models.CharField(
        max_length=20,
        choices=[
            ("not_submitted", "Non soumis"),
            ("pending", "En attente"),
            ("under_review", "En examen"),
            ("approved", "Approuvé"),
            ("rejected", "Rejeté"),
        ],
        default="not_submitted",
    )
    kyc_rejection_reason = models.TextField(
        blank=True,
        default="",
        help_text="Motif de rejet du dossier KYC",
    )
    kyc_cni_number = models.CharField(
        max_length=80,
        blank=True,
        default="",
        help_text="Numéro de la CNI",
    )
    kyc_cni_expiry = models.DateField(
        null=True,
        blank=True,
        help_text="Date d'expiration de la CNI",
    )
    kyc_cni_recto_url = models.TextField(
        blank=True,
        default="",
        help_text="URL recto CNI (base64 ou fichier)",
    )
    kyc_cni_verso_url = models.TextField(
        blank=True,
        default="",
        help_text="URL verso CNI (base64 ou fichier)",
    )
    kyc_selfie_url = models.TextField(
        blank=True,
        default="",
        help_text="URL selfie avec CNI",
    )
    kyc_submitted_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Date/heure de soumission du dossier KYC",
    )
    kyc_reviewed_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Date/heure de validation/rejet par admin",
    )
    kyc_reviewed_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="kyc_reviews",
        help_text="Admin qui a examiné le dossier",
    )

    def __str__(self):
        return self.nom


class WalletTransaction(models.Model):
    """Historique des mouvements du wallet prestataire."""

    class TxType(models.TextChoices):
        CREDIT = "credit", "Crédit (paiement reçu)"
        DEBIT = "debit", "Débit (retrait)"
        COMMISSION = "commission", "Commission BABIFIX"
        REFUND = "refund", "Remboursement"

    class TxStatus(models.TextChoices):
        PENDING = "pending", "En attente"
        PROCESSING = "processing", "En cours de versement"
        SUCCESS = "success", "Réussi"
        FAILED = "failed", "Échoué"

    provider = models.ForeignKey(
        Provider,
        on_delete=models.CASCADE,
        related_name="wallet_transactions",
    )
    tx_type = models.CharField(max_length=12, choices=TxType.choices)
    amount_fcfa = models.DecimalField(max_digits=12, decimal_places=2)
    status = models.CharField(max_length=10, choices=TxStatus.choices, default=TxStatus.SUCCESS)
    reference = models.CharField(max_length=100, blank=True, default="")
    description = models.TextField(blank=True, default="")
    operator = models.CharField(max_length=20, blank=True, default="")
    phone = models.CharField(max_length=20, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["provider", "-created_at"])]

    def __str__(self):
        return f"{self.tx_type} {self.amount_fcfa} FCFA — {self.provider_id}"


class Client(models.Model):
    nom = models.CharField(max_length=120)
    email = models.EmailField()
    ville = models.CharField(max_length=80)
    reservations = models.PositiveIntegerField(default=0)
    depense = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Dépense totale en FCFA",
    )

    def depense_display(self):
        return f"{self.depense} francs CFA"

    def __str__(self):
        return self.nom


class Reservation(models.Model):
    """UML : Reservation + flux paiement espèces (déclaration client → confirmation prestataire → admin)."""

    class Status(models.TextChoices):
        # Anciens statuts (compatibilité)
        PENDING = "En attente", "En attente"
        CONFIRMED = "Confirmee", "Confirmee"
        IN_PROGRESS = "En cours", "En cours"
        WAITING_CLIENT = "En attente client", "En attente client"
        DONE = "Terminee", "Terminee"
        CANCELLED = "Annulee", "Annulee"

        # Nouveau parcours - demande et devis
        DEMANDE_ENVOYEE = "DEMANDE_ENVOYEE", "Demande envoyée"
        DEVIS_EN_COURS = "DEVIS_EN_COURS", "Devis en cours"
        DEVIS_ENVOYE = "DEVIS_ENVOYE", "Devis envoyé"
        DEVIS_ACCEPTE = "DEVIS_ACCEPTE", "Devis accepté"
        INTERVENTION_EN_COURS = "INTERVENTION_EN_COURS", "Intervention en cours"

    class PaymentType(models.TextChoices):
        ESPECES = "ESPECES", "Especes"
        MOBILE_MONEY = "MOBILE_MONEY", "Mobile Money"
        CARTE = "CARTE", "Carte"
        AUTRE = "AUTRE", "Autre"

    class MobileMoneyOperator(models.TextChoices):
        """Operateurs courants en Cote d'Ivoire (Mobile Money)."""

        UNSPECIFIED = "", "Non precise"
        ORANGE_MONEY = "ORANGE_MONEY", "Orange Money"
        MTN_MOMO = "MTN_MOMO", "MTN Mobile Money"
        WAVE = "WAVE", "Wave"
        MOOV = "MOOV", "Moov Money"

    class CashFlowStatus(models.TextChoices):
        NA = "", "N/A"
        PENDING_PRESTATAIRE = "pending_prestataire", "En attente prestataire"
        PENDING_ADMIN = "pending_admin", "En attente validation admin"
        VALIDATED = "validated", "Valide"
        REFUSED = "refused", "Refuse"

    reference = models.CharField(max_length=40, unique=True)
    title = models.CharField(max_length=200, blank=True, default="")
    client = models.CharField(max_length=120)
    prestataire = models.CharField(max_length=120)
    montant = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        help_text="Montant de la réservation en francs CFA",
    )
    statut = models.CharField(
        max_length=30, choices=Status.choices, default=Status.DEMANDE_ENVOYEE
    )
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    address_label = models.CharField(max_length=500, blank=True, default="")
    location_captured_at = models.DateTimeField(null=True, blank=True)
    payment_type = models.CharField(
        max_length=24,
        choices=PaymentType.choices,
        default=PaymentType.ESPECES,
    )
    mobile_money_operator = models.CharField(
        max_length=24,
        choices=MobileMoneyOperator.choices,
        default=MobileMoneyOperator.UNSPECIFIED,
        blank=True,
        help_text="Si paiement Mobile Money : Orange, MTN, Wave, Moov (Cote d'Ivoire).",
    )
    client_message = models.TextField(
        blank=True, default="", help_text="Message client lors de la réservation (UML)"
    )
    # Nouveau parcours : champs pour la demande
    description_probleme = models.TextField(
        blank=True, default="", help_text="Description du problème par le client"
    )
    photos_probleme = models.JSONField(
        default=list, blank=True, help_text="URLs des photos du problème"
    )
    photos_avant = models.JSONField(
        default=list, blank=True, help_text="URLs des photos avant intervention"
    )
    photos_apres = models.JSONField(
        default=list, blank=True, help_text="URLs des photos après intervention"
    )
    disponibilites_client = models.CharField(
        max_length=255,
        blank=True,
        default="",
        help_text="Disponibilités du client: 'Matin, Après-midi, Lun-Mer'",
    )
    is_urgent = models.BooleanField(
        default=False, help_text="Intervention urgente demandée par le client"
    )
    urgence_surcharge_pct = models.PositiveSmallIntegerField(
        default=0,
        help_text="Surcharge urgence appliquée en % (ex: 20 = +20%)",
    )
    motif_refus_demande = models.TextField(
        blank=True,
        default="",
        help_text="Motif de refus de la demande par le prestataire",
    )

    prix_propose = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        null=True,
        blank=True,
        help_text="Prix proposé par le client (optionnel — si différent du tarif catalogue)",
    )
    # Champs de gestion de paiement sécurisé (Acompte / Solde)
    montant_verse = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Montant déjà versé / bloqué (acompte)",
    )
    montant_restant = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Montant restant dû à la fin de l'intervention",
    )
    acompte_valide = models.BooleanField(
        default=False,
        help_text="L'acompte a été payé et bloqué, le prestataire peut commencer",
    )
    solde_valide = models.BooleanField(
        default=False,
        help_text="Le solde a été payé, le prestataire peut être rémunéré",
    )
    cash_client_declared_at = models.DateTimeField(null=True, blank=True)
    cash_prestataire_confirmed_at = models.DateTimeField(null=True, blank=True)
    cash_admin_validated_at = models.DateTimeField(null=True, blank=True)
    cash_flow_status = models.CharField(
        max_length=32,
        choices=CashFlowStatus.choices,
        default=CashFlowStatus.NA,
        blank=True,
    )
    cash_refusal_motif = models.CharField(max_length=500, blank=True, default="")
    # Commission 18% - calcul automatique
    commission = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        null=True,
        blank=True,
        help_text="Commission BABIFIX 18% calculée automatiquement",
    )
    # Idempotence paiement - évite double paiement
    idempotency_key = models.CharField(
        max_length=64,
        unique=True,
        null=True,
        blank=True,
        help_text="Clé d'idempotence pour les paiements",
    )
    # Masquage telephone - ZEGOCLOUD
    appel_masque = models.BooleanField(
        default=False, help_text="Appel masquevia ZEGOCLOUD"
    )
    numero_masque = models.CharField(
        max_length=20,
        blank=True,
        default="",
        help_text="Numero masque temporaire pour appel ZEGOCLOUD",
    )
    # Idempotence paiement - [DEPRECATED] Utiliser Payment.idempotency_key
    # Ce champ est en doublon avec la definition ci-dessus (ligne 280).
    # TODO: Supprimer apres migration des donnees
    client_user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="babifix_reservations_as_client",
    )
    prestataire_user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="babifix_reservations_as_prestataire",
    )
    assigned_provider = models.ForeignKey(
        "Provider",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reservations",
    )
    # Flux paiement après prestation (UML + plan BABIFIX)
    prestation_terminee_at = models.DateTimeField(null=True, blank=True)
    client_confirme_prestation_at = models.DateTimeField(null=True, blank=True)
    # Phase F — Escrow : horodatage de libération des fonds (wallet presta ou
    # acte cash). Si null, les fonds sont encore bloqués côté plateforme.
    funds_released_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text=(
            "Horodatage de libération escrow. Null = fonds encore bloqués. "
            "Set après client_confirme_prestation_at via EscrowService.release_funds."
        ),
    )
    preuve_photos = models.JSONField(default=list, blank=True)
    # Journal client post-intervention (témoignage propre du client) :
    # photos avant/après facultatives et commentaire libre. Distinct des
    # `photos_avant`/`photos_apres` qui sont celles du prestataire.
    client_photos_avant = models.JSONField(
        default=list,
        blank=True,
        help_text="Photos avant prises par le client (témoignage, facultatif)",
    )
    client_photos_apres = models.JSONField(
        default=list,
        blank=True,
        help_text="Photos après prises par le client (témoignage, facultatif)",
    )
    client_journal_note = models.TextField(
        blank=True,
        default="",
        help_text=(
            "Commentaire libre du client à la fin de l'intervention "
            "(ressenti, détail des travaux, qualité…)."
        ),
    )
    client_journal_updated_at = models.DateTimeField(null=True, blank=True)
    # C1 — Annulation & remboursement
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancellation_by = models.CharField(
        max_length=16,
        blank=True,
        default="",
        help_text="CLIENT | PRESTATAIRE | ADMIN",
    )
    cancellation_stage = models.CharField(
        max_length=24,
        blank=True,
        default="",
        help_text="before_devis | after_devis | after_accept | after_start",
    )
    cancellation_motif = models.TextField(blank=True, default="")
    refund_owed_fcfa = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Montant que la plateforme doit rembourser au client (en attente admin)",
    )
    refund_paid_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Set une fois le remboursement client effectivement viré (payout).",
    )
    refund_reference = models.CharField(
        max_length=80,
        blank=True,
        default="",
        help_text="Référence externe du versement de remboursement (GeniusPay).",
    )
    refund_status = models.CharField(
        max_length=12,
        blank=True,
        default="",
        help_text="'' | processing | paid | failed | manual — état du remboursement client.",
    )
    dispute_ouverte = models.BooleanField(default=False, db_index=True)
    payment_client_note = models.TextField(
        blank=True,
        default="",
        help_text="Message optionnel du client au moment du paiement",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.reference

    def save(self, *args, **kwargs):
        if isinstance(self.montant, str):
            cleaned = (
                self.montant.replace("FCFA", "")
                .replace("F CFA", "")
                .replace("francs CFA", "")
                .replace(" ", "")
                .replace(",", ".")
                .strip()
            )
            try:
                self.montant = Decimal(cleaned or "0")
            except InvalidOperation:
                self.montant = Decimal("0")

        if self.montant:
            montant_decimal = (
                self.montant
                if isinstance(self.montant, Decimal)
                else Decimal(str(self.montant))
            )
            if montant_decimal > 0:
                self.montant = montant_decimal
                # Commission via SystemSetting (fallback 18%)
                try:
                    setting = SystemSetting.objects.first()
                    commission_pct = setting.commission if setting else 18
                    self.commission = montant_decimal * Decimal(str(commission_pct)) / Decimal("100")
                except Exception:
                    self.commission = montant_decimal * Decimal("0.18")
        # Calcul des montants restants pour la sécurisation
        self.montant_restant = (self.montant or 0) - (self.montant_verse or 0)
        super().save(*args, **kwargs)


class ReservationStatusHistory(models.Model):
    """Historique des changements de statut d'une réservation."""
    reservation = models.ForeignKey(
        Reservation,
        on_delete=models.CASCADE,
        related_name="status_history",
    )
    old_status = models.CharField(
        max_length=40,
        blank=True,
        default="",
        help_text="Ancien statut (vide si création)",
    )
    new_status = models.CharField(
        max_length=40,
        help_text="Nouveau statut",
    )
    changed_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        help_text="Utilisateur ayant effectué le changement",
    )
    comment = models.TextField(
        blank=True,
        default="",
        help_text="Commentaire optionnel",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["reservation", "-created_at"])]

    def __str__(self):
        return f"{self.reservation.reference}: {self.old_status} → {self.new_status}"


class Dispute(models.Model):
    class Priority(models.TextChoices):
        HIGH = "Haute", "Haute"
        MEDIUM = "Moyenne", "Moyenne"
        LOW = "Basse", "Basse"

    class Decision(models.TextChoices):
        OPEN = "En cours", "En cours"
        REFUND = "Rembourser client", "Rembourser client"
        RELEASE = "Liberer paiement", "Liberer paiement"
        SPLIT = "Partage partiel", "Partage partiel"

    class Category(models.TextChoices):
        TRAVAIL_NON_FAIT = "travail_non_fait", "Travail non réalisé"
        TRAVAIL_BACLE = "travail_bacle", "Travail bâclé / mal fait"
        PRESTA_ABSENT = "presta_absent", "Prestataire absent / pas venu"
        RETARD = "retard", "Retard important"
        PRIX_NON_CONFORME = "prix_non_conforme", "Prix non conforme au devis"
        DEGATS = "degats", "Dégâts causés"
        COMPORTEMENT = "comportement", "Comportement inapproprié"
        AUTRE = "autre", "Autre"

    reference = models.CharField(max_length=40, unique=True)
    motif = models.CharField(max_length=500)  # élargi pour textes plus longs
    categorie = models.CharField(
        max_length=32,
        choices=Category.choices,
        default=Category.AUTRE,
        db_index=True,
    )
    client = models.CharField(max_length=120)
    prestataire = models.CharField(max_length=120)
    priorite = models.CharField(
        max_length=10, choices=Priority.choices, default=Priority.MEDIUM
    )
    decision = models.CharField(
        max_length=30, choices=Decision.choices, default=Decision.OPEN
    )
    # v2 — lien vers la réservation concernée
    reservation = models.ForeignKey(
        "Reservation",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="disputes",
    )
    # v3 — pièces jointes (preuves photos) en data URLs base64, max 5.
    photos_client = models.JSONField(default=list, blank=True)
    # v3 — réponse du prestataire (sa version + ses preuves)
    prestataire_response = models.TextField(blank=True, default="")
    prestataire_response_at = models.DateTimeField(null=True, blank=True)
    photos_prestataire = models.JSONField(default=list, blank=True)
    # v3 — audit de la décision admin
    decided_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name="disputes_decided",
    )
    decision_note = models.TextField(blank=True, default="")
    decided_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, null=True)

    def __str__(self):
        return self.reference


class Payment(models.Model):
    class State(models.TextChoices):
        COMPLETE = "Complete", "Complete"
        PENDING = "Pending", "Pending"
        DISPUTE = "Litige", "Litige"

    class TypePaiement(models.TextChoices):
        MOBILE_MONEY = "MOBILE_MONEY", "Mobile Money"
        ESPECES = "ESPECES", "Especes"
        CARTE = "CARTE", "Carte"

    reference = models.CharField(max_length=40, unique=True)
    client = models.CharField(max_length=120)
    prestataire = models.CharField(max_length=120)
    montant = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        help_text="Montant en francs CFA",
    )
    commission = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        null=True,
        blank=True,
        help_text="Commission BABIFIX calculée automatiquement",
    )
    etat = models.CharField(max_length=20, choices=State.choices, default=State.PENDING)
    reservation = models.ForeignKey(
        "Reservation",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="payments",
    )
    type_paiement = models.CharField(
        max_length=24,
        choices=TypePaiement.choices,
        default=TypePaiement.ESPECES,
    )
    reference_externe = models.CharField(
        max_length=64,
        blank=True,
        default="",
        help_text=" Référence CinetPay ou autre externe",
    )
    valide_par_admin = models.BooleanField(
        default=False,
        help_text="Validé par admin pour les espèces",
    )
    # Idempotence - empêche double paiement
    idempotency_key = models.CharField(
        max_length=64,
        unique=True,
        null=True,
        blank=True,
        db_index=True,
        help_text="Clé d'idempotence pour éviter les doublons",
    )
    idempotency_used_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Date d'utilisation de la clé",
    )

    def __str__(self):
        return self.reference

    def save(self, *args, **kwargs):
        # Calculer la commission automatiquement si non définie
        if not self.commission and self.montant:
            montant_decimal = (
                self.montant
                if isinstance(self.montant, Decimal)
                else Decimal(str(self.montant))
            )
            if montant_decimal > 0:
                try:
                    from adminpanel.models import SystemSetting
                    setting = SystemSetting.objects.first()
                    commission_pct = setting.commission if setting else 18
                    self.commission = montant_decimal * Decimal(str(commission_pct)) / Decimal("100")
                except Exception:
                    self.commission = montant_decimal * Decimal("0.18")
        super().save(*args, **kwargs)


class Category(models.Model):
    nom = models.CharField(max_length=80, unique=True)
    description = models.TextField(blank=True, default="")
    icone_url = models.CharField(max_length=500, blank=True, default="")
    icone_slug = models.CharField(
        max_length=64,
        blank=True,
        default="",
        db_index=True,
        help_text="Slug → static/category-icons/{slug}.svg (SVG multicolore ; remplaçable par export IconScout sous licence, même nom de fichier).",
    )
    ordre_affichage = models.PositiveSmallIntegerField(default=0)
    services = models.PositiveIntegerField(default=0)
    reservations = models.PositiveIntegerField(default=0)
    is_deleted = models.BooleanField(default=False, db_index=True, help_text="Soft delete: l'admin a masqué cette catégorie, elle ne s'affiche plus mais les anciennes données sont conservées.")
    actif = models.BooleanField(default=True, help_text="Visible sur les apps (désactivable temporairement)")

    class Meta:
        ordering = ["ordre_affichage", "nom"]

    def __str__(self):
        return self.nom


class CategoryCommission(models.Model):
    """Taux de commission par catégorie."""

    category = models.OneToOneField(
        Category,
        on_delete=models.CASCADE,
        related_name="commission",
    )
    commission_rate = models.PositiveSmallIntegerField(
        default=10,
        help_text="Taux de commission en pourcentage (ex: 10 = 10%)",
    )
    actif = models.BooleanField(default=True)

    class Meta:
        verbose_name = "Commission catégorie"
        verbose_name_plural = "Commissions catégories"

    def __str__(self):
        return f"{self.category.nom} — {self.commission_rate}%"


class Notification(models.Model):
    """Notification persistante par utilisateur (centre de notifications in-app)."""

    class NotifType(models.TextChoices):
        RESERVATION = "reservation", "Réservation"
        MESSAGE = "message", "Message"
        VALIDATION = "validation", "Validation compte"
        BROADCAST = "broadcast", "Annonce"
        PAYMENT = "payment", "Paiement"
        DISPUTE = "dispute", "Litige"
        GENERAL = "general", "Général"

    title = models.CharField(max_length=200)
    body = models.TextField(blank=True, default="")
    time = models.CharField(max_length=80, default="A l instant")
    notif_type = models.CharField(
        max_length=20,
        choices=NotifType.choices,
        default=NotifType.GENERAL,
    )
    reference = models.CharField(
        max_length=60,
        blank=True,
        default="",
        help_text="Référence liée (réservation, litige…)",
    )
    lu = models.BooleanField(default=False, db_index=True)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="babifix_notifications",
        help_text="None = notification admin globale",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.title


class DeviceToken(models.Model):
    """Jeton FCM (Firebase Cloud Messaging) par appareil — Phase 2 push mobile."""

    class Platform(models.TextChoices):
        ANDROID = "android", "Android"
        IOS = "ios", "iOS"
        WEB = "web", "Web"

    user = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name="fcm_device_tokens"
    )
    # 191 = limite index UNIQUE MySQL utf8mb4 (InnoDB ~1000 octets) ; jeton FCM < ~200 car.
    token = models.CharField(max_length=191, unique=True, db_index=True)
    platform = models.CharField(
        max_length=16, choices=Platform.choices, default=Platform.ANDROID
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at"]

    def __str__(self):
        return f"{self.user_id}:{self.token[:20]}…"


class SystemSetting(models.Model):
    commission = models.PositiveIntegerField(default=10)
    auto_validation = models.BooleanField(default=False)
    maintenance = models.BooleanField(default=False)
    mode_paiement = models.CharField(
        max_length=120,
        default="Especes + Orange Money, MTN MoMo, Wave, Moov (CI)",
    )

    def __str__(self):
        return "BABIFIX Settings"


class UserProfile(models.Model):
    class Role(models.TextChoices):
        CLIENT = "client", "Client"
        PRESTATAIRE = "prestataire", "Prestataire"
        ADMIN = "admin", "Admin"

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    role = models.CharField(max_length=20, choices=Role.choices)
    active = models.BooleanField(default=True)
    phone_e164 = models.CharField(max_length=24, blank=True, default="")
    country_code = models.CharField(max_length=5, blank=True, default="CI")
    # v2 — Reinitialisation mot de passe
    reset_token = models.CharField(max_length=80, blank=True, default="", db_index=True)
    reset_token_created_at = models.DateTimeField(null=True, blank=True)
    # v2 — Verification email
    email_verified = models.BooleanField(default=False)
    email_verify_token = models.CharField(
        max_length=80, blank=True, default="", db_index=True
    )
    # Soft delete
    is_deleted = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Soft delete - compte desactive si True",
    )
    deleted_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Date de suppression soft",
    )
    # v2 — Parrainage (ReferralService)
    referral_code = models.CharField(
        max_length=20, blank=True, default="", db_index=True,
        help_text="Code de parrainage unique"
    )
    recommended_by = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="filleuls",
        help_text="Parrain qui a invite cet utilisateur"
    )
    referral_code_used = models.CharField(
        max_length=20, blank=True, default="",
        help_text="Code de parrainage utilise a l'inscription"
    )
    referral_credits_earned = models.DecimalField(
        max_digits=10, decimal_places=2, default=0,
        help_text="Credits gagnes via parrainage"
    )
    referral_bonus_applied = models.BooleanField(
        default=False,
        help_text="Bonus premiere reservation applique"
    )
    whatsapp_opt_in = models.BooleanField(
        default=True,
        help_text="Accepte de recevoir des notifications WhatsApp",
    )
    phone_verified = models.BooleanField(
        default=False,
        help_text="Telephone verifie via OTP Firebase",
    )

    def __str__(self):
        return f"{self.user.username} ({self.role})"


class SiteContent(models.Model):
    """Contenu éditable (vitrine, liens stores, textes)."""

    key = models.SlugField(max_length=80, unique=True)
    value = models.TextField(blank=True, default="")
    json_value = models.JSONField(null=True, blank=True)

    def __str__(self):
        return self.key


class Conversation(models.Model):
    client = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="babifix_conversations_as_client",
    )
    prestataire = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="babifix_conversations_as_prestataire",
    )
    reservation = models.OneToOneField(
        "Reservation",
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="chat_conversation",
    )
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["client", "prestataire"]),
        ]

    def __str__(self):
        return f"{self.client_id}-{self.prestataire_id}"


class Message(models.Model):
    class Kind(models.TextChoices):
        USER = "USER", "Message utilisateur"
        DEVIS_CARD = "DEVIS_CARD", "Carte devis ancrée"
        SYSTEM = "SYSTEM", "Événement système"

    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name="messages",
    )
    sender = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name="babifix_messages_sent"
    )
    body = models.TextField(
        blank=True,
        default="",
        validators=[MaxLengthValidator(5000)],
        help_text="Maximum 5000 caractères",
    )
    image = models.ImageField(upload_to="babifix_chat/", blank=True)
    reply_to = models.ForeignKey(
        "self",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="replies",
    )
    kind = models.CharField(
        max_length=16,
        choices=Kind.choices,
        default=Kind.USER,
        db_index=True,
        help_text=(
            "USER = message libre. DEVIS_CARD = devis figé ancré au fil. "
            "SYSTEM = événement (démarrage/fin/paiement)."
        ),
    )
    payload_json = models.JSONField(
        null=True,
        blank=True,
        help_text=(
            "Données structurées pour les messages DEVIS_CARD/SYSTEM "
            "(montants, références, statuts…)."
        ),
    )
    created_at = models.DateTimeField(auto_now_add=True)
    lu = models.BooleanField(
        default=False,
        db_index=True,
        help_text="Lu par le destinataire (pas l’expéditeur)",
    )
    deleted = models.BooleanField(default=False, db_index=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self):
        return f"Msg {self.pk}"


class Rating(models.Model):
    """Avis client sur prestataire après prestation (diagramme UML + activité notation)."""

    reservation = models.OneToOneField(
        Reservation,
        on_delete=models.CASCADE,
        related_name="rating",
    )
    client = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="babifix_ratings_given",
    )
    provider = models.ForeignKey(
        Provider,
        on_delete=models.CASCADE,
        related_name="ratings",
    )
    note = models.PositiveSmallIntegerField()  # 1–5
    commentaire = models.TextField(blank=True, default="")
    # Photos jointes à l’avis (data URLs base64 image/*, liste courte — MVP)
    photo_attachments = models.JSONField(default=list, blank=True)
    voice_note_url = models.CharField(
        max_length=500,
        blank=True,
        default="",
        help_text="URL de la note vocale (fichier audio uploadé)",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Rating {self.note} — {self.reservation_id}"


class Actualite(models.Model):
    """Actualités / annonces pour apps client & prestataire (hors blog complet)."""

    class CategorieTag(models.TextChoices):
        NOUVEAU_PRESTATAIRE = "nouveau_prestataire", "Nouveau prestataire"
        PAIEMENT = "paiement", "Paiement / Mobile Money"
        PROMO = "promo", "Promotion"
        MAINTENANCE = "maintenance", "Maintenance"
        GENERAL = "general", "Général"

    class Cible(models.TextChoices):
        CLIENT = "client", "Client uniquement"
        PRESTATAIRE = "prestataire", "Prestataire uniquement"
        TOUS = "tous", "Tous les utilisateurs"

    titre = models.CharField(max_length=150)
    description = models.TextField()
    image = models.ImageField(upload_to="actualites/", blank=True)
    date_publication = models.DateTimeField(auto_now_add=True)
    publie = models.BooleanField(default=False, db_index=True)
    categorie_tag = models.CharField(
        max_length=40,
        choices=CategorieTag.choices,
        default=CategorieTag.GENERAL,
    )
    icone_key = models.CharField(
        max_length=40,
        blank=True,
        default="",
        help_text="Clé simple (ex. megaphone) pour UI",
    )
    cible = models.CharField(
        max_length=20,
        choices=Cible.choices,
        default=Cible.TOUS,
        db_index=True,
        help_text="Audience : client uniquement, prestataire uniquement, ou tous",
    )
    created_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="actualites_crees",
    )

    class Meta:
        ordering = ["-date_publication"]
        verbose_name = "Actualité"
        verbose_name_plural = "Actualités"

    def __str__(self):
        return self.titre


class AdminAuditLog(models.Model):
    """Trace chaque action admin : validation prestataire, décision litige, action bulk."""

    class ActionType(models.TextChoices):
        PROVIDER_ACCEPTED = "provider_accepted", "Prestataire accepté"
        PROVIDER_REFUSED = "provider_refused", "Prestataire refusé"
        PROVIDER_SUSPENDED = "provider_suspended", "Prestataire suspendu"
        LITIGE_RESOLVED = "litige_resolved", "Litige résolu"
        BULK_ACCEPT = "bulk_accept", "Validation en masse"
        BULK_REFUSE = "bulk_refuse", "Refus en masse"
        PAYMENT_VALIDATED = "payment_validated", "Paiement validé"
        OTHER = "other", "Autre"

    admin_user = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="audit_logs",
    )
    action = models.CharField(
        max_length=40, choices=ActionType.choices, default=ActionType.OTHER
    )
    target_type = models.CharField(max_length=40, blank=True, default="")
    target_id = models.IntegerField(null=True, blank=True)
    target_label = models.CharField(max_length=200, blank=True, default="")
    details = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name = "Journal admin"

    def __str__(self):
        user = self.admin_user.username if self.admin_user else "système"
        return f"[{self.action}] {user} — {self.target_label}"


def recalc_provider_rating_stats(provider: Provider) -> None:
    from django.db.models import Avg, Count

    agg = Rating.objects.filter(provider=provider).aggregate(
        avg=Avg("note"), cnt=Count("id")
    )
    provider.average_rating = float(agg["avg"] or 0)
    provider.rating_count = agg["cnt"] or 0
    provider.save(update_fields=["average_rating", "rating_count"])


class PrestataireAvailabilitySlot(models.Model):
    """Créneaux de disponibilité d'un prestataire."""

    provider = models.ForeignKey(
        Provider,
        on_delete=models.CASCADE,
        related_name="availability_slots",
    )
    jour_semaine = models.PositiveSmallIntegerField(
        help_text="0 = lundi, 6 = dimanche",
    )
    heure_debut = models.TimeField()
    heure_fin = models.TimeField()
    actif = models.BooleanField(default=True)

    class Meta:
        ordering = ["jour_semaine", "heure_debut"]
        unique_together = ["provider", "jour_semaine", "heure_debut"]

    def __str__(self):
        return f"{self.provider.nom} — Jour {self.jour_semaine} {self.heure_debut}-{self.heure_fin}"


class PrestataireUnavailability(models.Model):
    """Périodes d'indisponibilité d'un prestataire."""

    provider = models.ForeignKey(
        Provider,
        on_delete=models.CASCADE,
        related_name="unavailabilities",
    )
    date_debut = models.DateField()
    date_fin = models.DateField()
    motif = models.CharField(max_length=200, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-date_debut"]

    def __str__(self):
        return f"{self.provider.nom} — {self.date_debut} à {self.date_fin}"


# Import des modèles v2 (ClientRating) — doit rester en bas pour éviter les imports circulaires
from .models_v2 import ClientRating  # noqa: E402, F401


class ClientFavorite(models.Model):
    """Prestataires favoris pour un client."""

    client = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="favoris",
    )
    provider = models.ForeignKey(
        Provider,
        on_delete=models.CASCADE,
        related_name="favoris_par",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ["client", "provider"]
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.client.username} ♥ {self.provider.nom}"


class Devis(models.Model):
    """Modèle de devis pour le nouveau parcours de réservation."""

    class Statut(models.TextChoices):
        BROUILLON = "BROUILLON", "Brouillon"
        ENVOYE = "ENVOYE", "Envoyé"
        ACCEPTE = "ACCEPTE", "Accepté"
        REFUSE = "REFUSE", "Refusé"
        EXPIRE = "EXPIRE", "Expiré"

    reference = models.CharField(max_length=20, unique=True)
    reservation = models.ForeignKey(
        "Reservation", on_delete=models.CASCADE, related_name="devis_set"
    )
    prestataire = models.ForeignKey(
        "Provider", on_delete=models.CASCADE, related_name="devis_crees"
    )

    diagnostic = models.TextField(help_text="Analyse du problème par le prestataire")

    date_proposee = models.DateField(null=True, blank=True)
    heure_debut = models.TimeField(null=True, blank=True)
    heure_fin = models.TimeField(null=True, blank=True)

    sous_total = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Total HT des lignes du devis = ce que le client paye",
    )
    commission_rate = models.IntegerField(
        default=18, help_text="Commission plateforme (15-20% recommandé)"
    )
    commission_montant = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Part BABIFIX, DÉDUITE du sous_total (jamais ajoutée au client)",
    )
    total_ttc = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Montant final payé par le client (= sous_total)",
    )
    net_prestataire = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Montant reversé au prestataire = sous_total - commission_montant",
    )

    note_prestataire = models.TextField(blank=True, default="")
    validite_jours = models.IntegerField(default=7)
    statut = models.CharField(
        max_length=20, choices=Statut.choices, default=Statut.BROUILLON
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def _recompute_totals(self):
        """Recalcule sous_total, commission, total_ttc et net_prestataire.

        Règle BABIFIX (confirmée par le métier) :
        - sous_total       = somme des lignes (HT)
        - total_ttc        = sous_total  (le client paye exactement le sous-total)
        - commission_montant = sous_total * commission_rate / 100  (notre part)
        - net_prestataire  = sous_total - commission_montant       (sa part)

        La commission est DÉDUITE de ce que reçoit le prestataire, JAMAIS
        ajoutée au prix payé par le client.

        C11 — Si le prestataire est sur un tier premium (silver/gold),
        on applique une réduction de commission cohérente avec
        `_get_effective_commission_rate` du WalletService. Le `commission_rate`
        stocké est celui effectivement appliqué (verrouillé à la création
        du devis pour ne pas changer si l'admin modifie le taux ensuite).
        """
        # Premium adjust — appliqué UNE SEULE FOIS quand le devis vient
        # d'être créé en brouillon ET que le taux est encore à la valeur
        # par défaut (jamais modifié). Verrouillé par le booléen interne
        # `_premium_adjusted` sur l'instance pour éviter une double
        # application dans la même session save().
        if (
            self.statut == self.Statut.BROUILLON
            and not getattr(self, "_premium_adjusted", False)
        ):
            try:
                prov = self.prestataire
                tier = (getattr(prov, "premium_tier", "") or "").lower()
                reduction = {"silver": 5, "gold": 10}.get(tier, 0)
                if reduction > 0 and self.commission_rate:
                    new_rate = max(5, int(self.commission_rate) - reduction)
                    self.commission_rate = new_rate
                self._premium_adjusted = True
            except Exception:
                pass

        sous_total = sum((ligne.total for ligne in self.lignes.all()), Decimal("0"))
        rate = Decimal(str(self.commission_rate or 0))
        commission = (sous_total * rate / Decimal("100")).quantize(Decimal("0.01"))
        self.sous_total = sous_total
        self.commission_montant = commission
        self.total_ttc = sous_total
        self.net_prestataire = sous_total - commission

    def save(self, *args, **kwargs):
        if not self.reference:
            year = timezone.now().year
            count = (
                Devis.objects.filter(reference__startswith=f"DEV-{year}").count() + 1
            )
            self.reference = f"DEV-{year}-{count:04d}"

        if self.pk:
            self._recompute_totals()

        super().save(*args, **kwargs)

        if self.lignes.exists():
            self._recompute_totals()
            super().save(
                update_fields=[
                    "sous_total",
                    "commission_montant",
                    "total_ttc",
                    "net_prestataire",
                ]
            )

    def __str__(self):
        return f"Devis {self.reference} - {self.reservation.title}"


class LigneDevis(models.Model):
    """Ligne de devis (fourniture, main d'œuvre, déplacement)."""

    class TypeLigne(models.TextChoices):
        FOURNITURE = "FOURNITURE", "Fourniture"
        MAIN_OEUVRE = "MAIN_OEUVRE", "Main d'œuvre"
        DEPLACEMENT = "DEPLACEMENT", "Déplacement"
        AUTRE = "AUTRE", "Autre"

    devis = models.ForeignKey(Devis, on_delete=models.CASCADE, related_name="lignes")
    type_ligne = models.CharField(max_length=20, choices=TypeLigne.choices)
    description = models.CharField(max_length=255)
    quantite = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=Decimal("1"),
        help_text=(
            "Quantité (peut être décimale : ex 2.5 m de tuyau, 1.5 h de main d'œuvre)."
        ),
    )
    prix_unitaire = models.DecimalField(max_digits=10, decimal_places=2)
    # Phase B — Devis catégoriel : enrichissement optionnel
    unite = models.CharField(
        max_length=16,
        blank=True,
        default="",
        help_text="Unité (u, m, m², m³, ml, kg, h, jour, forfait…) — affichage UI",
    )
    marque = models.CharField(
        max_length=80,
        blank=True,
        default="",
        help_text="Marque/référence matériau (optionnel, vue Kanban)",
    )
    catalogue_item = models.ForeignKey(
        "CatalogueItem",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="lignes_devis",
        help_text="Référence du catalogue catégorie si choisi via le catalogue",
    )

    @property
    def total(self):
        return self.quantite * self.prix_unitaire

    def __str__(self):
        return f"{self.description} x{self.quantite} = {self.total} francs CFA"


class CatalogueItem(models.Model):
    """Élément de catalogue par catégorie de métier (Phase B).

    Permet au prestataire de choisir rapidement un matériau/prestation type
    pour une catégorie donnée, sans interdire la saisie libre. Les prix
    sont indicatifs : le prestataire peut toujours les surcharger sur la
    ligne de devis.
    """

    category = models.ForeignKey(
        "Category",
        on_delete=models.CASCADE,
        related_name="catalogue_items",
    )
    type_ligne = models.CharField(
        max_length=20,
        choices=LigneDevis.TypeLigne.choices,
        default=LigneDevis.TypeLigne.FOURNITURE,
        help_text="Section devis (Fourniture / Main d'œuvre / Déplacement / Autre)",
    )
    nom = models.CharField(max_length=120)
    description = models.CharField(
        max_length=255, blank=True, default=""
    )
    unite = models.CharField(
        max_length=16,
        blank=True,
        default="u",
        help_text="u, m, m², m³, ml, kg, h, jour, forfait…",
    )
    prix_unitaire_indicatif = models.DecimalField(
        max_digits=10,
        decimal_places=2,
        default=Decimal("0"),
        help_text="Prix indicatif (XOF). Le prestataire peut surcharger.",
    )
    marque = models.CharField(
        max_length=80, blank=True, default=""
    )
    actif = models.BooleanField(default=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["category", "type_ligne", "nom"]
        indexes = [
            models.Index(fields=["category", "type_ligne", "actif"]),
        ]

    def __str__(self):
        return f"[{self.category_id}/{self.type_ligne}] {self.nom}"


class Call(models.Model):
    """Trace d'appel audio/vidéo LiveKit entre client et prestataire (Phase D).

    L'autorité de signalisation est le backend : c'est lui qui crée la
    room, envoie un FCM data-message `call.incoming` au destinataire et
    génère les tokens d'accès. Le SDK LiveKit côté app ne fait que
    rejoindre la room avec le token reçu.
    """

    class Status(models.TextChoices):
        RINGING = "RINGING", "Sonne"
        ANSWERED = "ANSWERED", "Décroché"
        REJECTED = "REJECTED", "Refusé"
        MISSED = "MISSED", "Manqué"
        ENDED = "ENDED", "Terminé"
        CANCELLED = "CANCELLED", "Annulé par l'appelant"

    class Kind(models.TextChoices):
        VOICE = "VOICE", "Audio"
        VIDEO = "VIDEO", "Vidéo"

    reservation = models.ForeignKey(
        "Reservation",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="calls",
    )
    caller = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="calls_initiated",
    )
    callee = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="calls_received",
    )
    room_name = models.CharField(max_length=80, unique=True)
    kind = models.CharField(
        max_length=8, choices=Kind.choices, default=Kind.VOICE
    )
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.RINGING, db_index=True
    )
    started_at = models.DateTimeField(auto_now_add=True)
    answered_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    duration_seconds = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-started_at"]
        indexes = [
            models.Index(fields=["caller", "-started_at"]),
            models.Index(fields=["callee", "-started_at"]),
            models.Index(fields=["reservation", "-started_at"]),
        ]

    def __str__(self):
        return f"Call {self.room_name} ({self.status})"


class Abonnement(models.Model):
    """Abonnement mensuel client - pack interventions."""

    class Statut(models.TextChoices):
        ACTIF = "actif", "Actif"
        EXPIRE = "expire", "Expiré"
        ANNULE = "annule", "Annulé"

    client = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name="abonnements",
    )
    pack_nom = models.CharField(max_length=50, default="3 interventions")
    pack_interventions = models.IntegerField(default=3)
    interventions_utilisees = models.IntegerField(default=0)
    prix = models.DecimalField(max_digits=10, decimal_places=2)
    date_debut = models.DateField()
    date_fin = models.DateField()
    statut = models.CharField(
        max_length=20, choices=Statut.choices, default=Statut.ACTIF
    )
    created_at = models.DateTimeField(auto_now_add=True)

    @property
    def interventions_restantes(self):
        return max(0, self.pack_interventions - self.interventions_utilisees)

    def peut_reserver(self):
        return self.statut == self.Statut.ACTIF and self.interventions_restantes > 0

    def __str__(self):
        return f"Abonnement {self.client.username} - {self.interventions_restantes}/{self.pack_interventions} restants"


class PlatformRevenue(models.Model):
    """Revenus de la plateforme BABIFIX (commission, abonnements premium, pénalités)."""

    class Source(models.TextChoices):
        COMMISSION = "commission", "Commission prestation"
        PREMIUM = "premium", "Abonnement premium"
        PENALITE = "penalite", "Pénalité"
        AUTRE = "autre", "Autre"

    amount_fcfa = models.DecimalField(max_digits=14, decimal_places=2)
    source = models.CharField(max_length=20, choices=Source.choices, default=Source.COMMISSION)
    reference = models.CharField(max_length=100, blank=True, default="")
    description = models.TextField(blank=True, default="")
    payment = models.ForeignKey(
        Payment,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="platform_revenues",
    )
    # C1 — Annulation : si une commission cash a été encaissée puis l'annulation
    # autorise un remboursement, on marque l'entrée comme `refunded_at` pour
    # l'exclure des dashboards de revenus.
    refunded_at = models.DateTimeField(null=True, blank=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Revenu {self.source} {self.amount_fcfa} FCFA"
