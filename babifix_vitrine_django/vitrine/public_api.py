import json
import os
import urllib.error
import urllib.request

from django.core.cache import cache

_PUBLIC_API_CACHE_TTL = 60
_LIVE_VITRINE_CACHE_TTL = 15


def _admin_bases():
    env_base = os.getenv('BABIFIX_ADMIN_API_BASE', '').strip().rstrip('/')
    bases = [b for b in [env_base, 'http://127.0.0.1:8002', 'http://127.0.0.1:8011'] if b]
    return list(dict.fromkeys(bases))


def _fetch_json(path_and_query, timeout=1.5):
    for base in _admin_bases():
        url = f'{base}{path_and_query}'
        try:
            with urllib.request.urlopen(url, timeout=timeout) as resp:
                return json.loads(resp.read().decode('utf-8'))
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, OSError):
            continue
    return None


def fetch_admin_public_vitrine(force_refresh: bool = False):
    """Recupere le JSON public depuis babifix_admin_django (avec cache court 15 s)."""
    ckey = 'vitrine:public_api:vitrine'
    if not force_refresh:
        cached = cache.get(ckey)
        if cached is not None:
            return cached
    data = _fetch_json('/api/public/vitrine/', timeout=1.5)
    out = data if isinstance(data, dict) else {}
    cache.set(ckey, out, _LIVE_VITRINE_CACHE_TTL if out else 10)
    return out


def fetch_admin_public_categories():
    """Categories actives (avec cache 60 s)."""
    ckey = 'vitrine:public_api:categories'
    cached = cache.get(ckey)
    if cached is not None:
        return cached
    data = _fetch_json('/api/public/categories/?all=1', timeout=1.5)
    out = data if isinstance(data, dict) else {'categories': []}
    cache.set(ckey, out, _PUBLIC_API_CACHE_TTL if out.get('categories') else 15)
    return out


def fetch_admin_public_config():
    """Configuration dynamique plateforme depuis /api/public/config/ avec repli et cache."""
    ckey = 'vitrine:public_api:config'
    cached = cache.get(ckey)
    if cached is not None:
        return cached
    defaults = {
        'std_rate': 18,
        'silver_rate': 13,
        'gold_rate': 8,
        'std_net': 82,
        'silver_net': 87,
        'gold_net': 92,
        'silver_price': 7500,
        'gold_price': 15000,
        'min_withdrawal': 1000,
        'frais_mise_en_relation': 500,
        'maintenance': False,
    }
    data = _fetch_json('/api/public/config/', timeout=1.5)
    if not isinstance(data, dict):
        cache.set(ckey, defaults, 15)
        return defaults
    try:
        tiers = data.get('tiers') or {}
        std_r = int((tiers.get('standard') or {}).get('commission_pct', data.get('commission_base_pct', 18)))
        sil_r = int((tiers.get('silver') or {}).get('commission_pct', 13))
        gld_r = int((tiers.get('gold') or {}).get('commission_pct', 8))
        escrow = data.get('escrow') or {}
        wallet = data.get('wallet') or {}
        apps = data.get('apps') or {}
        out = {
            'std_rate': std_r,
            'silver_rate': sil_r,
            'gold_rate': gld_r,
            'std_net': max(0, 100 - std_r),
            'silver_net': max(0, 100 - sil_r),
            'gold_net': max(0, 100 - gld_r),
            'silver_price': int((tiers.get('silver') or {}).get('price_fcfa', 7500)),
            'gold_price': int((tiers.get('gold') or {}).get('price_fcfa', 15000)),
            'min_withdrawal': int(wallet.get('min_withdrawal_fcfa', 1000)),
            'frais_mise_en_relation': int(escrow.get('frais_mise_en_relation_fcfa', 500)),
            'maintenance': bool(apps.get('maintenance', False)),
        }
        cache.set(ckey, out, _PUBLIC_API_CACHE_TTL)
        return out
    except (ValueError, TypeError):
        cache.set(ckey, defaults, 15)
        return defaults
