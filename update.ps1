# update.ps1
# Checks Forgejo for a newer version of the OSS toolkit and offers to update.
# Called by launcher.bat on startup. Fails silently if the server is unreachable.

$repoUrl      = "https://git.hartforge.dev/patrickhere/oss-tools"
$versionUrl   = "$repoUrl/raw/branch/main/version.txt"
$archiveUrl   = "$repoUrl/archive/main.zip"
$localFile    = Join-Path $PSScriptRoot "version.txt"

$localVersion = if (Test-Path $localFile) { (Get-Content $localFile -Raw).Trim() } else { "0" }

$zipPath     = Join-Path $env:TEMP "oss-tools-update.zip"
$extractPath = Join-Path $env:TEMP "oss-tools-update"
$downloadOk  = $false

try {
    $response      = Invoke-WebRequest -Uri $versionUrl -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    $remoteVersion = $response.Content.Trim()

    if ($remoteVersion -eq $localVersion) {
        Write-Host "  version $localVersion (up to date)" -ForegroundColor DarkGray
        exit 0
    }

    Write-Host ""
    Write-Host "  update available: $localVersion -> $remoteVersion" -ForegroundColor Yellow
    $choice = Read-Host "  download and install now? (Y/N)"

    if ($choice -notmatch '^[Yy]$') {
        Write-Host "  skipping update." -ForegroundColor DarkGray
        exit 0
    }

    Write-Host "  downloading v$remoteVersion..." -ForegroundColor Yellow

    Invoke-WebRequest -Uri $archiveUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop

    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # Forgejo extracts as <repo>-<branch>/ e.g. oss-tools-main/
    $extracted = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
    if (-not $extracted) {
        Write-Host "  ERROR: could not find extracted folder -- update aborted." -ForegroundColor Red
        exit 1
    }

    $downloadOk = $true
    Copy-Item -Path "$($extracted.FullName)\*" -Destination $PSScriptRoot -Recurse -Force -ErrorAction Stop
    Write-Host "  updated to v$remoteVersion." -ForegroundColor Green
    Write-Host "  re-run the script to use the new version." -ForegroundColor Green
}
catch {
    if ($downloadOk) {
        # Failed during file copy -- toolkit may be in a partial state
        Write-Host "  ERROR: update failed during install -- re-run the launcher to try again." -ForegroundColor Red
        exit 1
    }
    # Network/server unreachable -- silent, don't interrupt the tool
    Write-Host "  version $localVersion" -ForegroundColor DarkGray
    exit 0
}
finally {
    Remove-Item $zipPath     -Force -ErrorAction SilentlyContinue
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Read-Host "  press Enter to close"
exit 2  # signal to caller: updated, do not continue
