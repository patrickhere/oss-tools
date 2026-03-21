# fix.ps1
# Clears Teams cache folders to fix performance and sign-in issues

param([switch]$NonInteractive)

Write-Host "  BankOnIT OSS | Reset Teams Cache" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (Test-Path $_upd) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check for running Teams (classic or new)
$teams = Get-Process -Name @("Teams","ms-teams") -ErrorAction SilentlyContinue
if ($teams) {
    Write-Host ""
    Write-Host "WARNING: Teams is currently running." -ForegroundColor Yellow
    $kill = Read-Host "Force-close Teams before continuing? (Y/N)"
    if ($kill -match '^[Yy]$') {
        Get-Process -Name @("Teams","ms-teams") -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        Write-Host "INFO: Teams closed." -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host "INFO: Aborted. Close Teams manually and re-run." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }
}

try {
    $cleared = 0

    # Classic Teams (v1) -- %APPDATA%\Microsoft\Teams
    $classicBase = "$env:APPDATA\Microsoft\Teams"
    $classicDirs = @("Cache","blob_storage","databases","GPUCache","IndexedDB","Local Storage","tmp")
    if (Test-Path $classicBase) {
        foreach ($dir in $classicDirs) {
            $fullPath = "$classicBase\$dir"
            if (Test-Path $fullPath) {
                Remove-Item -Path "$fullPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                $cleared++
            }
        }
        Write-Host "INFO: Classic Teams cache cleared." -ForegroundColor Yellow
    }

    # New Teams (v2/MSIX) -- %LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams
    $newTeamsBase = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"
    if (Test-Path $newTeamsBase) {
        Remove-Item -Path "$newTeamsBase\*" -Recurse -Force -ErrorAction SilentlyContinue
        $cleared++
        Write-Host "INFO: New Teams cache cleared." -ForegroundColor Yellow
    }

    if ($cleared -eq 0) {
        Write-Host ""
        Write-Host "INFO: No Teams cache folders found -- nothing to clear." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    Write-Host ""
    Write-Host "SUCCESS: $cleared Teams cache location(s) cleared." -ForegroundColor Green
    Write-Host "Teams will rebuild cache on next launch."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
