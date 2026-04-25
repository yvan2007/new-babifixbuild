# BABIFIX Build - Startup Script
# Double-click this file OR run from PowerShell

# Auto-activate venv and run Django
& {
    $venvPath = "C:\Users\kouay\Documents\BABIFIX_BUILD\venv\Scripts\Activate.ps1"
    if (Test-Path $venvPath) {
        Write-Host "[OK] Activating venv..." -ForegroundColor Green
        & $venvPath
        
        Set-Location "C:\Users\kouay\Documents\BABIFIX_BUILD\babifix_admin_django"
        Write-Host "[OK] Starting Django on port 8002..." -ForegroundColor Green
        
        python manage.py runserver 0.0.0.0:8002
    } else {
        Write-Host "[ERROR] venv not found!" -ForegroundColor Red
        Write-Host "Creating venv..." -ForegroundColor Yellow
        
        python -m venv venv
        & $venvPath
        pip install -r requirements.txt
        
        Write-Host "[OK] venv created. Run script again." -ForegroundColor Green
    }
}

# Keep console open
Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("Options,IncludeKeyDown")