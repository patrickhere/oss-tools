# fix.ps1
# Clears Office identity and license cache to fix account notice and activation loops

Write-Host "  BankOnIT OSS | Clear Office Cache" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (Test-Path $_upd) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }


# Check for running Office apps
$officeProcs = @("OUTLOOK", "WINWORD", "EXCEL", "POWERPNT", "ONENOTE", "TEAMS")
$running = Get-Process -Name $officeProcs -ErrorAction SilentlyContinue

if ($running) {
    Write-Host ""
    Write-Host "WARNING: The following Office apps are running:" -ForegroundColor Yellow
    $running | ForEach-Object { Write-Host "  $($_.Name)" }
    $kill = Read-Host "Force-close all Office apps before continuing? (Y/N)"
    if ($kill -match '^[Yy]$') {
        $running | Stop-Process -Force
        Write-Host "INFO: Office apps closed." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
    else {
        Write-Host ""
        Write-Host "INFO: Aborted. Close Office apps manually and re-run." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }
}

try {
    $cleared = @()
    $failed  = @()

    # Office license cache
    $licensePath = "$env:LOCALAPPDATA\Microsoft\Office\16.0\Licensing"
    if (Test-Path $licensePath) {
        try {
            Remove-Item -Path "$licensePath\*" -Recurse -Force -ErrorAction Stop
            $cleared += "Office license cache ($licensePath)"
        } catch {
            $failed += "Office license cache ($licensePath) -- $($_.Exception.Message)"
        }
    }

    # Office identity/token cache in registry
    $identityPath = "HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Identities"
    if (Test-Path $identityPath) {
        try {
            Remove-Item -Path $identityPath -Recurse -Force -ErrorAction Stop
            $cleared += "Office identity registry cache"
        } catch {
            $failed += "Office identity registry cache -- $($_.Exception.Message)"
        }
    }

    # Token broker cache
    $tokenPath = "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache"
    if (Test-Path $tokenPath) {
        try {
            Remove-Item -Path "$tokenPath\*" -Recurse -Force -ErrorAction Stop
            $cleared += "Token broker cache ($tokenPath)"
        } catch {
            $failed += "Token broker cache ($tokenPath) -- $($_.Exception.Message)"
        }
    }

    Write-Host ""
    if ($cleared.Count -gt 0) {
        Write-Host "SUCCESS: Cleared $($cleared.Count) cache location(s):" -ForegroundColor Green
        $cleared | ForEach-Object { Write-Host "  $_" }
    }
    else {
        Write-Host "INFO: No cache locations found -- nothing to clear." -ForegroundColor Yellow
    }
    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "WARNING: $($failed.Count) location(s) could not be cleared (files may be locked):" -ForegroundColor Yellow
        $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
    Write-Host "Sign back in to Office after reopening."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
