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

    Write-Host "INFO: Checking spool queue..." -ForegroundColor Yellow
    $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
    $files = Get-ChildItem -Path $spoolPath -ErrorAction SilentlyContinue
    if ($files) {
        Write-Host "WARNING: $($files.Count) queued print job(s) will be permanently deleted." -ForegroundColor Yellow
        $confirm = Read-Host "Continue? (Y/N)"
        if ($confirm -notmatch '^[Yy]$') {
            Start-Service -Name Spooler -ErrorAction SilentlyContinue
            Write-Host "INFO: Aborted. Spooler restarted without clearing queue." -ForegroundColor Yellow
            Read-Host "Press Enter to close"
            exit 0
        }
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
