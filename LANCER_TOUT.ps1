# =============================================================================
#  BABIFIX — Lanceur tout-en-un
#  Démarre : Backend (Daphne) + Vitrine + App Client + App Prestataire
#  Usage :  clic droit > "Exécuter avec PowerShell"   OU   .\LANCER_TOUT.ps1
#  Options : .\LANCER_TOUT.ps1 -NoApps   (backend + vitrine seulement)
# =============================================================================
param(
    [switch]$NoApps,        # Ne pas lancer les apps Flutter
    [switch]$NoVitrine,     # Ne pas lancer la vitrine
    [string]$Device = ""    # ID d'émulateur/appareil Flutter (sinon auto)
)

$ErrorActionPreference = "Continue"
$ROOT = $PSScriptRoot
$ADMIN = Join-Path $ROOT "babifix_admin_django"
$VITRINE = Join-Path $ROOT "babifix_vitrine_django"
$CLIENT = Join-Path $ROOT "babifix_client_flutter"
$PRESTA = Join-Path $ROOT "babifix_prestataire_flutter"

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

Section "BABIFIX — Démarrage de tout l'écosystème"

# --- 1. Backend : migrations + Daphne (port 8002, ASGI = WebSocket + appels) ---
Section "1/4  Backend (Django/Daphne) — port 8002"
Push-Location $ADMIN
Write-Host "Application des migrations..." -ForegroundColor Yellow
python manage.py migrate 2>&1 | Select-Object -Last 3
Start-Process powershell -ArgumentList @(
    "-NoExit","-Command",
    "cd '$ADMIN'; Write-Host 'BACKEND BABIFIX (Daphne :8002)' -ForegroundColor Green; python -m daphne -b 0.0.0.0 -p 8002 config.asgi:application"
)
Pop-Location
Write-Host "Backend lancé dans une nouvelle fenêtre." -ForegroundColor Green

# --- 2. Vitrine (site public) — port 8001 ---
if (-not $NoVitrine) {
    Section "2/4  Vitrine (site public) — port 8001"
    Start-Process powershell -ArgumentList @(
        "-NoExit","-Command",
        "cd '$VITRINE'; Write-Host 'VITRINE BABIFIX (:8001)' -ForegroundColor Green; python manage.py runserver 0.0.0.0:8001"
    )
    Write-Host "Vitrine lancée." -ForegroundColor Green
}

if ($NoApps) {
    Section "Terminé (apps non lancées : option -NoApps)"
    Write-Host "Backend  : http://localhost:8002" -ForegroundColor White
    Write-Host "Admin    : http://localhost:8002/" -ForegroundColor White
    Write-Host "Vitrine  : http://localhost:8001/" -ForegroundColor White
    return
}

# --- Vérifier qu'un appareil/émulateur Flutter est prêt ---
Section "Vérification d'un appareil Flutter"
$devLine = ""
$tries = 0
while ($tries -lt 30 -and -not $devLine) {
    $devs = flutter devices 2>$null
    # Cherche un émulateur Android ou un téléphone (pas windows/edge/chrome)
    $devLine = ($devs | Select-String -Pattern "android|mobile" | Select-Object -First 1)
    if (-not $devLine) { Start-Sleep -Seconds 4; $tries++; Write-Host "  ...attente d'un appareil ($tries)" -ForegroundColor DarkGray }
}
if (-not $Device -and $devLine) {
    # Extrait l'ID de l'appareil (2e colonne du tableau flutter devices)
    $Device = (($devLine.ToString() -split "•")[1]).Trim()
}
if (-not $Device) {
    Write-Host "Aucun émulateur Android détecté. Lance-en un puis relance ce script," -ForegroundColor Red
    Write-Host "ou ouvre Android Studio > Device Manager > Play." -ForegroundColor Red
    Write-Host "Astuce : flutter emulators --launch Pixel_10_Pro" -ForegroundColor Yellow
    return
}
Write-Host "Appareil cible : $Device" -ForegroundColor Green

# --- 3. App Client ---
Section "3/4  App CLIENT (Flutter)"
Start-Process powershell -ArgumentList @(
    "-NoExit","-Command",
    "cd '$CLIENT'; Write-Host 'APP CLIENT BABIFIX' -ForegroundColor Green; flutter run -d $Device"
)
Write-Host "App client en cours de build/lancement." -ForegroundColor Green

# --- 4. App Prestataire ---
Section "4/4  App PRESTATAIRE (Flutter)"
Start-Process powershell -ArgumentList @(
    "-NoExit","-Command",
    "cd '$PRESTA'; Write-Host 'APP PRESTATAIRE BABIFIX' -ForegroundColor Green; flutter run -d $Device"
)
Write-Host "App prestataire en cours de build/lancement." -ForegroundColor Green

Section "Tout est lancé !"
Write-Host "Backend     : http://localhost:8002" -ForegroundColor White
Write-Host "Vitrine     : http://localhost:8001" -ForegroundColor White
Write-Host "Apps        : sur l'émulateur $Device" -ForegroundColor White
Write-Host ""
Write-Host "Note : 2 apps sur le MÊME émulateur se lancent l'une après l'autre." -ForegroundColor Yellow
Write-Host "Pour les tester en parallèle, lance un 2e émulateur et relance avec -Device <id2>." -ForegroundColor Yellow
