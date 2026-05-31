"""Filtres templates BABIFIX — monnaie FCFA (XOF) + temps relatif."""
from __future__ import annotations

import re
from decimal import Decimal

from django import template
from django.utils import timezone
from django.utils.timesince import timesince

register = template.Library()


@register.filter(name='relative_time')
def relative_time(value) -> str:
    """Temps relatif RÉEL et dynamique à partir d'un datetime (created_at).

    Remplace les anciennes chaînes statiques (« Il y a 5 min » figées). Se
    recalcule à chaque chargement de page → plus de notifications « figées ».
    """
    if not value:
        return "—"
    try:
        now = timezone.now()
        delta = now - value
        secs = delta.total_seconds()
        if secs < 0:
            return "À l'instant"
        if secs < 60:
            return "À l'instant"
        # timesince donne « 5 minutes », « 2 heures, 3 minutes »… on garde le
        # 1er terme pour rester concis, préfixé par « Il y a ».
        ts = timesince(value, now)
        ts = ts.split(",")[0].strip()
        return f"Il y a {ts}"
    except (TypeError, ValueError):
        return "—"


def _to_int(value) -> int | None:
    if value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    if isinstance(value, Decimal):
        return int(value)
    s = str(value).strip()
    s = re.sub(r'[^\d\-]', '', s.replace('\u202f', '').replace(' ', ''))
    if not s or s == '-':
        return None
    try:
        return int(s)
    except ValueError:
        return None


@register.filter(name='format_fcfa')
def format_fcfa(value) -> str:
    """
    Affiche un montant en francs CFA : « 12 500 FCFA » (espaces insécables possibles).
    Accepte int, Decimal, ou chaîne contenant des chiffres.
    """
    n = _to_int(value)
    if n is None:
        return '—'
    # Espace fine / espace normal entre milliers (usage CI / FR)
    formatted = f'{n:,}'.replace(',', '\u202f')
    return f'{formatted} FCFA'


@register.filter(name='strip_fcfa_label')
def strip_fcfa_label(value) -> str:
    """Retire un suffixe FCFA/XOF pour affichage brut si besoin."""
    if value is None:
        return ''
    s = str(value)
    for suf in (' FCFA', 'FCFA', ' XOF', 'XOF'):
        if s.upper().endswith(suf.upper()):
            s = s[: -len(suf)].strip()
            break
    return s
