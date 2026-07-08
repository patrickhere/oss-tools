# fix.ps1
# Clears stale Exchange/Office credentials from the Windows Credential Manager

param([switch]$NonInteractive)

Write-Host "  Navanta OSS | Credential Cleanup" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (-not $env:OSSMANAGED -and (Test-Path $_upd)) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$patterns = @(
    "MicrosoftOffice",
    "outlook",
    "exchange",
    "graph.microsoft.com",
    "outlook.office365.com",
    "office.com"
)

try {
    $raw = cmdkey /list 2>&1
    $targets = @()

    foreach ($line in $raw) {
        if ($line -match "Target:\s*(.+)") {
            $target = $matches[1].Trim()
            foreach ($p in $patterns) {
                if ($target -like "*$p*") {
                    $targets += $target
                    break
                }
            }
        }
    }

    $targets = @($targets | Sort-Object -Unique)

    if ($targets.Count -eq 0) {
        Write-Host ""
        Write-Host "INFO: No matching credentials found." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    Write-Host ""
    Write-Host "Found $($targets.Count) matching credential(s):" -ForegroundColor Yellow
    foreach ($t in $targets) {
        Write-Host "  $t"
    }

    Write-Host ""
    $confirm = Read-Host "Delete all listed credentials? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host ""
        Write-Host "INFO: Aborted. No credentials deleted." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    $failures = @()
    foreach ($t in $targets) {
        $result = cmdkey /delete:$t 2>&1
        if ($LASTEXITCODE -ne 0) {
            $failures += $t
        }
    }

    Write-Host ""
    if ($failures.Count -eq 0) {
        Write-Host "SUCCESS: All $($targets.Count) credential(s) removed." -ForegroundColor Green
    }
    else {
        Write-Host "WARNING: $($targets.Count - $failures.Count) removed, $($failures.Count) failed:" -ForegroundColor Yellow
        foreach ($f in $failures) {
            Write-Host "  FAILED: $f" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
