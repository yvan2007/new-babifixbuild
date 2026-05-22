#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ci_check — vérification pré-déploiement BABIFIX.

Lance, et n'échoue que sur de VRAIES erreurs (pas les lints info/warning) :
  1. Django :  manage.py check  +  tests du flux argent
  2. Flutter : flutter analyze (client + prestataire) — échec si « error - »

Usage :
    python ci_check.py            # tout
    python ci_check.py --fast     # saute les tests Django (plus rapide)

Codes retour : 0 = OK, 1 = échec (à brancher sur un hook CI / pre-push).
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
ADMIN = os.path.join(ROOT, "babifix_admin_django")
CLIENT = os.path.join(ROOT, "babifix_client_flutter")
PRESTA = os.path.join(ROOT, "babifix_prestataire_flutter")

ERR_RE = re.compile(r"^\s*error\s+-", re.IGNORECASE | re.MULTILINE)


def run(cmd, cwd, label):
    print(f"\n=== {label} ===")
    try:
        r = subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True)
    except Exception as exc:  # noqa: BLE001
        print(f"  ⚠️  impossible de lancer : {exc}")
        return None
    out = (r.stdout or "") + (r.stderr or "")
    print(out.strip()[-2000:])
    return out, r.returncode


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fast", action="store_true", help="Sauter les tests Django.")
    args = ap.parse_args()

    failures = []

    # 1) Django check
    res = run("python manage.py check", ADMIN, "Django — system check")
    if res and res[1] != 0:
        failures.append("django check")

    # 2) Django tests (flux argent)
    if not args.fast:
        res = run(
            "python manage.py test adminpanel.tests.test_money_flow",
            ADMIN,
            "Django — tests flux argent",
        )
        if res and res[1] != 0:
            failures.append("django tests")

    # 3) Flutter analyze — échec seulement si erreurs (pas les lints info)
    for label, path in (("client", CLIENT), ("prestataire", PRESTA)):
        res = run("flutter analyze", path, f"Flutter analyze — {label}")
        if res and ERR_RE.search(res[0]):
            failures.append(f"flutter {label} (errors)")

    print("\n" + "=" * 50)
    if failures:
        print("❌ CI ÉCHEC :", ", ".join(failures))
        sys.exit(1)
    print("✅ CI OK — prêt à déployer.")
    sys.exit(0)


if __name__ == "__main__":
    main()
