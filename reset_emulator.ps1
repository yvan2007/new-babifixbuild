param([string]$AvdName = "Pixel_10_Pro_XL")

Write-Host "=== Arret de tous les processus emulator ==="
Get-Process -Name "qemu-system-x86_64*","emulator*","adb*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2

Write-Host "=== Suppression du snapshot corrompu ==="
$snap = "$env:USERPROFILE\.android\avd\${AvdName}.avd\snapshots"
if (Test-Path $snap) {
    Remove-Item "$snap\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Snapshots effaces"
}

Write-Host "=== Wipe data et demarrage frais ==="
& "C:\Users\kouay\AppData\Local\Android\Sdk\emulator\emulator.exe" -avd $AvdName -wipe-data -no-snapshot