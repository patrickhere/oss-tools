param([switch]$NonInteractive)
# config.ps1
# Prevents consumer Teams from auto-installing and launching on first logon

Write-Host "  Navanta OSS | Disable Teams Auto-Install" -ForegroundColor DarkGray
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
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Teams"
    $teamsPath  = "HKLM:\SOFTWARE\Microsoft\Teams"

    foreach ($path in @($policyPath, $teamsPath)) {
        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }

    Set-ItemProperty -Path $policyPath -Name "PreventFirstLaunchAfterLogon" -Value 1 -Type DWord
    Set-ItemProperty -Path $policyPath -Name "PreventInstallationFromMsi"   -Value 1 -Type DWord
    Set-ItemProperty -Path $teamsPath  -Name "PreventFirstLaunchAfterLogon" -Value 1 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: Teams auto-install and first-launch suppressed." -ForegroundColor Green
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
