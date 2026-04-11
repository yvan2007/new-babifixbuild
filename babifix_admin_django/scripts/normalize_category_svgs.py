"""
ATTENTION : ce script forçait le trait #2563eb sur d’anciens SVG.
Les icônes multicolores (générées par generate_colorful_category_icons.py) ne doivent PAS
être passées dans ce script — vous casseriez les couleurs.
"""
import pathlib

p = pathlib.Path(__file__).resolve().parent.parent / "static" / "category-icons"
for f in p.glob("*.svg"):
    t = f.read_text(encoding="utf-8")
    t = t.replace("#0f766e", "#2563eb").replace('stroke-width="1.5"', 'stroke-width="2"')
    f.write_text(t, encoding="utf-8")
    print(f.name)
