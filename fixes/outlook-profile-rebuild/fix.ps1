# fix.ps1
# Deletes Outlook profile(s) from registry so Outlook prompts for a fresh setup

param([switch]$NonInteractive)

Write-Host "  BankOnIT OSS | Outlook Profile Rebuild" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (Test-Path $_upd) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$profilesPath = "HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles"

try {
    # Check for running Outlook
    $outlook = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
    if ($outlook) {
        Write-Host ""
        Write-Host "WARNING: Outlook is currently running." -ForegroundColor Yellow
        $kill = Read-Host "Force-close Outlook before continuing? (Y/N)"
        if ($kill -match '^[Yy]$') {
            Stop-Process -Name "OUTLOOK" -Force
            Write-Host "INFO: Outlook closed." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
        else {
            Write-Host ""
            Write-Host "INFO: Aborted. Close Outlook manually and re-run." -ForegroundColor Yellow
            Write-Host ""
            Read-Host "Press Enter to close"
            exit 0
        }
    }

    # List existing profiles
    if (!(Test-Path $profilesPath)) {
        Write-Host ""
        Write-Host "INFO: No Outlook profiles found at expected registry path." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    $profiles = @(Get-ChildItem -Path $profilesPath | Select-Object -ExpandProperty PSChildName)

    if ($profiles.Count -eq 0) {
        Write-Host ""
        Write-Host "INFO: No profiles found." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    Write-Host ""
    Write-Host "Existing Outlook profiles:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "  $($i + 1). $($profiles[$i])"
    }
    Write-Host "  A. All profiles"

    Write-Host ""
    $choice = Read-Host "Select profile to delete (number or A)"

    $toDelete = @()
    if ($choice -match '^[Aa]$') {
        $toDelete = $profiles
    }
    elseif ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        if ($idx -ge 0 -and $idx -lt $profiles.Count) {
            $toDelete = @($profiles[$idx])
        }
        else {
            Write-Host ""
            Write-Host "ERROR: Invalid selection." -ForegroundColor Red
            Write-Host ""
            Read-Host "Press Enter to close"
            exit 1
        }
    }
    else {
        Write-Host ""
        Write-Host "ERROR: Invalid input." -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 1
    }

    # Delete selected profiles
    foreach ($profile in $toDelete) {
        Remove-Item -Path "$profilesPath\$profile" -Recurse -Force
        Write-Host "  Deleted: $profile" -ForegroundColor Yellow
    }

    # Clear DefaultProfile so Outlook prompts on next launch
    $outlookKey = "HKCU:\Software\Microsoft\Office\16.0\Outlook"
    if (Get-ItemProperty -Path $outlookKey -Name "DefaultProfile" -ErrorAction SilentlyContinue) {
        Remove-ItemProperty -Path $outlookKey -Name "DefaultProfile" -Force
    }

    Write-Host ""
    Write-Host "SUCCESS: $($toDelete.Count) profile(s) removed. Outlook will prompt for new profile on next launch." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
