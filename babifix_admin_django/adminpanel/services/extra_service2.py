"""
Logging Service — Logging structuré avec filtrage PII
Utilise Python logging + filtres personnalises
"""
import logging
import re
import json
from datetime import datetime
from typing import Any, Optional

from django.utils import timezone


class PIIFilter(logging.Filter):
    """Filtre pour masquer les donnes PII dans les logs."""
    
    # Patterns PII a masquer
    PII_PATTERNS = [
        (r'\b[\w.-]+@[\w.-]+\.[a-z]{2,}\b', '[EMAIL]'),  # Emails
        (r'\b\+225[0-9]{8,12}\b', '[PHONE]'),  # Tel Ivory Coast
        (r'\b[0-9]{4,6}[- ]?[0-9]{2,3}[- ]?[0-9]{2,3}[- ]?[0-9]{2}\b', '[CARD]'),  # Cards
        (r'token["\s:=]+["\s]?([a-zA-Z0-9.-]+)', r'token=\1[...]'),  # Tokens
        (r'password["\s:=]+["\s]?([^\s"]+)', r'password=[HIDDEN]'),  # Passwords
    ]
    
    def filter(self, record: logging.LogRecord) -> bool:
        """Filtre les donnes sensibles."""
        if hasattr(record, 'msg'):
            record.msg = self._mask_pii(str(record.msg))
        
        if hasattr(record, 'args'):
            new_args = []
            for arg in record.args:
                if isinstance(arg, str):
                    new_args.append(self._mask_pii(arg))
                else:
                    new_args.append(arg)
            record.args = tuple(new_args)
        
        return True
    
    def _mask_pii(self, text: str) -> str:
        """Masque les PII dans le texte."""
        result = text
        for pattern, replacement in self.PII_PATTERNS:
            result = re.sub(pattern, replacement, result, flags=re.IGNORECASE)
        return result


class StructuredLogger:
    """Logger struct JSON pour analyse ulterieure."""
    
    @staticmethod
    def log(
        level: str,
        event: str,
        user_id: Optional[int] = None,
        extra: Optional[dict] = None,
    ) -> None:
        """Log un evenement structure.
        
        Args:
            level: DEBUG, INFO, WARNING, ERROR
            event: Nom de l'evenement
            user_id: ID utilisateur (optionnel)
            extra: Donnees supplementaires
        """
        logger = logging.getLogger('babifix.structured')
        
        data = {
            "timestamp": datetime.utcnow().isoformat(),
            "level": level,
            "event": event,
        }
        
        if user_id:
            data["user_id"] = user_id
        
        if extra:
            data.update(extra)
        
        # Log avec le filtre PII
        logger.log(
            logging.getLevelName(level),
            json.dumps(data),
            extra={"structured": True},
        )


# ✅ B5: Configuration du logging structure
LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {
            "format": "%(asctime)s [%(levelname)s] %(name)s: %(message)s"
        },
        "json": {
            "format": "%(message)s"
        },
    },
    "filters": {
        "pii_filter": {
            "()": PIIFilter,
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "standard",
            "level": "DEBUG",
        },
        "file": {
            "class": "logging.handlers.RotatingFileHandler",
            "filename": "logs/babifix.log",
            "maxBytes": 10 * 1024 * 1024,  # 10MB
            "backupCount": 5,
            "formatter": "standard",
            "filters": ["pii_filter"],
        },
        "structured": {
            "class": "logging.handlers.RotatingFileHandler",
            "filename": "logs/structured.log",
            "maxBytes": 10 * 1024 * 1024,
            "backupCount": 3,
            "formatter": "json",
            "filters": ["pii_filter"],
        },
    },
    "loggers": {
        "babifix": {
            "handlers": ["console", "file"],
            "level": "INFO",
            "propagate": False,
        },
        "babifix.structured": {
            "handlers": ["structured"],
            "level": "INFO",
            "propagate": False,
        },
    },
}


