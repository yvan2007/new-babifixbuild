#!/usr/bin/env python
"""
Crée le superuser admin initial pour BABIFIX.
Usage : python scripts/create_superuser.py
"""
import os
import sys

def main():
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
    
    import django
    django.setup()
    
    from django.contrib.auth import get_user_model
    User = get_user_model()
    
    username = input("Nom d'utilisateur admin: ").strip()
    if not username:
        print("Erreur: nom d'utilisateur requis")
        sys.exit(1)
    
    email = input("Email admin: ").strip()
    if not email:
        print("Erreur: email requis")
        sys.exit(1)
    
    password = input("Mot de passe: ")
    if len(password) < 8:
        print("Erreur: mot de passe doit faire au moins 8 caractères")
        sys.exit(1)
    
    if User.objects.filter(username=username).exists():
        user = User.objects.get(username=username)
        user.email = email
        user.is_staff = True
        user.is_superuser = True
        user.set_password(password)
        user.save()
        print(f"Utilisateur {username} mis à jour (admin)")
    else:
        user = User.objects.create_user(
            username=username,
            email=email,
            password=password,
            is_staff=True,
            is_superuser=True,
        )
        print(f"Superuser {username} créé avec succès!")
    
    # Créer aussi un profile si nécessaire
    from adminpanel.models import UserProfile, SystemSetting
    
    profile, _ = UserProfile.objects.get_or_create(
        user=user,
        defaults={'role': UserProfile.Role.ADMIN, 'active': True}
    )
    profile.role = UserProfile.Role.ADMIN
    profile.active = True
    profile.save()
    
    # Créer les paramètres système par défaut
    SystemSetting.objects.get_or_create(pk=1)
    
    print("Prêt!")

if __name__ == '__main__':
    main()
