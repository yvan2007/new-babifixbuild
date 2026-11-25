param(
    [switch]$Fast
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

Write-Host "=== BABIFIX : Controle Anti-Regression Integral ===" -ForegroundColor Cyan

function Assert-Markers {
    param(
        [string]$FilePath,
        [string[]]$Markers
    )
    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "Fichier critique manquant : $FilePath"
    }
    $content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
    foreach ($m in $Markers) {
        if ($content -notlike "*$m*") {
            throw "REGRESSION DETECTEE : marqueur '$m' absent de $FilePath"
        }
    }
}

Write-Host "`n[1/5] Verification des marqueurs critiques anti-regression..." -ForegroundColor Yellow
Assert-Markers "$RepoRoot\babifix_vitrine_django\vitrine\views.py" @("api_live_console", "devenir_prestataire", "service_local_detail")
Assert-Markers "$RepoRoot\babifix_vitrine_django\templates\vitrine\home.html" @("mm-chip", "radar", "Devenir prestataire")
Assert-Markers "$RepoRoot\babifix_admin_django\adminpanel\views_v2.py" @("api_category_catalogue", "api_reservation_bon_de_commande_pdf", "api_prestataire_sos_claim", "send_babifix_html_email")
Assert-Markers "$RepoRoot\babifix_admin_django\static\adminpanel\style.css" @("@keyframes pageIn", ".nav-badge", ".notif-count-badge")
Assert-Markers "$RepoRoot\babifix_client_flutter\lib\models\client_models.dart" @("avgResponseMin", "completedJobs", "casierVerifie")
Assert-Markers "$RepoRoot\babifix_client_flutter\lib\shared\services\nominatim_geocode.dart" @("kCivCommunesReference", "resolveNearestCivCommune", "nominatimReverse")
Assert-Markers "$RepoRoot\babifix_client_flutter\lib\features\booking\confirm_travaux_screen.dart" @("_buildAvantApresShowcase")
Assert-Markers "$RepoRoot\babifix_client_flutter\lib\features\reservations\reservations_history_screen.dart" @("_ReservationProgressTracker")
Assert-Markers "$RepoRoot\babifix_client_flutter\lib\babifix_fcm.dart" @("CONFIGUREZ_IOS")
Assert-Markers "$RepoRoot\babifix_prestataire_flutter\lib\features\requests\devis_kanban_editor_screen.dart" @("_buildQuickSuggestionsBar", "_devisCoherenceBanner")
Assert-Markers "$RepoRoot\babifix_prestataire_flutter\lib\features\profile\edit_profile_screen.dart" @("_categoryNom")
Assert-Markers "$RepoRoot\babifix_prestataire_flutter\lib\features\auth\registration_screen.dart" @("_CategoryPickerSheet")
Assert-Markers "$RepoRoot\babifix_prestataire_flutter\lib\shared\services\nominatim_geocode.dart" @("kCivCommunesReference", "resolveNearestCivCommune", "nominatimReverse")
Assert-Markers "$RepoRoot\babifix_prestataire_flutter\lib\babifix_fcm.dart" @("CONFIGUREZ_IOS")

# Verifie que pageIn ne reintroduit pas transform (bloque les modales fixed)
$adminCss = Get-Content -LiteralPath "$RepoRoot\babifix_admin_django\static\adminpanel\style.css" -Raw -Encoding UTF8
if ($adminCss -match '@keyframes pageIn\s*\{[^}]*transform:') {
    throw "REGRESSION CSS : @keyframes pageIn contient transform (casse position:fixed des modales)"
}
Write-Host "  OK : 100% des marqueurs critiques presents sur les 4 surfaces." -ForegroundColor Green

Write-Host "`n[2/5] Securite Git : controle secrets suivis..." -ForegroundColor Yellow
$tracked = git -C $RepoRoot ls-files
foreach ($f in $tracked) {
    if ($f -match '(^|/)\.env($|\.)' -and $f -notmatch '\.example$') {
        throw "ALERTE SECURITE : fichier .env suivi par Git : $f"
    }
    if ($f -match 'firebase-adminsdk|\.pem$|private_kyc/|\.sqlite3$') {
        throw "ALERTE SECURITE : fichier sensible suivi par Git : $f"
    }
}
Write-Host "  OK : Aucun secret ni fichier prive suivi par Git." -ForegroundColor Green

Write-Host "`n[3/5] Vitrine Django : check + tests..." -ForegroundColor Yellow
Push-Location "$RepoRoot\babifix_vitrine_django"
& ".\.venv\Scripts\python.exe" manage.py check
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
& ".\.venv\Scripts\python.exe" manage.py test vitrine.tests -v 1
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Write-Host "`n[4/5] Admin Django : check + tests..." -ForegroundColor Yellow
Push-Location "$RepoRoot\babifix_admin_django"
& ".\.venv\Scripts\python.exe" manage.py check --settings=config.test_settings
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
if ($Fast) {
    & ".\.venv\Scripts\python.exe" manage.py test adminpanel.tests.test_dashboard_smoke adminpanel.tests.test_security_pentest adminpanel.tests.test_smart_v2_features --settings=config.test_settings -v 1
} else {
    & ".\.venv\Scripts\python.exe" manage.py test --settings=config.test_settings -v 1
}
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Pop-Location

Write-Host "`n[5/5] Apps Flutter Client & Prestataire : analyze + tests..." -ForegroundColor Yellow
foreach ($app in @("babifix_client_flutter", "babifix_prestataire_flutter")) {
    Write-Host "  -> $app" -ForegroundColor Cyan
    Push-Location "$RepoRoot\$app"
    flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings
    if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
    flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
    Pop-Location
}

Write-Host "`n=== SUCCES : Zero regression detectee sur Vitrine, Admin, Client et Prestataire ===" -ForegroundColor Green
