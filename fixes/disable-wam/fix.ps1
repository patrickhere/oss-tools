# fix.ps1
# Disables WAM (Web Account Manager) for Office authentication

param([string]$Environment = "onprem")

Write-Host "  BankOnIT OSS | Disable WAM" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (Test-Path $_upd) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }

Write-Host ""
Write-Host "  environment: $Environment" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

# WAM/ADAL is required for M365 modern auth -- do not disable on cloud-only clients
if ($Environment -eq "m365") {
    Write-Host ""
    Write-Host "WARNING: This client is M365 (cloud only)." -ForegroundColor Yellow
    Write-Host "Disabling WAM on an M365 environment will break modern authentication" -ForegroundColor Yellow
    Write-Host "and cause sign-in loops. This fix is not applicable here." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 0
}

# Hybrid -- warn but allow
if ($Environment -eq "hybrid") {
    Write-Host ""
    Write-Host "WARNING: This client is hybrid (Exchange + M365)." -ForegroundColor Yellow
    Write-Host "Disabling WAM on a hybrid environment can cause auth issues for M365 services." -ForegroundColor Yellow
    Write-Host "Only proceed if you have confirmed WAM is the root cause." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Proceed anyway? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host ""
        Write-Host "INFO: Aborted." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }
}

try {
    $path = "HKLM:\Software\Microsoft\Office\16.0\Common\Identity"

    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "EnableADAL" -Value 0 -Type DWord
    Set-ItemProperty -Path $path -Name "DisableAADWAM" -Value 1 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: WAM disabled for Office on this machine." -ForegroundColor Green
    Write-Host "Office will use legacy credential prompts instead of WAM."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
