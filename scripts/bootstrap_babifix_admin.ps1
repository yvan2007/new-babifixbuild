# Preparation BABIFIX admin : venv, pip, base MySQL WAMP, migrate, superutilisateur.
# Usage : depuis BABIFIX_BUILD  ->  .\scripts\bootstrap_babifix_admin.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$admin = Join-Path $root "babifix_admin_django"
Set-Location $admin

$mysqlExe = $null
foreach ($p in @(
    "C:\wamp64\bin\mysql\mysql9.1.0\bin\mysql.exe",
    "C:\wamp64\bin\mysql\mysql8.4.0\bin\mysql.exe",
    "C:\wamp64\bin\mysql\mysql8.3.0\bin\mysql.exe"
)) {
    if (Test-Path $p) { $mysqlExe = $p; break }
}
if (-not $mysqlExe) {
    $found = Get-ChildItem "C:\wamp64\bin\mysql" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $c = Join-Path $_.FullName "bin\mysql.exe"
        if (Test-Path $c) { $c }
    } | Select-Object -First 1
    $mysqlExe = $found
}

if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    Write-Host "Creation du venv..."
    python -m venv .venv
}

Write-Host "pip install -r requirements.txt ..."
& .\.venv\Scripts\python.exe -m pip install -U pip -q
& .\.venv\Scripts\pip.exe install -r requirements.txt -q

if ($mysqlExe) {
    Write-Host "DROP/CREATE base babifix (MySQL)..."
    & $mysqlExe -u root -e "DROP DATABASE IF EXISTS babifix; CREATE DATABASE babifix CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1 | Out-Null
} else {
    Write-Warning "mysql.exe WAMP introuvable : creez la base 'babifix' dans phpMyAdmin puis : python manage.py migrate"
}

Write-Host "migrate..."
& .\.venv\Scripts\python.exe manage.py migrate --noinput

$py = @"
from django.contrib.auth import get_user_model
U = get_user_model()
u, p = 'babifix_admin', 'BabifixDev2026!'
if not U.objects.filter(username=u).exists():
    U.objects.create_superuser(u, 'admin@babifix.local', p)
    print('CREATED', u)
else:
    print('EXISTS', u)
"@
& .\.venv\Scripts\python.exe manage.py shell -c $py

Write-Host ""
Write-Host "=== Connexion panel /admin ===" -ForegroundColor Green
Write-Host "  URL           : http://127.0.0.1:8002/admin/"
Write-Host "  Utilisateur   : babifix_admin"
Write-Host "  Mot de passe  : BabifixDev2026!"
Write-Host ""
Write-Host "Lancer le serveur :" -ForegroundColor Cyan
Write-Host "  cd babifix_admin_django"
Write-Host "  .\.venv\Scripts\activate"
Write-Host "  python manage.py runserver 0.0.0.0:8002"
