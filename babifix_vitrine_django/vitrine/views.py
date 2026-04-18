import json
import os

from django.conf import settings
from django.core.cache import cache
from django.core.mail import send_mail
from django.http import JsonResponse
from django.shortcuts import render
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_POST

from .models import (
    ContactInquiry,
    FAQItem,
    HeroContent,
    Lead,
    Testimonial,
    VitrineStats,
)
from .public_api import fetch_admin_public_categories, fetch_admin_public_vitrine

# Anti-spam : max 3 messages par IP par heure
_CONTACT_RATE_LIMIT = 3
_CONTACT_RATE_WINDOW = 3600  # secondes


def _contact_rate_key(request):
    ip = request.META.get("HTTP_X_FORWARDED_FOR", request.META.get("REMOTE_ADDR", ""))
    ip = ip.split(",")[0].strip()
    return f"babifix_contact_{ip}"


def home(request):
    message = ""
    contact_message = ""
    if request.method == "POST":
        # Formulaire contact (champs préfixés pour ne pas confondre avec la newsletter)
        if request.POST.get("contact_form"):
            # Honeypot : si le champ caché "website" est rempli, c'est un bot
            if request.POST.get("website", "").strip():
                contact_message = "Merci ! Votre message a bien été envoyé. Nous vous répondons sous 48 h."
            else:
                # Rate limiting
                rate_key = _contact_rate_key(request)
                count = cache.get(rate_key, 0)
                if count >= _CONTACT_RATE_LIMIT:
                    contact_message = "Trop de messages envoyés. Veuillez patienter avant de réessayer."
                else:
                    name = (request.POST.get("contact_name") or "").strip()
                    c_email = (request.POST.get("contact_email") or "").strip()
                    subject = (request.POST.get("contact_subject") or "").strip()
                    body = (request.POST.get("contact_message") or "").strip()
                    if name and c_email and subject and body:
                        ContactInquiry.objects.create(
                            name=name,
                            email=c_email,
                            subject=subject,
                            message=body,
                        )
                        cache.set(rate_key, count + 1, _CONTACT_RATE_WINDOW)

                        # Envoyer email à l'équipe admin
                        admin_email = settings.DEFAULT_FROM_EMAIL
                        try:
                            send_mail(
                                subject=f"[CONTACT BABIFIX] {subject}",
                                message=f"De: {name} <{c_email}>\n\n{body}",
                                from_email=admin_email,
                                recipient_list=[admin_email],
                                fail_silently=False,
                            )
                        except Exception:
                            pass  # Email envío échoué mais message enregistré en DB

                        contact_message = "Merci ! Votre message a bien été envoyé. Nous vous répondons sous 48 h."
                    else:
                        contact_message = (
                            "Veuillez remplir tous les champs du formulaire."
                        )
        else:
            email = request.POST.get("email", "").strip()
            if email:
                _, created = Lead.objects.get_or_create(email=email)
                message = (
                    "Merci, votre demande a bien ete enregistree."
                    if created
                    else "Cet email est deja inscrit."
                )
            else:
                message = "Veuillez saisir une adresse email valide."

    vd = fetch_admin_public_vitrine()
    cat_payload = fetch_admin_public_categories()
    categories = cat_payload.get("categories") if isinstance(cat_payload, dict) else []
    if not isinstance(categories, list):
        categories = []
    faq_raw = vd.get("faq")
    faq_items = faq_raw if isinstance(faq_raw, list) else []

    hero_title = (vd.get("hero_title") or "").strip() or None
    hero_subtitle = (vd.get("hero_subtitle") or "").strip() or None

    # Récupérer le contenu héros depuis la DB
    hero_db = HeroContent.objects.filter(actif=True).first()
    if hero_db:
        hero_title = hero_title or hero_db.titre
        hero_subtitle = hero_subtitle or hero_db.soustitre

    store_ios = (vd.get("store_ios_url") or "").strip()
    store_android = (vd.get("store_android_url") or "").strip()
    store_p_ios = (vd.get("store_prestataire_ios_url") or "").strip()
    store_p_android = (vd.get("store_prestataire_android_url") or "").strip()

    # Récupérer les statistiques depuis la DB
    stats_db = VitrineStats.objects.filter(actif=True).order_by("ordre_affichage")
    stats_list = [{"label": s.label, "value": s.valeur} for s in stats_db]
    if not stats_list:
        # Fallback si pas de stats en DB
        stats_list = [
            {"label": "Prestataires vérifiés", "value": "10,000+"},
            {"label": "Services réalisés", "value": "50,000+"},
            {"label": "Note moyenne", "value": "4.9/5"},
            {"label": "Clients satisfaits", "value": "95%"},
        ]

    # Récupérer les témoignages depuis la DB
    temoignages_db = Testimonial.objects.filter(actif=True).order_by("ordre_affichage")
    temoignages_list = [
        {
            "nom": t.nom,
            "role": t.role,
            "ville": t.ville,
            "texte": t.texte,
        }
        for t in temoignages_db
    ]
    if not temoignages_list:
        # Fallback si pas de témoignages en DB
        temoignages_list = [
            {
                "nom": "Aminata Koné",
                "role": "Particulier",
                "ville": "Abidjan Cocody",
                "texte": "J'ai trouvé un excellent plombier en moins de 10 minutes. Service rapide et professionnel. Je recommande à 100% !",
            },
            {
                "nom": "Ibrahim Touré",
                "role": "Chef d'entreprise",
                "ville": "Bouaké",
                "texte": "BABIFIX a révolutionné ma façon de trouver des prestataires. Fini les longues recherches, tout est simple et sécurisé.",
            },
            {
                "nom": "Marie Koffi",
                "role": "Électricienne — Prestataire BABIFIX",
                "ville": "Abidjan Plateau",
                "texte": "En tant qu'électricienne, BABIFIX m'a permis de développer ma clientèle rapidement. Les paiements sont toujours sécurisés.",
            },
        ]

    # Récupérer les FAQs depuis la DB
    faq_db = FAQItem.objects.filter(actif=True).order_by("ordre_affichage")
    faq_items = (
        [{"question": f.question, "answer": f.answer} for f in faq_db]
        if faq_db
        else faq_items
    )

    context = {
        "hero_title": hero_title,
        "hero_subtitle": hero_subtitle,
        "store_ios_client": store_ios,
        "store_android_client": store_android,
        "store_ios_prestataire": store_p_ios,
        "store_android_prestataire": store_p_android,
        "stats": stats_list,
        "features": [
            "Sécurisé",
            "Local",
            "Simple",
            "Mobile Money",
            "Rapide",
            "Qualité garantie",
        ],
        "temoignages": temoignages_list,
        "message": message,
        "contact_message": contact_message,
        "last_email": "",
        "categories": categories,
        "admin_api_base": os.getenv(
            "BABIFIX_ADMIN_API_BASE", "http://127.0.0.1:8002"
        ).rstrip("/"),
        "faq_items": faq_items,
    }
    return render(request, "vitrine/home.html", context)


