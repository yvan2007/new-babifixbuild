<#
.SYNOPSIS
    Triage automatise des incidents et latences depuis l'export Sante & Erreurs Live (/api/admin/observability/export/).
.DESCRIPTION
    Lit un fichier JSON exporte depuis le Cockpit Sante (ex: babifix_sante_diagnostic.json) ou appelle l'API
    admin si un cookie de session valide est fourni via variable d'environnement BABIFIX_ADMIN_COOKIE.
    Regroupe les incidents par empreinte, mappe les fichiers source concernes et produit un rapport de diagnostic
    pret pour arbitrage avant correctif (Human-in-the-Loop). Aucun deploiement automatique n'est effectue.
#>
param(
    [string]$InputJsonPath = "babifix_sante_diagnostic.json",
    [string]$BaseUrl = "https://new-babifixbuild.onrender.com",
    [string]$OutMarkdownPath = ""
)

$ErrorActionPreference = "Stop"

$rawJson = ""
if ($InputJsonPath -and (Test-Path -LiteralPath $InputJsonPath)) {
    $rawJson = Get-Content -LiteralPath $InputJsonPath -Raw -Encoding UTF8
} elseif ($env:BABIFIX_ADMIN_COOKIE) {
    $uri = "$($BaseUrl.TrimEnd('/'))/api/admin/observability/export/?format=json&status=open&limit=500"
    $headers = @{ Cookie = $env:BABIFIX_ADMIN_COOKIE }
    $resp = Invoke-WebRequest -Uri $uri -Headers $headers -TimeoutSec 25 -UseBasicParsing
    $rawJson = $resp.Content
} else {
    Write-Host "Aucun fichier trouve a '$InputJsonPath' et variable d'environnement BABIFIX_ADMIN_COOKIE absente." -ForegroundColor Yellow
    Write-Host "Telechargez 'Export JSON' depuis l'onglet Sante du dashboard Admin puis relancez:" -ForegroundColor Cyan
    Write-Host "  powershell -ExecutionPolicy Bypass -File scripts/auto_triage_observability.ps1 -InputJsonPath .\babifix_sante_diagnostic.json" -ForegroundColor Gray
    exit 1
}

$data = $rawJson | ConvertFrom-Json
$events = @($data.events)

function Resolve-HintFile {
    param([string]$Endpoint, [string]$SourceFile)
    if ($SourceFile -and $SourceFile.Trim().Length -gt 0) { return $SourceFile }
    switch -Regex ($Endpoint) {
        "^/api/client/home"         { return "babifix_admin_django/adminpanel/views.py (api_client_home) + babifix_client_flutter/lib/user_store.dart" }
        "^/api/public/providers"    { return "babifix_admin_django/adminpanel/views.py (api_public_providers)" }
        "^/api/public/config"       { return "babifix_admin_django/adminpanel/services/platform_config_service.py" }
        "^/api/app/log-error"       { return "babifix_client_flutter/lib/shared/widgets/error_reporter.dart" }
        "^/api/auth/"               { return "babifix_admin_django/adminpanel/views.py + mobile social_auth_service.dart" }
        "^/$"                       { return "babifix_admin_django/adminpanel/views.py (_dashboard_kpi_payload)" }
        default                     { return "babifix_admin_django/adminpanel/views*.py" }
    }
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# Rapport Auto-Triage BABIFIX Observability")
$lines.Add("Genere le : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Source : $($data.exported_at)")
$lines.Add("RAM process : $($data.ram_mb) Mo | Firebase ready : $($data.integrations.firebase.ready)")
$lines.Add("")

if ($data.summary_24h) {
    $s = $data.summary_24h
    $lines.Add("## Resume 24h")
    $lines.Add("- Total incidents : $($s.total) | Erreurs ouvertes : $($s.open_errors) | Lenteurs : $($s.slow_count)")
    $lines.Add("- Mobile : $($s.mobile_count) | Vitrine : $($s.vitrine_count) | Latence moy : $($s.avg_ms) ms (max $($s.max_ms) ms)")
    $lines.Add("")
}

$openEvents = @($events | Where-Object { -not $_.resolved })
$groups = $openEvents | Group-Object -Property fingerprint, level, source, endpoint | Sort-Object Count -Descending

$lines.Add("## Groupes d'incidents ouverts ($($openEvents.Count) evenements, $($groups.Count) signatures)")
foreach ($g in ($groups | Select-Object -First 25)) {
    $first = $g.Group[0]
    $totalOcc = ($g.Group | Measure-Object -Property occurrence_count -Sum).Sum
    $maxMs = ($g.Group | Measure-Object -Property duration_ms -Maximum).Maximum
    $hint = Resolve-HintFile -Endpoint "$($first.endpoint)" -SourceFile "$($first.source_file)"
    $lines.Add("- [$($first.level)] ($($g.Count) entrees / $totalOcc occurrences, max ${maxMs} ms) $($first.method) $($first.endpoint) [HTTP $($first.status_code)] -> Fichier cible : $hint | Message : $($first.message)")
}

$report = $lines -join "`n"
Write-Output $report
if ($OutMarkdownPath -and $OutMarkdownPath.Trim().Length -gt 0) {
    Set-Content -LiteralPath $OutMarkdownPath -Value $report -Encoding UTF8
    Write-Host "`nRapport ecrit dans $OutMarkdownPath" -ForegroundColor Green
}
