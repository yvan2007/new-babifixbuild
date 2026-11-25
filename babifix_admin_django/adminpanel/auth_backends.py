import unicodedata
from django.contrib.auth import get_user_model
from django.contrib.auth.backends import ModelBackend
from django.db.models import Q


class EmailOrUsernameModelBackend(ModelBackend):
    """
    Authentification flexible pour l'administration Django et les APIs :
    permet de se connecter soit avec son nom d'utilisateur, soit avec son e-mail.
    """

    def authenticate(self, request, username=None, password=None, **kwargs):
        if username is None:
            username = kwargs.get(get_user_model().USERNAME_FIELD) or kwargs.get("email")
        if not username or not password:
            return None

        user_model = get_user_model()
        cleaned_username = unicodedata.normalize("NFKC", str(username).strip())

        try:
            user = user_model._default_manager.filter(
                Q(username__iexact=cleaned_username) | Q(email__iexact=cleaned_username)
            ).order_by("-is_superuser", "-is_staff", "-id").first()
        except Exception:
            return None

        if user and user.check_password(password) and self.user_can_authenticate(user):
            return user
        return None
