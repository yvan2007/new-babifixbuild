# Serializers BABIFIX - DRF strict serializers
#
# Serializers avec validation stricte:
# - Champs explicites (pas __all__)
# - Validation automatique
# - Compatible drf-spectacular pour OpenAPI
#
# Usage:
#   from adminpanel.serializers import ReservationSerializer
#   serializer = ReservationSerializer(data=request.data)
#   if serializer.is_valid():
#       ...

try:
    from rest_framework import serializers
    from rest_framework.exceptions import ValidationError as RFValidationError
except ImportError:
    raise ImportError(
        "Django REST Framework required. Install with: pip install djangorestframework"
    )

from django.contrib.auth.models import User
from django.db.models import Sum

from ..models import (
    Category,
    Provider,
    Reservation,
    Devis,
    Payment,
    Notification,
    UserProfile,
)


class CategorySerializer(serializers.ModelSerializer):
    """Serializer pour les categories."""
    
    class Meta:
        model = Category
        fields = [
            "id",
            "name",
            "slug",
            "icon",
            "description",
            "parent",
        ]
        read_only_fields = ["id"]
    
    def validate_name(self, value):
        if not value or not value.strip():
            raise serializers.ValidationError("Name is required")
        return value.strip()


class ProviderListSerializer(serializers.ModelSerializer):
    """Serializer pour liste des prestataires."""
    
    categories_names = serializers.SerializerMethodField()
    
    class Meta:
        model = Provider
        fields = [
            "id",
            "nom",
            "photo",
            "note_moyenne",
            "nombre_notes",
            "categories_names",
            "disponible",
            "tarif_horaire",
            "commune",
        ]
        read_only_fields = fields
    
    def get_categories_names(self, obj):
        return [c.name for c in obj.categories.all()[:3]]


class ProviderDetailSerializer(serializers.ModelSerializer):
    """Serializer pour detail prestataire."""
    
    categories = CategorySerializer(many=True, read_only=True)
    completed_missions = serializers.SerializerMethodField()
    rating_breakdown = serializers.SerializerMethodField()
    
    class Meta:
        model = Provider
        fields = [
            "id",
            "nom",
            "photo",
            "description",
            "note_moyenne",
            "nombre_notes",
            "categories",
            "disponible",
            "tarif_horaire",
            "adresse",
            "commune",
            "telephone",
            "completed_missions",
            "rating_breakdown",
            "created_at",
        ]
        read_only_fields = fields
    
    def get_completed_missions(self, obj):
        return Reservation.objects.filter(
            provider=obj,
            statut=Reservation.Statut.TERMINEE,
        ).count()
    
    def get_rating_breakdown(self, obj):
        # Retourner la repartition des notes
        return {
            "5": obj.nb_5_etoiles,
            "4": obj.nb_4_etoiles,
            "3": obj.nb_3_etoiles,
            "2": obj.nb_2_etoiles,
            "1": obj.nb_1_etoile,
        }


class ReservationCreateSerializer(serializers.Serializer):
    """Serializer pour creation de reservation."""
    
    title = serializers.CharField(max_length=200)
    category_id = serializers.IntegerField(min_value=1)
    provider_id = serializers.IntegerField(required=False, allow_null=True)
    description = serializers.CharField(
        required=False,
        allow_blank=True,
        max_length=2000,
    )
    address_label = serializers.CharField(
        required=False,
        allow_blank=True,
        max_length=500,
    )
    latitude = serializers.FloatField(required=False, allow_null=True)
    longitude = serializers.FloatField(required=False, allow_null=True)
    payment_type = serializers.ChoiceField(
        required=False,
        choices=[
            "ESPECES",
            "MOBILE_MONEY",
            "CARTE",
            "AUTRE",
        ],
        default="ESPECES",
    )
    prix_propose = serializers.FloatField(required=False, allow_null=True)
    photo_attachments = serializers.ListField(
        required=False,
        child=serializers.CharField(max_length=600000),
        max_length=6,
    )
    
    def validate_title(self, value):
        if not value or not value.strip():
            raise serializers.ValidationError("Title is required")
        return value.strip()
    
    def validate_category_id(self, value):
        if not Category.objects.filter(id=value, active=True).exists():
            raise serializers.ValidationError("Invalid category")
        return value
    
    def validate_provider_id(self, value):
        if value is not None:
            if not Provider.objects.filter(id=value, statut=Provider.Status.VALID).exists():
                raise serializers.ValidationError("Invalid provider")
        return value


class ReservationListSerializer(serializers.ModelSerializer):
    """Serializer pour liste des reservations."""
    
    category_name = serializers.SerializerMethodField()
    provider_name = serializers.SerializerMethodField()
    
    class Meta:
        model = Reservation
        fields = [
            "reference",
            "title",
            "statut",
            "category_name",
            "provider_name",
            "created_at",
            "updated_at",
            "prix_propose",
            "address_label",
        ]
        read_only_fields = fields
    
    def get_category_name(self, obj):
        return obj.category.name if obj.category else None
    
    def get_provider_name(self, obj):
        return obj.provider.nom if obj.provider else None


