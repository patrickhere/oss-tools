# fix.ps1
# Clears the print queue and restarts the spooler

Write-Host "  BankOnIT OSS | Fix Print Spooler" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

try {
    Write-Host ""
    Write-Host "INFO: Stopping print spooler..." -ForegroundColor Yellow
    Stop-Service -Name Spooler -Force -ErrorAction Stop

    Write-Host "INFO: Clearing spool queue..." -ForegroundColor Yellow
    $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
    $files = Get-ChildItem -Path $spoolPath -ErrorAction SilentlyContinue
    if ($files) {
        Remove-Item -Path "$spoolPath\*" -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "INFO: $($files.Count) spool file(s) removed." -ForegroundColor Yellow
    }
    else {
        Write-Host "INFO: Spool queue already empty." -ForegroundColor Yellow
    }

    Write-Host "INFO: Starting print spooler..." -ForegroundColor Yellow
    Start-Service -Name Spooler -ErrorAction Stop

    Write-Host ""
    Write-Host "SUCCESS: Print spooler restarted and queue cleared." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "INFO: Attempting to restart spooler anyway..." -ForegroundColor Yellow
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
}

Write-Host ""
Read-Host "Press Enter to close"
