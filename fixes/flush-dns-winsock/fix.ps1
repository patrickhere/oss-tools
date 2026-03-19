# fix.ps1
# Flushes DNS cache and resets Winsock

Write-Host "  BankOnIT OSS | Flush DNS / Winsock Reset" -ForegroundColor DarkGray
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
    Write-Host "INFO: Flushing DNS cache..." -ForegroundColor Yellow
    $dns = ipconfig /flushdns 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: DNS cache flushed." -ForegroundColor Green
    } else {
        Write-Host "WARNING: DNS flush returned exit code $LASTEXITCODE -- $dns" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "INFO: Resetting Winsock..." -ForegroundColor Yellow
    $winsock = netsh winsock reset 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Winsock reset. A reboot is required for this to fully take effect." -ForegroundColor Green
    } else {
        Write-Host "WARNING: Winsock reset returned exit code $LASTEXITCODE -- $winsock" -ForegroundColor Yellow
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