def telecharger_app_client(request):
    vd = fetch_admin_public_vitrine()
    ios = (vd.get("store_ios_url") or "").strip()
    android = (vd.get("store_android_url") or "").strip()
    lines = []
    if ios:
        lines.append(
            f'<p><a class="btn primary" href="{ios}" rel="noopener">App Store (iOS)</a></p>'
        )
    if android:
        lines.append(
            f'<p><a class="btn primary" href="{android}" rel="noopener">Google Play (Android)</a></p>'
        )
    if not lines:
        lines.append(
            "<p>Les liens stores seront affichés ici une fois renseignés dans l’admin BABIFIX (SiteContent).</p>"
        )
    return render(
        request,
        "vitrine/simple_page.html",
        {"title": "Telecharger l app Client", "body_safe": "".join(lines)},
    )


def devenir_prestataire(request):
    vd = fetch_admin_public_vitrine()
    ios = (vd.get("store_prestataire_ios_url") or "").strip()
    android = (vd.get("store_prestataire_android_url") or "").strip()
    lines = []
    if ios:
        lines.append(
            f'<p><a class="btn primary" href="{ios}" rel="noopener">App Prestataire — App Store</a></p>'
        )
    if android:
        lines.append(
            f'<p><a class="btn primary" href="{android}" rel="noopener">App Prestataire — Google Play</a></p>'
        )
    if not lines:
        lines.append(
            "<p>Téléchargez l’application prestataire BABIFIX depuis les stores (liens à configurer dans l’admin).</p>"
        )
    return render(
        request,
        "vitrine/simple_page.html",
        {"title": "Devenir prestataire", "body_safe": "".join(lines)},
    )


def creer_un_compte(request):
    return render(
        request,
        "vitrine/simple_page.html",
        {
            "title": "Creer un compte",
            "body": "La creation de compte client sera activee sur le backend central BABIFIX.",
        },
    )


def error_404(request, exception=None):
    return render(request, "vitrine/404.html", status=404)


def error_500(request):
    return render(request, "vitrine/500.html", status=500)


# =============================================================================
# API NEWSLETTER — POST /api/newsletter/subscribe/
# =============================================================================
@csrf_exempt
@require_POST
def api_newsletter_subscribe(request):
    """API d'inscription à la newsletter avec honeypot anti-spam."""
    try:
        payload = json.loads(request.body)
    except (json.JSONDecodeError, ValueError):
        return JsonResponse({"error": "invalid_json"}, status=400)

    # Honeypot - si rempli, c'est un bot
    honeypot = payload.get("website_url", "").strip()
    if honeypot:
        # Simuler un succès pour piéger le bot
        return JsonResponse({"ok": True, "message": "Inscription confirmée"})

    email = (payload.get("email") or "").strip().lower()
    name = (payload.get("name") or "").strip()
    role = (payload.get("role") or "").strip()

    if not email or "@" not in email:
        return JsonResponse({"error": "email_required"}, status=400)

    # Rate limiting par IP
    ip = request.META.get("HTTP_X_FORWARDED_FOR", request.META.get("REMOTE_ADDR", ""))
    ip = ip.split(",")[0].strip() if ip else ""
    rate_key = f"newsletter_subscribe_{ip}"
    count = cache.get(rate_key, 0)
    if count >= 5:
        return JsonResponse({"error": "rate_limit_exceeded"}, status=429)

    # Enregistrer ou récupérer le lead
    lead, created = Lead.objects.get_or_create(
        email=email, defaults={"name": name, "role": role} if name else {}
    )

    # Si pas nouveau mais utilisateur veut mettre à jour son rôle
    if not created and role and hasattr(lead, "role"):
        lead.role = role
        lead.save()

    cache.set(rate_key, count + 1, 3600)  # 1h

    return JsonResponse(
        {
            "ok": True,
            "message": "Inscription confirmée"
            if created
            else "Cet email est déjà inscrit.",
        }
    )


def cgu(request):
    return render(request, "vitrine/cgu.html")


def confidentialite(request):
    return render(request, "vitrine/confidentialite.html")
