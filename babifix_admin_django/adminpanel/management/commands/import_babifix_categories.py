"""Importe le catalogue JSON des catégories BABIFIX (voir data/categories-services-domicile.json)."""

from pathlib import Path

from django.core.management.base import BaseCommand

from adminpanel.category_catalog import default_catalog_path, import_categories_from_catalog


class Command(BaseCommand):
    help = 'Importe ou met à jour les catégories depuis le fichier JSON (sans toucher aux compteurs services/réservations).'

    def add_arguments(self, parser):
        parser.add_argument(
            '--file',
            type=str,
            default='',
            help='Chemin vers le JSON (défaut : data/categories-services-domicile.json du projet).',
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Simule sans écrire en base.',
        )

    def handle(self, *args, **options):
        raw = (options.get('file') or '').strip()
        path = Path(raw) if raw else default_catalog_path()
        if not path.is_file():
            self.stderr.write(self.style.ERROR(f'Fichier introuvable : {path}'))
            return

        result = import_categories_from_catalog(path=path, dry_run=options['dry_run'])
        mode = 'DRY-RUN' if options['dry_run'] else 'OK'
        self.stdout.write(self.style.SUCCESS(f'[{mode}] créés={result["created"]} mis_à_jour={result["updated"]} lignes={result["total_rows"]}'))
        for w in result.get('warnings') or []:
            self.stdout.write(self.style.WARNING(w))
