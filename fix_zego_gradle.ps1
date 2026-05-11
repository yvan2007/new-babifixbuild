# ============================================================
# Fix ZEGOCLOUD Gradle Network Issue (artifact-node.zego.cloud)
# 
# Ce script copie les SDK natifs ZEGOCLOUD d'une version du cache
# vers une autre, pour eviter le telechargement depuis
# artifact-node.zego.cloud (qui ne fonctionne pas avec Java)
# ============================================================

param(
    [string]$SourceVersion = "3.23.0",
    [string]$TargetVersion = "3.24.1"
)

$pubCache = Join-Path $env:LOCALAPPDATA "Pub\Cache\hosted\pub.dev"
$sourceDir = Join-Path $pubCache "zego_express_engine-$SourceVersion\android\libs"
$targetDir = Join-Path $pubCache "zego_express_engine-$TargetVersion\android\libs"
$targetDeps = Join-Path $pubCache "zego_express_engine-$TargetVersion\DEPS.yaml"

Write-Host "ZEGOCLOUD Fix Script" -ForegroundColor Cyan
Write-Host "Source: $SourceVersion" -ForegroundColor Gray
Write-Host "Target: $TargetVersion" -ForegroundColor Gray
Write-Host ""

# Check if source exists
if (-not (Test-Path $sourceDir)) {
    Write-Host "ERROR: Source directory not found: $sourceDir" -ForegroundColor Red
    Write-Host "Looking for available versions..." -ForegroundColor Yellow
    
    $available = Get-ChildItem $pubCache -Filter "zego_express_engine-*" | Select-Object Name
    foreach ($v in $available) {
        $libsPath = Join-Path (Join-Path $pubCache $v.Name) "android\libs"
        if (Test-Path $libsPath) {
            $jarPath = Join-Path $libsPath "ZegoExpressEngine.jar"
            if (Test-Path $jarPath) {
                Write-Host "  FOUND: $($v.Name) - has valid SDK" -ForegroundColor Green
            }
        }
    }
    exit 1
}

# Check if target DEPS.yaml exists (to get expected version)
$expectedVersion = ""
if (Test-Path $targetDeps) {
    $depsContent = Get-Content $targetDeps
    $androidLine = $depsContent | Where-Object { $_ -like "android:*" }
    if ($androidLine -match "version=([\d\.]+)") {
        $expectedVersion = $matches[1]
        Write-Host "Expected version from DEPS.yaml: $expectedVersion" -ForegroundColor Green
    }
}

# Copy files
Write-Host ""
Write-Host "Copying SDK files..." -ForegroundColor Yellow

if (Test-Path $targetDir) {
    Remove-Item -Recurse -Force $targetDir -ErrorAction SilentlyContinue
}

Copy-Item -Path $sourceDir -Destination $targetDir -Recurse -Force

# Update VERSION.txt
$versionFile = Join-Path $targetDir "VERSION.txt"
if ($expectedVersion -and (Test-Path $versionFile)) {
    Write-Host "Updating VERSION.txt to: $expectedVersion" -ForegroundColor Yellow
    
    $versionContent = Get-Content $versionFile
    $newContent = @()
    $firstLine = $true
    foreach ($line in $versionContent) {
        if ($firstLine -and $line -match "^\d") {
            $newContent += $expectedVersion
            $firstLine = $false
        } else {
            $newContent += $line
            $firstLine = $false
        }
    }
    Set-Content -Path $versionFile -Value $newContent -NoNewline
}

# Verify
$jarFile = Join-Path $targetDir "ZegoExpressEngine.jar"
$versionFile = Join-Path $targetDir "VERSION.txt"

if ((Test-Path $jarFile) -and (Test-Path $versionFile)) {
    Write-Host ""
    Write-Host "SUCCESS! ZEGOCLOUD SDK is ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "SDK location: $targetDir" -ForegroundColor Gray
    Write-Host ""
    Write-Host "You can now run: flutter run" -ForegroundColor Cyan
} else {
    Write-Host "ERROR: Copy failed" -ForegroundColor Red
    exit 1
}
