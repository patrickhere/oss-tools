param([switch]$NonInteractive)
# config.ps1
# Disables consumer OneDrive auto-install and removes it from the startup run key

Write-Host "  Navanta OSS | Disable OneDrive Auto-Install" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (-not $env:OSSMANAGED -and (Test-Path $_upd)) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

try {
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"

    if (!(Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }

    Set-ItemProperty -Path $policyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord
    Write-Host ""
    Write-Host "INFO: OneDrive file sync policy applied." -ForegroundColor Yellow

    # Remove OneDrive from the machine-wide startup run key if present
    $runPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $runProp = Get-ItemProperty -Path $runPath -Name "OneDrive" -ErrorAction SilentlyContinue
    if ($runProp) {
        Remove-ItemProperty -Path $runPath -Name "OneDrive" -Force
        Write-Host "INFO: OneDrive removed from startup run key." -ForegroundColor Yellow
    }
    else {
        Write-Host "INFO: OneDrive not present in startup run key (nothing to remove)." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "SUCCESS: OneDrive auto-install suppressed." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
if (-not $NonInteractive) {
    Read-Host "Press Enter to close"
}
