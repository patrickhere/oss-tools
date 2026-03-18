# fix.ps1
# Blocks Entra ID device registration nag on domain-joined machines

param([string]$Environment = "onprem")

Write-Host "  BankOnIT OSS | Block AAD Workplace Join" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
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

# Warn on M365/hybrid -- blocking workplace join can break Conditional Access
if ($Environment -eq "m365" -or $Environment -eq "hybrid") {
    Write-Host ""
    Write-Host "WARNING: This client is $Environment." -ForegroundColor Yellow
    Write-Host "Blocking AAD Workplace Join on M365 or hybrid environments can break" -ForegroundColor Yellow
    Write-Host "Conditional Access policies and modern authentication flows." -ForegroundColor Yellow
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
    $path = "HKLM:\Software\Policies\Microsoft\Windows\WorkplaceJoin"

    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "BlockAADWorkplaceJoin" -Value 1 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: AAD Workplace Join blocked for this machine." -ForegroundColor Green
    Write-Host "The 'Your organization wants to manage this device' prompt will no longer appear."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
