param([switch]$NonInteractive)
# config.ps1
# Prevents Windows Update from auto-rebooting and from auto-installing updates while users are logged in.
# Sets AUOptions=3: updates download automatically but require manual install trigger.

Write-Host "  Navanta OSS | Disable Update Auto-Reboot" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (Test-Path $_upd) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }
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
    $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    if (!(Test-Path $auPath)) {
        New-Item -Path $auPath -Force | Out-Null
    }

    # Do not reboot while a user is logged in
    Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
    # Auto-download but notify before installing (lets IT control timing)
    Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 3 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: Windows Update reboot and auto-install suppressed." -ForegroundColor Green
    Write-Host "Updates will download automatically but will NOT install or reboot while users are logged in."
    Write-Host "Technician or user must manually trigger installs."
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