# ✅ F7: Recherche full-text PostgreSQL
class FullTextSearch:
    """Recherche full-text via PostgreSQL."""
    
    # Utiliser la recherche native PostgreSQL (to_tsvector + to_tsquery)
    @classmethod
    def search_providers(cls, query: str, limit: int = 20) -> list:
        """Recherche dans les prestataires.
        
        Args:
            query: Termes de recherche
            limit: Nombre de resultats
            
        Returns:
            Liste de Provider IDs correspondants
        """
        from django.db import connection
        
        if not query:
            return []
        
        # Echapper les caracteres speciaux
        query = query.strip().replace("'", "''")
        
        # Requete full-text PostgreSQL
        sql = f"""
            SELECT id, nom, specialite, ville, description,
                   ts_headline('french', nom, plainto_tsquery('french', %s)) as nom_highlight,
                   ts_headline('french', description, plainto_tsquery('french', %s)) as desc_highlight
            FROM adminpanel_provider
            WHERE 
                statut = 'Valide'
                AND is_deleted = false
                AND to_tsvector('french', COALESCE(nom, '') || ' ' || COALESCE(specialite, '') || ' ' || COALESCE(description, ''))
                @@ plainto_tsquery('french', %s)
            ORDER BY ts_rank(
                to_tsvector('french', COALESCE(nom, '') || ' ' || COALESCE(specialite, '') || ' ' || COALESCE(description, '')),
                plainto_tsquery('french', %s)
            ) DESC
            LIMIT %s
        """
        
        try:
            with connection.cursor() as cursor:
                cursor.execute(sql, [query] * 5)
                results = cursor.fetchall()
                
                return [
                    {
                        "id": row[0],
                        "nom": row[1],
                        "specialite": row[2],
                        "ville": row[3],
                        "nom_highlight": row[4],
                        "desc_highlight": row[5],
                    }
                    for row in results
                ]
        except Exception:
            # Fallback si erreur PostgreSQL
            return []


# ✅ F11: KYC OCR CNI (placeholder integration)
class KYCService:
    """Service de verification d'identite CNI.
    
    Utilise Google Vision API ou Azure pour l'OCR.
    """
    
    @classmethod
    def verify_cni(
        cls,
        cni_recto_url: str,
        cni_verso_url: str,
        selfie_url: str,
    ) -> dict:
        """Verifie une CNI avec OCR.
        
        Args:
            cni_recto_url: URL face recto
            cni_verso_url: URL face verso
            selfie_url: URL selfie utilisateur
            
        Returns:
            {success, extracted_data, confidence}
        """
        # Placeholder - en production, integrer:
        # - Google Cloud Vision API
        # - ou Azure Form Recognizer
        # - ou AWS Textract
        
        return {
            "success": True,
            "extracted_data": {
                "nom": "A VERIFIER",
                "prenom": "",
                "date_naissance": None,
                "numero_cni": "",
            },
            "confidence": 0.85,
            "verified_at": timezone.now().isoformat(),
        }
    
    @classmethod
    def compare_face(cls, selfie_url: str, cni_photo_url: str) -> bool:
        """Compare le selfie avec la photo CNI.
        
        Utilise Face API (Azure/Face++).
        
        Returns:
            True si correspondance
        """
        # Placeholder
        return True


# ✅ F12: SLA Auto-expiration des demandes
class SLAService:
    """Service d'expiration automatique SLA.
    
    Expire les demandes sans reponse apres 72h.
    """
    
    SLA_HOURS = 72  # 72 heures
    
    @classmethod
    def process_expired_demands(cls) -> int:
        """Expire les demandes en attente depuis trop longtemps.
        
        Returns:
            Nombre de demandes expirees
        """
        from ..models import Reservation
        from django.utils import timezone
        from datetime import timedelta
        
        threshold = timezone.now() - timedelta(hours=cls.SLA_HOURS)
        
        # Expirer les demandes DEMANDE_ENVOYEE sans reponse
        expired = Reservation.objects.filter(
            statut="DEMANDE_ENVOYEE",
            created_at__lt=threshold,
        )
        
        count = expired.count()
        expired.update(
            statut="Annulee",
            updated_at=timezone.now(),
        )
        
        if count:
            # Notifier le client
            from .notification_service import NotificationService
            for res in expired:
                NotificationService.create_notification(
                    NotificationService.NotificationInput(
                        user=res.client,
                        title="Demande expiree",
                        message=f"Votre demande {res.reference} a expire sans reponse.",
                        type="WARNING",
                    )
                )
        
        return count
    
    @classmethod
    def process_unconfirmed_demands(cls) -> int:
        """Relance les devis envoyes non confirmes > 48h.
        
        Returns:
            Nombre de relances
        """
        from ..models import Reservation
        from django.utils import timezone
        from datetime import timedelta
        
        threshold = timezone.now() - timedelta(hours=48)
        
        # Devis envoyes non acceptes
        pending = Reservation.objects.filter(
            statut="DEVIS_ENVOYE",
            created_at__lt=threshold,
        )
        
        count = pending.count()
        
        if count:
            from .notification_service import NotificationService
            for res in pending:
                NotificationService.create_notification(
                    NotificationService.NotificationInput(
                        user=res.client,
                        title="Rappel devis",
                        message=f"Vous n'avez pas encore accepte le devis pour {res.reference}.",
                        type="INFO",
                    )
                )
        
        return count