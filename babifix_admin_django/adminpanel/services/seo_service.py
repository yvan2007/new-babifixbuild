"""
SEO Service — Optimisation pour les moteurs de recherche
"""
import logging
from django.db.models import Q

logger = logging.getLogger(__name__)


class SEOService:
    """Service d'optimisation SEO pour BABIFIX."""
    
    # ✅ M6: Metadonnees pour le referencement
    SITE_NAME = "BABIFIX"
    SITE_DESCRIPTION = "Plateforme de services a domicile en Cote d'Ivoire. Trouvez des prestataires qualifies pour vos services domestques: menage, plomberie, electricite, jardinage, et plus."
    SITE_URL = "https://babifix.ci"
    
    # Mots-cles par categorie
    CATEGORY_KEYWORDS = {
        "menage": ["menage abidjan", "femme de menage", "nettoyage maison"],
        "plomberie": ["plombier abidjan", "reparation fuite", "installation sanitaire"],
        "electricite": ["electricien abidjan", "depannage electricite", "installation electrique"],
        "jardinage": ["jardinier abidjan", "entretien jardin", "paysagiste"],
        "peinture": ["peintre abidjan", "peinture maison", "renovation"],
    }
    
    @classmethod
    def get_meta_tags(cls, categorie: str = None) -> dict:
        """Genere les meta tags pour une page.
        
        Args:
            categorie: Categorie optionnelle
            
        Returns:
            Dict avec title, description, keywords, og_tags
        """
        if categorie:
            title = f"{categorie.capitalize()} - {cls.SITE_NAME}"
            keywords = cls.CATEGORY_KEYWORDS.get(
                categorie.lower(), 
                [categorie]
            )
            description = f"Trouvez les meilleurs prestataires {categorie} a Abidjan sur {cls.SITE_NAME}. Intervention rapide, paiement securise."
        else:
            title = cls.SITE_NAME
            keywords = ["services domicile", "prestataire", "abidjan", "CI"]
            description = cls.SITE_DESCRIPTION
        
        return {
            "title": title,
            "description": description,
            "keywords": ", ".join(keywords),
            "og_title": title,
            "og_description": description,
            "og_url": cls.SITE_URL,
            "og_type": "website",
        }
    
    @classmethod
    def get_sitemap_entries(cls) -> list:
        """Genere les entrees pour le sitemap XML.
        
        Returns:
            Liste de {loc, changefreq, priority}
        """
        from ..models import Category, Provider
        from django.utils import timezone
        
        entries = [
            {"loc": cls.SITE_URL, "changefreq": "daily", "priority": "1.0"},
            {"loc": f"{cls.SITE_URL}/services", "changefreq": "weekly", "priority": "0.8"},
            {"loc": f"{cls.SITE_URL}/about", "changefreq": "monthly", "priority": "0.5"},
            {"loc": f"{cls.SITE_URL}/contact", "changefreq": "monthly", "priority": "0.5"},
        ]
        
        # Ajouter les categories
        for cat in Category.objects.filter(active=True):
            entries.append({
                "loc": f"{cls.SITE_URL}/services/{cat.slug}",
                "changefreq": "weekly",
                "priority": "0.7",
            })
        
        # Ajouter les prestataires validates
        for provider in Provider.objects.filter(
            statut=Provider.Status.VALID,
            is_deleted=False,
        ).only("id", "nom"):
            entries.append({
                "loc": f"{cls.SITE_URL}/provider/{provider.id}",
                "changefreq": "weekly",
                "priority": "0.6",
            })
        
        return entries
    
    @classmethod
    def generate_schema_ldjson(cls, provider, category) -> str:
        """Genere le schema.org JSON-LD pour un prestataire.
        
        Args:
            provider: Instance Provider
            category: Instance Category
            
        Returns:
            Script JSON-LD pour schema.org
        """
        import json
        
        schema = {
            "@context": "https://schema.org",
            "@type": "LocalBusiness",
            "name": provider.nom,
            "image": provider.photo_portrait_url or "",
            "address": {
                "@type": "PostalAddress",
                "addressLocality": provider.ville or "Abidjan",
                "addressRegion": "CI",
                "addressCountry": "CI",
            },
            "telephone": provider.telephone or "",
            "priceRange": f"XOF{int(provider.tarif_horaire or 0)}",
            "rating": {
                "@type": "AggregateRating",
                "ratingValue": provider.note_moyenne or 0,
                "reviewCount": provider.nombre_notes or 0,
            },
        }
        
        if provider.latitude and provider.longitude:
            schema["geo"] = {
                "@type": "GeoCoordinates",
                "latitude": provider.latitude,
                "longitude": provider.longitude,
            }
        
        return json.dumps(schema)