class ReservationDetailSerializer(serializers.ModelSerializer):
    """Serializer pour detail d'une reservation."""
    
    category = CategorySerializer(read_only=True)
    provider = ProviderListSerializer(read_only=True)
    client_name = serializers.SerializerMethodField()
    devisions = serializers.SerializerMethodField()
    payment = serializers.SerializerMethodField()
    
    class Meta:
        model = Reservation
        fields = [
            "reference",
            "title",
            "description",
            "statut",
            "category",
            "provider",
            "client_name",
            "address_label",
            "latitude",
            "longitude",
            "payment_type",
            "prix_propose",
            "photo_attachments",
            "devisions",
            "payment",
            "created_at",
            "updated_at",
            "completed_at",
        ]
        read_only_fields = fields
    
    def get_client_name(self, obj):
        return obj.client.get_full_name() or obj.client.username
    
    def get_devisions(self, obj):
        devisions = Devis.objects.filter(reservation=obj)
        return [{"id": d.id, "status": d.statut} for d in devisions]
    
    def get_payment(self, obj):
        payment = Payment.objects.filter(reservation=obj).first()
        if payment:
            return {
                "amount": payment.amount,
                "method": payment.payment_method,
                "status": payment.statut,
                "paid_at": payment.paid_at,
            }
        return None


class DevisCreateSerializer(serializers.Serializer):
    """Serializer pour creation de devis."""
    
    diagnostic = serializers.CharField(max_length=2000)
    date_proposee = serializers.DateField()
    lignes = serializers.ListField(
        child=serializers.DictField(),
        min_length=1,
        max_length=20,
    )
    
    def validate_lignes(self, value):
        for ligne in value:
            if "description" not in ligne:
                raise serializers.ValidationError("Line must have description")
            if "type_ligne" not in ligne:
                raise serializers.ValidationError("Line must have type")
            if "quantite" not in ligne or ligne["quantite"] < 1:
                raise serializers.ValidationError("Invalid quantity")
            if "prix_unitaire" not in ligne or ligne["prix_unitaire"] < 0:
                raise serializers.ValidationError("Invalid price")
        return value
    
    def validate_date_proposee(self, value):
        from datetime import date
        if value < date.today():
            raise serializers.ValidationError("Date must be in the future")
        return value


class DevisSerializer(serializers.ModelSerializer):
    """Serializer pour un devis."""
    
    provider_name = serializers.SerializerMethodField()
    total = serializers.SerializerMethodField()
    
    class Meta:
        model = Devis
        fields = [
            "id",
            "provider_name",
            "diagnostic",
            "date_proposee",
            "lignes",
            "total",
            "statut",
            "created_at",
        ]
        read_only_fields = fields
    
    def get_provider_name(self, obj):
        return obj.provider.nom if obj.provider else None
    
    def get_total(self, obj):
        total = 0
        for ligne in obj.lignes or []:
            qty = ligne.get("quantite", 1)
            prix = ligne.get("prix_unitaire", 0)
            total += qty * prix
        return total


class PaymentCreateSerializer(serializers.Serializer):
    """Serializer pour creation de paiement."""
    
    payment_method_id = serializers.ChoiceField(
        choices=[
            "ESPECES",
            "MOBILE_MONEY",
            "CARTE",
            "ORANGE_MONEY",
            "MTN_MONEY",
        ],
    )
    amount = serializers.FloatField(min_value=0)
    message = serializers.CharField(
        required=False,
        allow_blank=True,
        max_length=500,
    )
    
    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError("Amount must be positive")
        return value


class PaymentSerializer(serializers.ModelSerializer):
    """Serializer pour un paiement."""
    
    reservation_ref = serializers.SerializerMethodField()
    provider_name = serializers.SerializerMethodField()
    
    class Meta:
        model = Payment
        fields = [
            "id",
            "reservation_ref",
            "provider_name",
            "amount",
            "payment_method",
            "statut",
            "paid_at",
            "message",
        ]
        read_only_fields = fields
    
    def get_reservation_ref(self, obj):
        return obj.reservation.reference if obj.reservation else None
    
    def get_provider_name(self, obj):
        return obj.provider.nom if obj.provider else None


class NotificationSerializer(serializers.ModelSerializer):
    """Serializer pour notification."""
    
    class Meta:
        model = Notification
        fields = [
            "id",
            "title",
            "message",
            "type",
            "link",
            "is_read",
            "created_at",
        ]
        read_only_fields = fields
        extra_kwargs = {
            "message": {"required": False},
        }


class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer pour profil utilisateur."""
    
    username = serializers.CharField(source="user.username", read_only=True)
    email = serializers.CharField(source="user.email", read_only=True)
    full_name = serializers.SerializerMethodField()
    
    class Meta:
        model = UserProfile
        fields = [
            "username",
            "email",
            "full_name",
            "telephone",
            "photo",
            "commune",
            "quartier",
        ]
        read_only_fields = fields
    
    def get_full_name(self, obj):
        return obj.user.get_full_name()


class RatingSerializer(serializers.Serializer):
    """Serializer pour notation."""
    
    rating = serializers.IntegerField(min_value=1, max_value=5)
    comment = serializers.CharField(
        required=False,
        allow_blank=True,
        max_length=1000,
    )


class ReservationStatusTransitionSerializer(serializers.Serializer):
    """Serializer pour transition de statut."""
    
    new_status = serializers.CharField(max_length=50)
    reason = serializers.CharField(
        required=False,
        allow_blank=True,
        max_length=500,
    )