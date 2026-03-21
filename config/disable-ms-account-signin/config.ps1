param([switch]$NonInteractive)
# config.ps1
# Blocks personal Microsoft account authentication machine-wide via Windows policy.
# This prevents MSA sign-in prompts in Office and across the OS (Settings, Store, etc.).

Write-Host "  BankOnIT OSS | Disable MS Account Sign-in" -ForegroundColor DarkGray
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
    $path = "HKLM:\Software\Policies\Microsoft\MicrosoftAccount"

    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "DisableUserAuth" -Value 1 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: Personal Microsoft account sign-in blocked (machine-wide)." -ForegroundColor Green
    Write-Host "Users will not be prompted to sign in with personal Microsoft accounts in Office or Windows."
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
