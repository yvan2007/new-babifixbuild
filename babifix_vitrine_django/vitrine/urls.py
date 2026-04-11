from django.urls import path

from .views import api_newsletter_subscribe, creer_un_compte, devenir_prestataire, home, telecharger_app_client

urlpatterns = [
    path('', home, name='vitrine-home'),
    path('telecharger-app-client', telecharger_app_client, name='vitrine-download-client'),
    path('devenir-prestataire', devenir_prestataire, name='vitrine-devenir-prestataire'),
    path('creer-un-compte', creer_un_compte, name='vitrine-creer-compte'),
    path('api/newsletter/subscribe/', api_newsletter_subscribe, name='api-newsletter-subscribe'),
]
