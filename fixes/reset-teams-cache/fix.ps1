# fix.ps1
# Clears Teams cache folders to fix performance and sign-in issues

Write-Host "  BankOnIT OSS | Reset Teams Cache" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for running Teams
$teams = Get-Process -Name "Teams" -ErrorAction SilentlyContinue
if ($teams) {
    Write-Host ""
    Write-Host "WARNING: Teams is currently running." -ForegroundColor Yellow
    $kill = Read-Host "Force-close Teams before continuing? (Y/N)"
    if ($kill -match '^[Yy]$') {
        Get-Process -Name "Teams" -ErrorAction SilentlyContinue | Stop-Process -Force
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
    $teamsBase = "$env:APPDATA\Microsoft\Teams"
    $cacheDirs = @(
        "Cache",
        "blob_storage",
        "databases",
        "GPUCache",
        "IndexedDB",
        "Local Storage",
        "tmp"
    )

    if (!(Test-Path $teamsBase)) {
        Write-Host ""
        Write-Host "INFO: Teams cache folder not found -- nothing to clear." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }

    $cleared = 0
    foreach ($dir in $cacheDirs) {
        $fullPath = "$teamsBase\$dir"
        if (Test-Path $fullPath) {
            Remove-Item -Path "$fullPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            $cleared++
        }
    }

    Write-Host ""
    Write-Host "SUCCESS: $cleared Teams cache folder(s) cleared." -ForegroundColor Green
    Write-Host "Teams will rebuild cache on next launch."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
