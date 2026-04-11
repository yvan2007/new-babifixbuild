"""Import du catalogue métier des catégories (JSON) vers le modèle Category."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from django.db import transaction

from .constants import CATEGORY_ICON_SLUGS
from .models import Category

_ALLOWED_SLUGS = frozenset(s for s, _ in CATEGORY_ICON_SLUGS)


def default_catalog_path() -> Path:
    return Path(__file__).resolve().parent.parent / 'data' / 'categories-services-domicile.json'


def icon_slug_from_icon_field(icon_path: str) -> str:
    """Extrait le slug depuis `category-icons/foo.svg` → `foo`."""
    p = (icon_path or '').strip()
    if not p:
        return ''
    return Path(p).stem


def load_catalog_dict(path: Path | None = None) -> dict[str, Any]:
    p = path or default_catalog_path()
    with p.open(encoding='utf-8') as f:
        return json.load(f)


def import_categories_from_catalog(
    *,
    path: Path | None = None,
    dry_run: bool = False,
) -> dict[str, int | list[str]]:
    """
    Crée ou met à jour les Category à partir du JSON.
    Ne modifie jamais `services` ni `reservations` (stats métier).
    Met à jour : nom (clé métier), description, icone_slug, ordre_affichage, actif=True.
    """
    data = load_catalog_dict(path)
    rows = data.get('categories') or []
    warnings: list[str] = []
    created = 0
    updated = 0

    def _one(order: int, row: dict[str, Any]) -> None:
        nonlocal created, updated
        name = (row.get('name') or '').strip()
        if not name:
            warnings.append(f'Entrée ignorée (nom vide) : {row.get("id")!r}')
            return
        desc = (row.get('description') or '').strip()
        slug = icon_slug_from_icon_field(str(row.get('icon') or ''))
        if not slug:
            warnings.append(f'Icône manquante pour {name!r}')
            return
        if slug not in _ALLOWED_SLUGS:
            warnings.append(f'Slug inconnu {slug!r} pour {name!r} — vérifiez constants / fichiers SVG.')
            return

        if dry_run:
            if Category.objects.filter(nom=name).exists():
                updated += 1
            else:
                created += 1
            return

        obj, was_created = Category.objects.get_or_create(
            nom=name,
            defaults={
                'description': desc,
                'icone_slug': slug,
                'ordre_affichage': order,
                'actif': True,
                'icone_url': '',
            },
        )
        if was_created:
            created += 1
        else:
            obj.description = desc
            obj.icone_slug = slug
            obj.ordre_affichage = order
            obj.actif = True
            obj.save(update_fields=['description', 'icone_slug', 'ordre_affichage', 'actif'])
            updated += 1

    if dry_run:
        for i, row in enumerate(rows):
            _one(i, row)
    else:
        with transaction.atomic():
            for i, row in enumerate(rows):
                _one(i, row)

    return {
        'created': created,
        'updated': updated,
        'total_rows': len(rows),
        'warnings': warnings,
    }
