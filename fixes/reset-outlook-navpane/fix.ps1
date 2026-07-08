# fix.ps1
# Resets the Outlook navigation pane to fix corrupt nav pane issues

param([switch]$NonInteractive)

Write-Host "  Navanta OSS | Reset Outlook Nav Pane" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (-not $env:OSSMANAGED -and (Test-Path $_upd)) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check Outlook not already running
$outlook = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
if ($outlook) {
    Write-Host ""
    Write-Host "WARNING: Outlook is currently running." -ForegroundColor Yellow
    $kill = Read-Host "Force-close Outlook before continuing? (Y/N)"
    if ($kill -match '^[Yy]$') {
        Stop-Process -Name "OUTLOOK" -Force
        Start-Sleep -Seconds 2
        Write-Host "INFO: Outlook closed." -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host "INFO: Aborted. Close Outlook manually and re-run." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }
}

try {
    # Find Outlook.exe
    $outlookPath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE" -ErrorAction SilentlyContinue).'(Default)'

    if (!$outlookPath) {
        $candidates = @(
            "$env:ProgramFiles\Microsoft Office\root\Office16\OUTLOOK.EXE",
            "$env:ProgramFiles\Microsoft Office\Office16\OUTLOOK.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OUTLOOK.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OUTLOOK.EXE"
        )
        $outlookPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if (!$outlookPath) {
        Write-Host ""
        Write-Host "ERROR: Could not locate Outlook.exe." -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 1
    }

    Write-Host ""
    Write-Host "INFO: Launching Outlook with /resetnavpane -- Outlook will open briefly." -ForegroundColor Yellow
    Start-Process $outlookPath -ArgumentList "/resetnavpane"

    Write-Host ""
    Write-Host "SUCCESS: Nav pane reset applied. Close Outlook and reopen normally." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
