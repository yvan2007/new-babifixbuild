"""
URL configuration for config project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.conf import settings
from django.contrib import admin
from django.contrib.auth import views as auth_views
from django.urls import include, path
from django.views.static import serve as serve_static
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    path('admin/', admin.site.urls),
    path('logout/', auth_views.LogoutView.as_view(next_page='/admin/login/'), name='logout'),
    path('', include('adminpanel.urls')),
    # Swagger / OpenAPI
    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
]

# Pages d'erreur personnalisées BABIFIX
handler404 = 'adminpanel.views.error_404'
handler500 = 'adminpanel.views.error_500'

# Servir les fichiers média toujours (pas seulement en DEBUG)
# Pour Render, c'est suffisant ; en vrai prod, utiliser S3/Cloudinary
urlpatterns += [
    path('media/<path:path>', serve_static, {'document_root': settings.MEDIA_ROOT}),
]
