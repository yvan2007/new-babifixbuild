@echo off
echo ========================================
echo  BABIFIX BUILD - Environment Active
echo ========================================
echo.
echo Commands:
echo   cd babifix_admin_django   - Backend Django
echo   cd babifix_client_flutter - Flutter Client
echo   cd babifix_prestataire_flutter - Flutter Prestataire
echo.
echo Start Django: python manage.py runserver 0.0.0.0:8002
echo Start Flutter: flutter run
echo.
echo ========================================
cd babifix_admin_django
echo [Backend] venv activated
cmd /k