#!/usr/bin/env python3
"""
Génère les SVG colorés dans static/category-icons/ (style flat moderne type marketplace).

Les pictogrammes sont des compositions SVG originales BABIFIX (plusieurs couleurs, dégradés légers).
Pour utiliser des packs IconScout sous licence : exportez en SVG depuis https://iconscout.com
et remplacez le fichier correspondant (même slug, ex. goutte.svg) en conservant viewBox 0 0 24 24.
"""
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "static" / "category-icons"

# Chaque entrée : SVG complet (24x24, fills + parfois stroke fin)
SVG: dict[str, str] = {
    "goutte": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<defs><linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#38bdf8"/><stop offset="100%" stop-color="#2563eb"/></linearGradient></defs>
<path fill="url(#g)" d="M12 2.2c-2.8 3.5-5.2 6.4-5.2 9.8a5.2 5.2 0 1010.4 0c0-3.4-2.4-6.3-5.2-9.8z"/>
<path fill="#7dd3fc" opacity=".5" d="M12 6.5c-1.2 1.5-2.1 2.9-2.1 4.2a2.1 2.1 0 104.2 0c0-1.3-.9-2.7-2.1-4.2z"/>
</svg>""",
    "eclair": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#fbbf24" d="M13 2L3 14h7l-1 8 12-14h-7l-1-6z"/>
<path fill="#f59e0b" d="M11.5 8.5L6 14h5.5l-.5 4.5 6.5-7.5H12l-.5-2.5z"/>
</svg>""",
    "climatisation": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="12" cy="12" r="9" fill="#e0f2fe"/>
<path fill="#0ea5e9" d="M12 4a8 8 0 100 16 8 8 0 000-16zm0 2v4l3.5 2-3.5 2v4l6-3.5V7.5L12 6z"/>
<path fill="#38bdf8" d="M12 8v2.5l2 1.2-2 1.1V15l4-2.3V9.3L12 8z"/>
</svg>""",
    "chauffage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#fed7aa" d="M12 3c-3.3 0-6 2.2-6 5.5 0 2.1 1.2 3.9 3 4.8V20h6v-6.7c1.8-.9 3-2.7 3-4.8C18 5.2 15.3 3 12 3z"/>
<path fill="#f97316" d="M12 6c-.5 1.2-1 2.3-1 3.5a3 3 0 006 0c0-1.2-.5-2.3-1-3.5-.5 1-1 2-1 3h-2c0-1-.5-2-1-3z"/>
</svg>""",
    "cle": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="8.5" cy="8.5" r="4" fill="#fde68a" stroke="#ca8a04" stroke-width="1.2"/>
<path fill="#eab308" d="M11 11l10 10-1.5 1.5-3-3-2 2-1.5-1.5 2-2-3-3L11 11z"/>
</svg>""",
    "fenetre": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="3" y="4" width="18" height="16" rx="2" fill="#bae6fd"/>
<path stroke="#0284c7" stroke-width="1.5" d="M12 4v16M3 12h18"/>
<rect x="5" y="6" width="5" height="5" rx="0.5" fill="#e0f2fe"/>
<rect x="14" y="6" width="5" height="5" rx="0.5" fill="#e0f2fe"/>
</svg>""",
    "pinceau": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#a855f7" d="M3 21l8-8 2 2-8 8H3v-2z"/>
<path fill="#7c3aed" d="M11 13l1.5-1.5 7-7a2 2 0 012.8 0l.7.7a2 2 0 010 2.8l-7 7L11 13z"/>
<path fill="#fbbf24" d="M16 8l2 2-1 1-2-2 1-1z"/>
</svg>""",
    "carrelage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="3" y="3" width="8" height="8" rx="1" fill="#94a3b8"/>
<rect x="13" y="3" width="8" height="8" rx="1" fill="#cbd5e1"/>
<rect x="3" y="13" width="8" height="8" rx="1" fill="#cbd5e1"/>
<rect x="13" y="13" width="8" height="8" rx="1" fill="#64748b"/>
</svg>""",
    "menuiserie": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="4" y="4" width="16" height="16" rx="1" fill="#d4a574"/>
<rect x="6" y="6" width="12" height="12" rx="0.5" fill="#a16207"/>
<path stroke="#fde68a" stroke-width="1.2" d="M12 6v12M6 12h12"/>
</svg>""",
    "tondeuse": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<ellipse cx="12" cy="16" rx="9" ry="4" fill="#22c55e"/>
<path fill="#16a34a" d="M3 16c0-2 4-4 9-4s9 2 9 4v2H3v-2z"/>
<path fill="#4ade80" d="M8 10c0-2.2 1.8-4 4-4s4 1.8 4 4v3H8v-3z"/>
<circle cx="12" cy="7" r="2" fill="#86efac"/>
</svg>""",
    "elagage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#15803d" d="M12 2L4 18h16L12 2z"/>
<path fill="#22c55e" d="M12 6l-4 10h8L12 6z"/>
<path fill="#cbd5e1" d="M10 18h4v3h-4v-3z"/>
<path fill="#64748b" d="M9 14h6l-1 4H10l-1-4z"/>
</svg>""",
    "balai": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#78716c" d="M10 2h4l1 12H9L10 2z"/>
<path fill="#f59e0b" d="M5 16h14l-1 4H6l-1-4z"/>
<path fill="#fbbf24" d="M6 16l1 2h10l1-2H6z"/>
</svg>""",
    "nettoyage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#38bdf8" d="M8 10l-2 2 6 6 8-8-2-2-6 6-4-4z"/>
<path fill="#0ea5e9" d="M14 8l2 2-1 1-2-2 1-1z"/>
<circle cx="7" cy="7" r="2" fill="#7dd3fc"/>
<circle cx="5" cy="5" r="1.2" fill="#bae6fd"/>
</svg>""",
    "demenagement": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="4" y="8" width="14" height="12" rx="1" fill="#c4b5fd"/>
<path fill="#7c3aed" d="M6 8V6a2 2 0 012-2h8a2 2 0 012 2v2"/>
<path fill="#f59e0b" d="M8 12h6v4H8v-4z"/>
<path fill="#6366f1" d="M18 18h3v2h-5v-2l2-6h2l-2 6z"/>
</svg>""",
    "escalier": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#94a3b8" d="M4 20h4v-4H4v4zm4-4h4v-4H8v4zm4-4h4V8h-4v4zm4-4h4V4h-4v4z"/>
<path fill="#64748b" d="M4 16h4v-4H4v4zm8 0h4v-4h-4v4z"/>
</svg>""",
    "marteau": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#78716c" d="M14 3l7 7-2 2-7-7 2-2z"/>
<path fill="#dc2626" d="M3 18l9-9 2 2-9 9H3v-2z"/>
<rect x="12" y="1" width="6" height="5" rx="0.5" transform="rotate(45 15 3.5)" fill="#a8a29e"/>
</svg>""",
    "frigo": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="6" y="3" width="12" height="18" rx="2" fill="#e2e8f0"/>
<path fill="#3b82f6" d="M8 5h8v7H8V5zm0 9h8v6H8v-6z"/>
<circle cx="12" cy="15" r="1" fill="#fff"/>
</svg>""",
    "ordinateur": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="2" y="4" width="20" height="13" rx="2" fill="#1e293b"/>
<rect x="4" y="6" width="16" height="9" rx="0.5" fill="#38bdf8"/>
<path fill="#64748b" d="M8 19h8v2H8v-2z"/>
</svg>""",
    "domotique": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="3" y="6" width="18" height="12" rx="2" fill="#312e81"/>
<circle cx="8" cy="12" r="2" fill="#a5b4fc"/>
<circle cx="12" cy="12" r="2" fill="#818cf8"/>
<circle cx="16" cy="12" r="2" fill="#6366f1"/>
<path stroke="#c7d2fe" stroke-width="1.2" fill="none" d="M6 4v2M12 4v2M18 4v2"/>
</svg>""",
    "assistance": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="12" cy="8" r="4" fill="#fecdd3"/>
<path fill="#ec4899" d="M4 20c0-4 3.6-7 8-7s8 3 8 7v1H4v-1z"/>
<path fill="#f472b6" d="M9 11h6v2H9v-2z"/>
</svg>""",
    "enfant": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="12" cy="7" r="3" fill="#fcd34d"/>
<path fill="#f59e0b" d="M8 14c0-2 1.8-3.5 4-3.5s4 1.5 4 3.5v5H8v-5z"/>
<circle cx="10" cy="6.5" r="0.5" fill="#1e293b"/>
<circle cx="14" cy="6.5" r="0.5" fill="#1e293b"/>
</svg>""",
    "animal": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<ellipse cx="12" cy="14" rx="6" ry="5" fill="#d97706"/>
<circle cx="8" cy="9" r="2" fill="#f59e0b"/>
<circle cx="16" cy="9" r="2" fill="#f59e0b"/>
<path fill="#92400e" d="M9 15h6v1a3 3 0 01-6 0v-1z"/>
</svg>""",
    "toilettage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#ec4899" d="M8 4c0 2 2 4 4 4s4-2 4-4H8z"/>
<path fill="#f9a8d4" d="M6 10h12v2a6 6 0 01-12 0v-2z"/>
<path fill="#db2777" d="M10 14h4v6h-4v-6z"/>
</svg>""",
    "cours": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#3b82f6" d="M4 6h16v2H4V6zm0 4h10v2H4v-2zm0 4h14v2H4v-2z"/>
<circle cx="18" cy="16" r="4" fill="#fbbf24"/>
<path fill="#f59e0b" d="M17 15h2v3h-2v-3z"/>
</svg>""",
    "sport": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="12" cy="12" r="9" fill="#fef3c7" stroke="#f59e0b" stroke-width="1.5"/>
<path fill="#ef4444" d="M12 5l1.5 4.5L18 11l-4.5 1.5L12 17l-1.5-4.5L6 11l4.5-1.5L12 5z"/>
</svg>""",
    "ciseaux": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#c084fc" d="M6 4l6 8-2 2-6-8 2-2zm12 0l-6 8 2 2 6-8-2-2z"/>
<circle cx="8" cy="17" r="2.5" fill="#e9d5ff" stroke="#9333ea" stroke-width="1"/>
<circle cx="16" cy="17" r="2.5" fill="#e9d5ff" stroke="#9333ea" stroke-width="1"/>
</svg>""",
    "massage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<ellipse cx="12" cy="14" rx="7" ry="4" fill="#a7f3d0"/>
<path fill="#10b981" d="M5 14c2-2 5-3 7-3s5 1 7 3v2H5v-2z"/>
<circle cx="12" cy="8" r="3" fill="#6ee7b7"/>
</svg>""",
    "photo": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="3" y="6" width="18" height="14" rx="2" fill="#1e293b"/>
<circle cx="12" cy="12" r="4" fill="#38bdf8"/>
<circle cx="12" cy="12" r="2" fill="#0ea5e9"/>
<rect x="6" y="4" width="4" height="2" rx="0.5" fill="#64748b"/>
</svg>""",
    "musique": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#8b5cf6" d="M8 18V8l12-2v10"/>
<circle cx="8" cy="18" r="3" fill="#a78bfa"/>
<circle cx="20" cy="16" r="3" fill="#c4b5fd"/>
</svg>""",
    "voiture": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#64748b" d="M3 12l2-4h14l2 4v6H3v-6z"/>
<path fill="#94a3b8" d="M5 12h14v4H5v-4z"/>
<circle cx="8" cy="16" r="2" fill="#1e293b"/>
<circle cx="16" cy="16" r="2" fill="#1e293b"/>
<path fill="#ef4444" d="M10 10h4v2h-4v-2z"/>
</svg>""",
    "lavage-auto": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#38bdf8" d="M4 14h16v4H4v-4z"/>
<path fill="#0ea5e9" d="M6 10h12l2 4H4l2-4z"/>
<circle cx="8" cy="18" r="1.8" fill="#1e293b"/>
<circle cx="16" cy="18" r="1.8" fill="#1e293b"/>
<path fill="#bae6fd" d="M8 6c2 0 4 2 4 4H6c0-2 2-4 4-4z"/>
</svg>""",
    "casserole": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<ellipse cx="12" cy="14" rx="8" ry="4" fill="#78716c"/>
<path fill="#a8a29e" d="M4 14c0-2 3.6-4 8-4s8 2 8 4v1H4v-1z"/>
<path fill="#f97316" d="M10 8h4v3h-4V8z"/>
<rect x="11" y="4" width="2" height="4" fill="#57534e"/>
</svg>""",
    "telephone": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="7" y="2" width="10" height="20" rx="2" fill="#1e293b"/>
<rect x="8.5" y="4" width="7" height="14" rx="0.5" fill="#38bdf8"/>
<circle cx="12" cy="19" r="1" fill="#64748b"/>
</svg>""",
    "vitrage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#bae6fd" d="M4 4h16v16H4V4z"/>
<path stroke="#ef4444" stroke-width="2" d="M6 6l12 12M18 6L6 18"/>
<path stroke="#0284c7" stroke-width="1.2" d="M12 4v16M4 12h16"/>
</svg>""",
    "desinfection": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#22c55e" d="M12 2l2 5 5 .5-3.5 3 1 5L12 13l-4.5 2.5 1-5L5 7.5 10 7l2-5z"/>
<circle cx="12" cy="17" r="4" fill="#86efac" stroke="#16a34a" stroke-width="1"/>
<path stroke="#15803d" stroke-width="1.2" d="M10 17h4"/>
</svg>""",
    "piscine": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="2" y="10" width="20" height="10" rx="2" fill="#0ea5e9"/>
<path fill="#38bdf8" d="M2 14c3 1 5-1 8 0s5 1 8 0 5-1 8 0v4H2v-4z" opacity=".6"/>
<path fill="#7dd3fc" d="M4 8h16v2H4V8z"/>
</svg>""",
    "arrosage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#22c55e" d="M12 4c-2 4-6 6-6 10a6 6 0 0012 0c0-4-4-6-6-10z"/>
<path fill="#4ade80" d="M12 8c-1 2-3 3.5-3 6a3 3 0 006 0c0-2.5-2-4-3-6z"/>
<path fill="#86efac" d="M8 18h8v2H8v-2z"/>
</svg>""",
    "maison": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#fbbf24" d="M12 3L2 12h3v9h6v-6h4v6h6v-9h3L12 3z"/>
<path fill="#f59e0b" d="M12 5.5L5 12h2v7h4v-5h6v5h4v-7h2l-7-6.5z"/>
<rect x="10" y="14" width="4" height="5" fill="#92400e"/>
</svg>""",
    "inspection": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="11" cy="11" r="7" fill="#fef9c3" stroke="#eab308" stroke-width="1.5"/>
<path stroke="#ca8a04" stroke-width="2" stroke-linecap="round" d="M16 16l5 5"/>
<path fill="#facc15" d="M8 9h6v2H8V9zm0 3h4v2H8v-2z"/>
</svg>""",
    "securite": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#64748b" d="M12 2L4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5l-8-3z"/>
<path fill="#22c55e" d="M10 12l2 2 4-4 1.5 1.5L12 15.5 8.5 12 10 12z"/>
</svg>""",
    "outils": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#64748b" d="M14.7 6.3a1 1 0 010 1.4l-7 7-2 2-2-2 2-2 7-7a1 1 0 011.4 0z"/>
<path fill="#f59e0b" d="M18 4l2 2-3 3-2-2 3-3z"/>
<path fill="#94a3b8" d="M3 18l6-2-1-1-5 3z"/>
</svg>""",
    "multiservices": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="8" cy="8" r="3" fill="#38bdf8"/>
<circle cx="16" cy="8" r="3" fill="#a855f7"/>
<circle cx="12" cy="16" r="3" fill="#22c55e"/>
<path fill="#fbbf24" d="M12 11l1 2h2l-1.5 1.5L14 16l-2-1.5L10 16l.5-1.5L9 13h2l1-2z"/>
</svg>""",
    "toiture": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#b45309" d="M2 12L12 4l10 8v8H2v-8z"/>
<path fill="#ea580c" d="M4 12.5L12 6l8 6.5V20H4v-7.5z"/>
<path fill="#fef3c7" d="M8 14h8v6H8v-6z"/>
</svg>""",
    "maconnerie": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="3" y="6" width="7" height="5" rx="0.5" fill="#dc2626"/><rect x="11" y="6" width="10" height="5" rx="0.5" fill="#b91c1c"/>
<rect x="3" y="12" width="10" height="5" rx="0.5" fill="#ef4444"/><rect x="14" y="12" width="7" height="5" rx="0.5" fill="#991b1b"/>
<rect x="3" y="18" width="7" height="4" rx="0.5" fill="#b91c1c"/><rect x="11" y="18" width="10" height="4" rx="0.5" fill="#dc2626"/>
</svg>""",
    "isolation": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="4" y="5" width="16" height="4" rx="1" fill="#fef9c3"/><rect x="4" y="10" width="16" height="4" rx="1" fill="#fde68a"/>
<rect x="4" y="15" width="16" height="4" rx="1" fill="#fcd34d"/><path stroke="#ca8a04" stroke-width="1" d="M6 7h12M6 12h12M6 17h12"/>
</svg>""",
    "ravalement": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="5" y="3" width="14" height="18" rx="1" fill="#e2e8f0"/><rect x="7" y="5" width="4" height="4" fill="#94a3b8"/><rect x="13" y="5" width="4" height="4" fill="#cbd5e1"/>
<path fill="#a855f7" d="M4 20h16v2H4v-2z"/><path fill="#7c3aed" d="M14 8l6 10h-4l-2-6 2-4z"/>
</svg>""",
    "sol-souple": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#78716c" d="M3 8c4 2 6-1 10 1s6-1 10 1v10H3V8z"/><path fill="#a8a29e" d="M3 12c3 1.5 5-.5 8.5 1S17 12 21 13.5V20H3v-8z"/>
<path fill="#d6d3d1" d="M5 15h14v3H5v-3z"/>
</svg>""",
    "tapisserie-deco": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="4" y="4" width="16" height="16" rx="1" fill="#fce7f3"/><path stroke="#db2777" stroke-width="1.2" d="M4 9h16M4 14h16M9 4v16M15 4v16"/>
<circle cx="12" cy="12" r="2" fill="#f472b6"/>
</svg>""",
    "metallier": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#64748b" d="M3 18h18v2H3v-2z"/><path fill="#94a3b8" d="M5 8h14v8H5V8z"/><path stroke="#475569" stroke-width="1.5" d="M5 12h14M9 8v8M15 8v8"/>
</svg>""",
    "stores-volets": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="3" y="4" width="18" height="3" rx="0.5" fill="#0ea5e9"/><rect x="3" y="8" width="18" height="2.5" fill="#38bdf8"/><rect x="3" y="11.5" width="18" height="2.5" fill="#7dd3fc"/>
<rect x="3" y="15" width="18" height="2.5" fill="#bae6fd"/><rect x="3" y="18.5" width="18" height="2" fill="#e0f2fe"/>
</svg>""",
    "placo": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="4" y="5" width="16" height="14" rx="0.5" fill="#f1f5f9" stroke="#94a3b8" stroke-width="1.2"/>
<path stroke="#cbd5e1" stroke-width="1" d="M12 5v14M4 12h16"/>
</svg>""",
    "etancheite": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#0ea5e9" d="M4 14h16l-2 6H6l-2-6z"/><path fill="#38bdf8" d="M6 12h12v2H6v-2z"/>
<path fill="#0369a1" d="M12 3c-2 3-5 4.5-5 7a5 5 0 0010 0c0-2.5-3-4-5-7z"/>
</svg>""",
    "cloture": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#78716c" d="M4 20h2V8h2v12h2V8h2v12h2V8h2v12h2V8h2v12h2V6H4v14z"/>
<path fill="#a16207" d="M4 20h16v2H4v-2z"/>
</svg>""",
    "forage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="10" y="3" width="4" height="14" rx="0.5" fill="#64748b"/><path fill="#475569" d="M8 17h8l-1 4H9l-1-4z"/>
<circle cx="12" cy="10" r="2" fill="#f59e0b"/><path stroke="#eab308" stroke-width="1.5" d="M12 2v4"/>
</svg>""",
    "demoussage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#166534" d="M2 10L12 5l10 5v3H2v-3z"/><path fill="#22c55e" d="M4 13h16v2H4v-2z"/>
<path fill="#854d0e" d="M14 14l4 8h-3l-1.5-5-1.5 5h-3l4-8z"/>
</svg>""",
    "taille-haies": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="3" y="10" width="18" height="8" rx="1" fill="#15803d"/><rect x="5" y="8" width="14" height="4" rx="0.5" fill="#22c55e"/>
<path fill="#64748b" d="M18 6l3 4h-2v6h-2V6z"/><path fill="#94a3b8" d="M17 7h4l-1 2h-2V7z"/>
</svg>""",
    "engazonnement": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<ellipse cx="12" cy="16" rx="10" ry="5" fill="#22c55e"/><path fill="#16a34a" d="M4 16c2-3 5-4 8-4s6 1 8 4v4H4v-4z"/>
<path fill="#86efac" d="M8 12c1-2 2-3 4-3s3 1 4 3l-8 1z"/>
</svg>""",
    "potager": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#854d0e" d="M8 18h8v3H8v-3z"/><path fill="#16a34a" d="M10 10c0 4-2 6-2 8h8c0-2-2-4-2-8-1 2-3 2-4 0z"/>
<circle cx="9" cy="7" r="2" fill="#ef4444"/><circle cx="15" cy="8" r="1.8" fill="#f97316"/>
</svg>""",
    "bassin": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<ellipse cx="12" cy="14" rx="9" ry="5" fill="#0ea5e9"/><path fill="#38bdf8" d="M3 14c2 1 4 0 6 .5s4 .5 6-.5 4-1 6 0v4H3v-4z" opacity=".7"/>
<path fill="#22c55e" d="M10 8c0-2 1-3 2-3s2 1 2 3c-1-1-3-1-4 0z"/>
</svg>""",
    "repassage": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#64748b" d="M5 8h14a2 2 0 012 2v1H3v-1a2 2 0 012-2z"/><path fill="#94a3b8" d="M4 12h16v6H4v-6z"/>
<path fill="#f97316" d="M6 14h12v1.5H6V14z"/>
</svg>""",
    "courses": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#22c55e" d="M6 6h2l1.5 9h10l1.5-6H9"/><circle cx="10" cy="19" r="1.5" fill="#334155"/><circle cx="17" cy="19" r="1.5" fill="#334155"/>
<path fill="#fbbf24" d="M8 4h3v2H8V4z"/>
</svg>""",
    "conciergerie": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<rect x="6" y="7" width="12" height="14" rx="1" fill="#e0e7ff" stroke="#6366f1" stroke-width="1.2"/>
<circle cx="12" cy="12" r="2" fill="#818cf8"/><path fill="#c4b5fd" d="M9 16h6v2H9v-2z"/>
<path fill="#fbbf24" d="M16 5l2 2-1 1-2-2 1-1z"/>
</svg>""",
    "aide-quotidien": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="9" cy="9" r="3" fill="#fdba74"/><circle cx="15" cy="9" r="3" fill="#fcd34d"/>
<path fill="#fb923c" d="M5 20c1-3 3.5-5 7-5s6 2 7 5H5z"/><path fill="#f59e0b" d="M11 20c.5-2 2-3.5 4-3.5s3.5 1.5 4 3.5h-8z"/>
</svg>""",
    "traiteur": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#94a3b8" d="M5 8h14v2H5V8z"/><ellipse cx="12" cy="13" rx="8" ry="4" fill="#e2e8f0" stroke="#64748b" stroke-width="1"/>
<circle cx="10" cy="13" r="1.2" fill="#ef4444"/><circle cx="14" cy="13" r="1.2" fill="#22c55e"/>
<path fill="#cbd5e1" d="M11 4h2v4h-2V4z"/>
</svg>""",
    "animation": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#a855f7" d="M8 4h8v16H8V4z"/><circle cx="12" cy="9" r="2" fill="#fde68a"/><path fill="#f472b6" d="M9 13h6v3H9v-3z"/>
<path fill="#fbbf24" d="M18 6l2 3h-2l-1-2 1-1zM6 8L4 11h2l1-2-1-1z"/>
</svg>""",
    "deco-fetes": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#ec4899" d="M12 4l1.5 5L18 8l-4 3 2 5-4-3-4 3 2-5-4-3 4.5 1L12 4z"/><circle cx="6" cy="6" r="1.5" fill="#fbbf24"/><circle cx="19" cy="10" r="1.2" fill="#38bdf8"/>
<circle cx="5" cy="16" r="1.2" fill="#22c55e"/>
</svg>""",
    "antenne": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path stroke="#64748b" stroke-width="1.5" d="M12 21V10"/><path fill="#0ea5e9" d="M8 8l4-5 4 5H8z"/><path stroke="#38bdf8" stroke-width="1.2" d="M6 12h12M7 9h10M7 15h10"/>
</svg>""",
    "couture": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path stroke="#db2777" stroke-width="1.5" d="M4 16c4-4 8-8 16-4"/><path fill="#fce7f3" d="M14 6l4 4-2 2-4-4 2-2z"/>
<path stroke="#9d174d" stroke-width="1.2" d="M12 8l2 2"/><circle cx="11" cy="7" r="1" fill="#f472b6"/>
</svg>""",
    "debarras": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#64748b" d="M6 8h12l1 12H5L6 8z"/><path fill="#475569" d="M9 8V6h6v2"/><path fill="#94a3b8" d="M8 11h8v2H8v-2z"/>
<path fill="#fbbf24" d="M10 14h4v4h-4v-4z"/>
</svg>""",
    "montage-velo": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="7" cy="17" r="4" fill="none" stroke="#0ea5e9" stroke-width="1.8"/><circle cx="17" cy="17" r="4" fill="none" stroke="#0ea5e9" stroke-width="1.8"/>
<path stroke="#0369a1" stroke-width="1.5" d="M7 17h5l3-8h3M12 17l4-8"/><path fill="#f59e0b" d="M15 7h3v2h-3V7z"/>
</svg>""",
    "home-staging": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#d97706" d="M4 18V10l8-5 8 5v8H4z"/><rect x="8" y="13" width="8" height="5" fill="#fef3c7"/><path fill="#22c55e" d="M14 8l3 4h-2v3h-2V8z"/>
</svg>""",
    "rideaux": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#64748b" d="M3 5h18v2H3V5z"/><path fill="#a855f7" d="M4 8h5v12H4V8z"/><path fill="#c084fc" d="M10 8h4v12h-4V8z"/><path fill="#7c3aed" d="M15 8h5v12h-5V8z"/>
</svg>""",
    "vmc": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<circle cx="12" cy="12" r="8" fill="#e0f2fe" stroke="#0284c7" stroke-width="1.2"/>
<path fill="#0ea5e9" d="M12 6l1.5 4.5L18 12l-4.5 1.5L12 18l-1.5-4.5L6 12l4.5-1.5L12 6z"/>
</svg>""",
    "luminaires": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path fill="#fbbf24" d="M9 3h6v8H9V3z"/><path fill="#f59e0b" d="M8 11h8l-1 3H9l-1-3z"/><path fill="#fde68a" d="M10 14h4v2h-4v-2z"/>
<path stroke="#ca8a04" stroke-width="1.2" d="M12 16v4"/>
</svg>""",
    "pressing": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path stroke="#64748b" stroke-width="1.5" d="M8 4h8a2 2 0 012 2v12a2 2 0 01-2 2H8a2 2 0 01-2-2V6a2 2 0 012-2z"/>
<path fill="#38bdf8" d="M9 8h6v10H9V8z"/><path fill="#e0f2fe" d="M10 6h4v2h-4V6z"/>
</svg>""",
    "gaz-cuisson": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<ellipse cx="12" cy="16" rx="8" ry="4" fill="#334155"/><path fill="#475569" d="M6 14h12v2H6v-2z"/>
<path fill="#f97316" d="M12 7c-1.2 2-2.5 3.5-2.5 5.5a2.5 2.5 0 005 0c0-2-1.3-3.5-2.5-5.5z"/>
<path fill="#fbbf24" d="M12 9c-.6 1-.9 1.8-.9 2.6a1.2 1.2 0 002.4 0c0-.8-.3-1.6-.9-2.6-.3.6-.4 1-.6 1.4-.2-.4-.3-.8-.6-1.4z"/>
</svg>""",
    "soudure": """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" aria-hidden="true">
<path stroke="#64748b" stroke-width="2" stroke-linecap="round" d="M4 16l6-6"/><path fill="#f59e0b" d="M14 6l4 4-2 2-4-4 2-2z"/>
<path fill="#fbbf24" d="M16 4l2 2-1 1-2-2 1-1z"/><circle cx="18" cy="8" r="2" fill="#fef08a"/>
</svg>""",
}


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    missing: list[str] = []
    for slug, _label in __import__(
        "adminpanel.constants", fromlist=["CATEGORY_ICON_SLUGS"]
    ).CATEGORY_ICON_SLUGS:
        if slug not in SVG:
            missing.append(slug)
            continue
        path = ROOT / f"{slug}.svg"
        path.write_text(SVG[slug].strip() + "\n", encoding="utf-8")
        print("wrote", path.relative_to(ROOT.parent.parent))
    if missing:
        raise SystemExit(f"Slugs sans SVG dans le script: {missing}")


if __name__ == "__main__":
    import os
    import sys

    # Permet d'importer adminpanel depuis le projet Django
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    import django

    django.setup()
    main()
