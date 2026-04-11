# Installe les dependances Python du backend admin (daphne, PyMySQL, etc.)
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root "babifix_admin_django")
if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    Write-Host "Creation du venv..."
    python -m venv .venv
}
& .\.venv\Scripts\Activate.ps1
python -m pip install -U pip
pip install -r requirements.txt
Write-Host "OK. Ensuite: copier .env.example vers .env, puis python manage.py migrate"
