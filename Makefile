.PHONY: help setup run-backend run-client migrate createsuperuser test clean

help:
	@echo "BABIFIX Makefile - Commands disponibles:"
	@echo "  make setup         - Installer les dépendances"
	@echo "  make run-backend   - Lancer le serveur Django"
	@echo "  make run-client    - Lancer l'app Flutter client"
	@echo "  make run-prestataire - Lancer l'app Flutter prestataire"
	@echo "  make migrate       - Appliquer les migrations Django"
	@echo "  make createsuperuser - Créer un superutilisateur admin"
	@echo "  make test          - Lancer les tests"
	@echo "  make clean          - Nettoyer les fichiers temporaires"

setup:
	cd babifix_admin_django && pip install -r requirements.txt

run-backend:
	cd babifix_admin_django && python manage.py runserver

run-client:
	cd babifix_client_flutter && flutter run

run-prestataire:
	cd babifix_prestataire_flutter && flutter run

migrate:
	cd babifix_admin_django && python manage.py makemigrations && python manage.py migrate

createsuperuser:
	cd babifix_admin_django && python manage.py createsuperuser

test:
	cd babifix_admin_django && python manage.py test

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	find . -type d -name ".dart_tool" -exec rm -rf {} + 2>/dev/null || true