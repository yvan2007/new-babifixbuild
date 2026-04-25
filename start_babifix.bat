# Script d'activation automatique BABIFIX
# Place ce fichier dans C:\Users\kouay\Documents\BABIFIX_BUILD

@echo off
echo ========================================
echo  Activation BABIFIX Build...
echo ========================================

# Verifier si le venv existe
if not exist "venv\Scripts\activate.bat" (
    echo [ERROR] venv non trouve! Creer avec:
    echo   python -m venv venv
    echo   venv\Scripts\pip install -r requirements.txt
    pause
    exit /b 1
)

# Activer le venv
call venv\Scripts\activate.bat

echo [OK] Environnement active!
echo.
echo Commandes disponibles:
echo   cd babifix_admin_django
echo   python manage.py runserver 0.0.0.0:8002
echo.

# Aller dans le dossier admin
cd babifix_admin_django
echo [OK] Dans babifix_admin_django

# Lancer le serveur
echo.
echo Demarrage du serveur Django sur port 8002...
python manage.py runserver 0.0.0.0:8002

pause