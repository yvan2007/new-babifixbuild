#!/bin/bash
# =============================================================================
# Tests statiques — BABIFIX Backend
# =============================================================================
# Outils requis : flake8, pylint, bandit, mypy
# Usage : bash scripts/test_static.sh
# =============================================================================

set -e

echo "=========================================="
echo "TESTS STATIQUES — BABIFIX Backend"
echo "=========================================="

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Racine du projet
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo ""
echo "📋 1. FLUTE8 — Style PEP8"
echo "----------------------------------------"
if command -v flake8 &> /dev/null; then
    flake8 babifix_admin_django/adminpanel babifix_admin_django/config babifix_vitrine_django/vitrine \
        --max-line-length=120 \
        --exclude=.venv,migrations,__pycache__,*.pyc \
        --ignore=E501,W503,E402 || true
    echo -e "${GREEN}✓ flake8 terminé${NC}"
else
    echo -e "${YELLOW}⚠ flake8 non installé${NC}"
fi

echo ""
echo "📋 2. BANDIT — Vulnérabilités de sécurité"
echo "----------------------------------------"
if command -v bandit &> /dev/null; then
    bandit -r babifix_admin_django/adminpanel babifix_admin_django/config babifix_vitrine_django/vitrine \
        -x .venv \
        -f txt || true
    echo -e "${GREEN}✓ bandit terminé${NC}"
else
    echo -e "${YELLOW}⚠ bandit non installé${NC}"
fi

echo ""
echo "📋 3. PYLINT — Analyse supplémentaire"
echo "----------------------------------------"
if command -v pylint &> /dev/null; then
    pylint babifix_admin_django/adminpanel babifix_admin_django/config babifix_vitrine_django/vitrine \
        --disable=import-error,too-few-public-methods,too-many-public-methods \
        --max-line-length=120 || true
    echo -e "${GREEN}✓ pylint terminé${NC}"
else
    echo -e "${YELLOW}⚠ pylint non installé${NC}"
fi

echo ""
echo "📋 4. MYPY — Typage statique"
echo "----------------------------------------"
if command -v mypy &> /dev/null; then
    mypy babifix_admin_django/adminpanel babifix_admin_django/config \
        --ignore-missing-imports \
        --no-error-summary || true
    echo -e "${GREEN}✓ mypy terminé${NC}"
else
    echo -e "${YELLOW}⚠ mypy non installé${NC}"
fi

echo ""
echo "📋 5. FLUTTER ANALYZE — Apps Flutter"
echo "----------------------------------------"
for app in babifix_client_flutter babifix_prestataire_flutter; do
    if [ -d "$app" ]; then
        echo ""
        echo "Analyse $app..."
        cd "$app"
        if command -v flutter &> /dev/null; then
            flutter analyze --no-fatal-warnings --no-fatal-infos || true
            echo -e "${GREEN}✓ $app analyze terminé${NC}"
        else
            echo -e "${YELLOW}⚠ flutter non installé${NC}"
        fi
        cd "$PROJECT_ROOT"
    fi
done

echo ""
echo "=========================================="
echo "TESTS STATIQUES TERMINÉS"
echo "=========================================="
echo ""
echo "Pour installer les outils:"
echo "  pip install flake8 pylint bandit mypy"
echo "  # Flutter analyze:"
echo "  flutter pub global activate dart_analysis"
echo ""
