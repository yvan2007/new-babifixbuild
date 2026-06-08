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
        help_text="Abonnement premium payant actif (silver/gold)",
    )
    premium_tier = models.CharField(
        max_length=20,
        blank=True,
        default="",
        choices=[
            ("standard", "Standard"),
            ("silver", "Silver"),
            ("gold", "Gold"),
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
    # Privacy-by-design : horodatage de purge des images d'identité (selfie +
    # CNI recto/verso). Une fois le dossier traité, on ne garde plus les images
    # brutes — seulement le résultat, le numéro masqué et la date d'expiration.
    kyc_documents_purged_at = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Date de suppression des images d'identité (minimisation des données).",
    )

    def __str__(self):
        return self.nom

    # ── KYC : rétention & re-vérification ────────────────────────────────
    def purge_kyc_documents(self) -> bool:
        """Supprime les images d'identité brutes (selfie + CNI) tout en gardant
        la trace de vérification. Idempotent. Retourne True si une purge a eu lieu.

        Minimisation des données : une CNI/selfie n'a aucune raison d'être
        conservée indéfiniment une fois le dossier approuvé ou rejeté.
        """
        had_data = any([
            self.kyc_cni_recto_url,
            self.kyc_cni_verso_url,
            self.kyc_selfie_url,
            self.cni_url,
            self.cni_recto_url,
            self.cni_verso_url,
            self.selfie_url,
        ])
        if not had_data:
            return False
        self.kyc_cni_recto_url = ""
        self.kyc_cni_verso_url = ""
        self.kyc_selfie_url = ""
        self.cni_url = ""
        self.cni_recto_url = ""
        self.cni_verso_url = ""
        self.selfie_url = ""
        self.kyc_documents_purged_at = timezone.now()
        self.save(update_fields=[
            "kyc_cni_recto_url", "kyc_cni_verso_url", "kyc_selfie_url",
            "cni_url", "cni_recto_url", "cni_verso_url", "selfie_url",
            "kyc_documents_purged_at",
        ])
        return True

    def kyc_masked_cni(self) -> str:
        """Numéro de CNI masqué pour l'affichage admin (ex. 'CI•••••789')."""
        n = (self.kyc_cni_number or "").strip()
        if len(n) <= 4:
            return "•" * len(n)
        return n[:2] + "•" * (len(n) - 5) + n[-3:]

    def kyc_needs_reverification(self) -> bool:
        """True si le dossier est approuvé mais la CNI a expiré : il faut
        redemander une pièce valide au prestataire."""
        from datetime import date
        if self.kyc_status != "approved":
            return False
        if not self.kyc_cni_expiry:
            return False
        return self.kyc_cni_expiry < date.today()


class WalletTransaction(models.Model):
    """Historique des mouvements du wallet prestataire."""

    class TxType(models.TextChoices):
        CREDIT = "credit", "Crédit (paiement reçu)"
        DEBIT = "debit", "Débit (retrait)"
        COMMISSION = "commission", "Commission BABIFIX"
        REFUND = "refund", "Remboursement"

    class TxStatus(models.TextChoices):
        PENDING = "pending", "En attente"
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
    # `address_label` reste le résumé compact « Rue, Quartier, Ville »
    # affiché par défaut ; les 5 champs ci-dessous permettent un affichage
    # structuré et pro côté prestataire (chacun avec son icône).
    address_label = models.CharField(max_length=500, blank=True, default="")
    address_street = models.CharField(max_length=200, blank=True, default="")
    address_quartier = models.CharField(max_length=120, blank=True, default="")
    address_ville = models.CharField(max_length=120, blank=True, default="")
    address_pays = models.CharField(max_length=80, blank=True, default="Côte d'Ivoire")
    # Repère textuel saisi librement par le client (« à côté de la pharmacie
    # XYZ », « en face de l'école Sainte-Marie », etc.) — pas géocodable.
    address_repere = models.CharField(max_length=300, blank=True, default="")
    # L'adresse affichee au prestataire est-elle encore approximative ?
    # True tant que le prestataire n'a pas accepte la demande : on masque
    # les details fins (rue, repere) pour proteger la vie privee du client.
    address_is_approximate = models.BooleanField(default=False)
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
    # Séquestre : horodatage de libération des fonds vers le prestataire.
    # Null = fonds encore bloqués. Set par EscrowService.release_funds après
    # confirmation client. Sert aussi de garde d'idempotence.
    funds_released_at = models.DateTimeField(
        blank=True,
        null=True,
        help_text=(
            "Horodatage de libération escrow. Null = fonds encore bloqués. "
            "Set après client_confirme_prestation_at via EscrowService.release_funds."
        ),
    )
    # Remboursement dû au client (annulation / litige tranché en sa faveur),
    # en attente de virement manuel par l'admin.
    refund_owed_fcfa = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Montant que la plateforme doit rembourser au client (en attente admin)",
    )
    refund_paid_at = models.DateTimeField(
        blank=True,
        null=True,
        help_text="Set par l'admin une fois le remboursement effectivement viré",
    )
    refund_status = models.CharField(
        max_length=12,
        blank=True,
        default="",
        help_text="'' | processing | paid | failed | manual — état du remboursement client.",
    )
    refund_reference = models.CharField(
        max_length=80,
        blank=True,
        default="",
        help_text="Référence externe du versement de remboursement (GeniusPay).",
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
    # B2B — rattachement éventuel à un site géré par un compte professionnel
    pro_site = models.ForeignKey(
        "ProSite",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="reservations",
        help_text="Site B2B concerné (intervention déclarée par un compte pro)",
    )
    # Programme de fidélité : points déjà attribués au client pour cette prestation ?
    fidelite_awarded = models.BooleanField(default=False)
    # Flux paiement après prestation (UML + plan BABIFIX)
    prestation_terminee_at = models.DateTimeField(null=True, blank=True)
    client_confirme_prestation_at = models.DateTimeField(null=True, blank=True)
    preuve_photos = models.JSONField(default=list, blank=True)
    dispute_ouverte = models.BooleanField(default=False, db_index=True)
    payment_client_note = models.TextField(
        blank=True,
        default="",
        help_text="Message optionnel du client au moment du paiement",
    )
    # Journal client (témoignage, photos avant/apres)
    client_journal_note = models.TextField(
        blank=True, default="",
        help_text="Commentaire libre du client à la fin de l'intervention",
    )
    client_journal_updated_at = models.DateTimeField(blank=True, null=True)
    client_photos_avant = models.JSONField(blank=True, default=list)
    client_photos_apres = models.JSONField(blank=True, default=list)

    def __str__(self):
        return self.reference

    def contact_allowed(self) -> bool:
        """Appel / message autorisés UNIQUEMENT après accord entre les deux
        acteurs : le prestataire a accepté la demande (statut au-delà de
        DEMANDE_ENVOYEE), et la réservation n'est ni en attente ni annulée.

        Tant que c'est False : ni le client ni le prestataire ne peuvent
        s'appeler ou s'envoyer un message — protège le prestataire du démarchage
        avant qu'il se soit engagé.
        """
        blocked = {
            Reservation.Status.DEMANDE_ENVOYEE,
            Reservation.Status.PENDING,
            Reservation.Status.CANCELLED,
        }
        return self.statut not in blocked

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
                # Priorité au devis ACCEPTÉ (un seul possible) ; sinon dernier
                # ENVOYÉ ; sinon fallback historique 18 %. Empêche qu'un nouveau
                # ENVOYÉ posté après acceptation écrase la commission négociée.
                devis = (
                    self.devis_set.filter(statut="ACCEPTE")
                    .order_by("-created_at")
                    .first()
                    or self.devis_set.filter(statut="ENVOYE")
                    .order_by("-created_at")
                    .first()
                )
                if devis and devis.commission_montant:
                    self.commission = Decimal(str(devis.commission_montant))
                else:
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

    reference = models.CharField(max_length=40, unique=True)
    motif = models.CharField(max_length=200)
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
    # Catégorie du litige (sélection client à l'ouverture).
    categorie = models.CharField(
        max_length=32,
        db_index=True,
        default="autre",
        choices=[
            ("travail_non_fait", "Travail non réalisé"),
            ("travail_bacle", "Travail bâclé / mal fait"),
            ("presta_absent", "Prestataire absent / pas venu"),
            ("retard", "Retard important"),
            ("prix_non_conforme", "Prix non conforme au devis"),
            ("degats", "Dégâts causés"),
            ("comportement", "Comportement inapproprié"),
            ("autre", "Autre"),
        ],
    )
    # Preuves jointes par chaque partie (URLs d'images).
    photos_client = models.JSONField(blank=True, default=list)
    photos_prestataire = models.JSONField(blank=True, default=list)
    # Version du prestataire (droit de réponse au litige).
    prestataire_response = models.TextField(blank=True, default="")
    prestataire_response_at = models.DateTimeField(blank=True, null=True)
    # Décision admin (traçabilité).
    decided_at = models.DateTimeField(blank=True, null=True)
    decided_by = models.ForeignKey(
        User,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="disputes_decided",
    )
    decision_note = models.TextField(blank=True, default="")
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
        help_text="Commission en francs CFA",
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
        help_text=" Référence GeniusPay ou autre externe",
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
    created_at = models.DateTimeField(
        default=timezone.now,
        db_index=True,
        help_text="Date de création du paiement",
    )

    def __str__(self):
        return self.reference


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


class ClientSavedAddress(models.Model):
    """Carnet d'adresses du client (Maison, Bureau, Chez maman…).

    Permet de NE PAS confondre « où je suis maintenant » et « où doit avoir lieu
    l'intervention ». Le client peut enregistrer plusieurs lieux et les réutiliser
    au moment de réserver, plutôt que d'envoyer systématiquement sa position GPS.
    """
    user = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name="babifix_saved_addresses"
    )
    label = models.CharField(
        max_length=60, help_text="Nom du lieu : Maison, Bureau, Chez maman…"
    )
    latitude = models.FloatField()
    longitude = models.FloatField()
    address_label = models.CharField(max_length=255, blank=True, default="")
    address_repere = models.CharField(
        max_length=300, blank=True, default="",
        help_text="Repère textuel : « à côté de la pharmacie X »",
    )
    is_default = models.BooleanField(
        default=False, help_text="Adresse proposée en premier (domicile principal)."
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-is_default", "-updated_at"]
        indexes = [models.Index(fields=["user", "is_default"])]

    def __str__(self):
        return f"{self.label} ({self.user_id})"


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
    # Programme de fidélité client (points cumulés à chaque prestation terminée)
    points_fidelite = models.PositiveIntegerField(
        default=0,
        help_text="Points de fidélité cumulés (1 point par tranche de 1 000 FCFA dépensée)",
    )
    fidelite_credit_fcfa = models.DecimalField(
        max_digits=10, decimal_places=2, default=0,
        help_text="Crédit de réduction obtenu en convertissant des points de fidélité",
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


class Call(models.Model):
    """Appel audio/vidéo entre client et prestataire (via LiveKit).

    Le modèle a été perdu lors d'une migration mais la table
    `adminpanel_call` existe encore en DB — on la remappe.
    """
    class Kind(models.TextChoices):
        VOICE = "VOICE", "Audio"
        VIDEO = "VIDEO", "Vidéo"

    class Status(models.TextChoices):
        RINGING  = "RINGING",  "Sonne"
        ANSWERED = "ANSWERED", "Décroché"
        REJECTED = "REJECTED", "Refusé"
        ENDED    = "ENDED",    "Terminé"
        MISSED   = "MISSED",   "Manqué"

    room_name = models.CharField(max_length=80, default="")
    kind = models.CharField(max_length=8, choices=Kind.choices, default=Kind.VOICE)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.RINGING)

    caller = models.ForeignKey(
        "auth.User", on_delete=models.CASCADE,
        related_name="calls_initiated",
    )
    callee = models.ForeignKey(
        "auth.User", on_delete=models.CASCADE,
        related_name="calls_received",
    )
    reservation = models.ForeignKey(
        "Reservation", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="calls",
    )

    started_at = models.DateTimeField(auto_now_add=True)
    answered_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    duration_seconds = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["-id"]
        verbose_name = "Appel"
        verbose_name_plural = "Appels"


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
    # Type de message : USER = libre ; DEVIS_CARD = devis figé ancré au fil ;
    # SYSTEM = événement (démarrage/fin/paiement). Permet d'injecter cartes
    # devis et événements dans le fil de chat unique de chaque réservation.
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
    # Données structurées pour les messages DEVIS_CARD / SYSTEM
    # (montants, références, statuts…).
    payload_json = models.JSONField(
        blank=True,
        null=True,
        help_text=(
            "Données structurées pour les messages DEVIS_CARD/SYSTEM "
            "(montants, références, statuts…)."
        ),
    )
    image = models.ImageField(upload_to="babifix_chat/", blank=True)
    # Note vocale (enregistrement audio envoyé dans le fil, façon WhatsApp).
    audio = models.FileField(upload_to="babifix_chat_audio/", blank=True)
    audio_duration = models.PositiveIntegerField(
        default=0, help_text="Durée de la note vocale en secondes (affichage UI)."
    )
    reply_to = models.ForeignKey(
        "self",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="replies",
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

    sous_total = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    commission_rate = models.IntegerField(
        default=18, help_text="Commission plateforme (15-20% recommandé)"
    )
    commission_montant = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    net_prestataire = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    remise = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        default=0,
        help_text="Remise commerciale accordée au client (déduite du sous-total).",
    )
    total_ttc = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    # Photos jointes par le prestataire au devis (diagnostic visuel).
    photos_prestataire = models.JSONField(blank=True, default=list)

    note_prestataire = models.TextField(blank=True, default="")
    validite_jours = models.IntegerField(default=7)
    statut = models.CharField(
        max_length=20, choices=Statut.choices, default=Statut.BROUILLON
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def save(self, *args, **kwargs):
        if not self.reference:
            year = timezone.now().year
            # On regarde le PLUS GRAND numéro existant (et pas le count) pour
            # éviter les doublons quand un devis a été supprimé : count() ne
            # « rebouchait » pas les trous, ce qui causait des UNIQUE conflicts.
            from django.db.models import Max
            prefix = f"DEV-{year}-"
            last_ref = (
                Devis.objects
                .filter(reference__startswith=prefix)
                .aggregate(m=Max("reference"))
                .get("m")
            )
            if last_ref:
                try:
                    last_n = int(last_ref.split("-")[-1])
                except (ValueError, IndexError):
                    last_n = 0
            else:
                last_n = 0
            next_n = last_n + 1
            # Garde-fou : si par hasard la ref existe quand même (course condition),
            # on incrémente jusqu'à trouver un libre.
            while Devis.objects.filter(reference=f"{prefix}{next_n:04d}").exists():
                next_n += 1
            self.reference = f"{prefix}{next_n:04d}"

        if self.pk:
            self.sous_total = sum(ligne.total for ligne in self.lignes.all())
            self.commission_montant = self.sous_total * self.commission_rate / 100
            # Façon B : le client paie le prix annoncé ; la commission est déduite
            # de la part du prestataire (jamais ajoutée au client).
            self.total_ttc = self.sous_total
            self.net_prestataire = self.total_ttc - self.commission_montant

        super().save(*args, **kwargs)

        if not self.pk:
            self.pk = self.id
        if self.lignes.exists():
            self.sous_total = sum(ligne.total for ligne in self.lignes.all())
            self.commission_montant = self.sous_total * self.commission_rate / 100
            # Façon B : le client paie le prix annoncé ; la commission est déduite
            # de la part du prestataire (jamais ajoutée au client).
            self.total_ttc = self.sous_total
            self.net_prestataire = self.total_ttc - self.commission_montant
            super().save(
                update_fields=["sous_total", "commission_montant", "total_ttc", "net_prestataire"]
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
    quantite = models.IntegerField(default=1)
    prix_unitaire = models.DecimalField(max_digits=10, decimal_places=2)
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

    @property
    def total(self):
        return self.quantite * self.prix_unitaire

    def __str__(self):
        return f"{self.description} x{self.quantite} = {self.total} francs CFA"


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
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Revenu {self.source} {self.amount_fcfa} FCFA"


# =============================================================================
# B2B — BABIFIX Pro (syndics, entreprises, agences immobilières)
# Offre multi-sites + facturation mensuelle groupée + commission réduite + SLA
# =============================================================================

class ProAccount(models.Model):
    """Compte professionnel B2B (un syndic / une entreprise gérant plusieurs sites)."""

    class Formule(models.TextChoices):
        STARTER = "starter", "Starter"          # 1-5 sites
        BUSINESS = "business", "Business"        # 5-20 sites
        ENTERPRISE = "enterprise", "Enterprise"  # 20+ sites

    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name="babifix_pro_account",
        help_text="Compte de connexion du gestionnaire B2B",
    )
    raison_sociale = models.CharField(max_length=200)
    contact_nom = models.CharField(max_length=120, blank=True, default="")
    contact_telephone = models.CharField(max_length=30, blank=True, default="")
    contact_email = models.EmailField(blank=True, default="")
    formule = models.CharField(
        max_length=20, choices=Formule.choices, default=Formule.STARTER
    )
    commission_rate = models.PositiveSmallIntegerField(
        default=10, help_text="Commission B2B en % (Starter 10, Business 8, Enterprise négociée)"
    )
    sla_heures = models.PositiveSmallIntegerField(
        default=24, help_text="Délai d'intervention contractuel en heures"
    )
    abonnement_mensuel_fcfa = models.DecimalField(
        max_digits=12, decimal_places=2, default=0,
        help_text="Abonnement mensuel récurrent (SaaS B2B)",
    )
    actif = models.BooleanField(default=True, db_index=True)
    jour_facturation = models.PositiveSmallIntegerField(
        default=1, help_text="Jour du mois où la facture groupée est émise (1-28)"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["raison_sociale"]

    def __str__(self):
        return f"{self.raison_sociale} ({self.get_formule_display()})"


class ProSite(models.Model):
    """Site / immeuble géré par un compte B2B."""

    pro_account = models.ForeignKey(
        ProAccount, on_delete=models.CASCADE, related_name="sites"
    )
    nom = models.CharField(max_length=200, help_text="Ex : Résidence Les Palmiers, Bât. A")
    adresse = models.CharField(max_length=500, blank=True, default="")
    commune = models.CharField(max_length=120, blank=True, default="")
    latitude = models.FloatField(null=True, blank=True)
    longitude = models.FloatField(null=True, blank=True)
    contact_sur_site = models.CharField(max_length=120, blank=True, default="")
    telephone_sur_site = models.CharField(max_length=30, blank=True, default="")
    actif = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["pro_account", "nom"]

    def __str__(self):
        return f"{self.nom} — {self.pro_account.raison_sociale}"


class ProInvoice(models.Model):
    """Facture mensuelle groupée d'un compte B2B (interventions + abonnement)."""

    class Statut(models.TextChoices):
        BROUILLON = "brouillon", "Brouillon"
        EMISE = "emise", "Émise"
        PAYEE = "payee", "Payée"

    pro_account = models.ForeignKey(
        ProAccount, on_delete=models.CASCADE, related_name="invoices"
    )
    reference = models.CharField(max_length=40, unique=True, blank=True, default="")
    periode = models.CharField(max_length=7, help_text="Mois facturé, format AAAA-MM")
    nombre_interventions = models.PositiveIntegerField(default=0)
    montant_interventions_fcfa = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    abonnement_fcfa = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    total_fcfa = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    statut = models.CharField(max_length=20, choices=Statut.choices, default=Statut.BROUILLON)
    detail = models.JSONField(default=list, blank=True, help_text="Lignes : par site / intervention")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        unique_together = ("pro_account", "periode")

    def save(self, *args, **kwargs):
        if not self.reference:
            from django.utils import timezone as _tz
            self.reference = f"PRO-{self.periode}-{self.pro_account_id or 0:04d}"
        super().save(*args, **kwargs)

    def __str__(self):
        return f"Facture {self.reference} — {self.total_fcfa} FCFA"
