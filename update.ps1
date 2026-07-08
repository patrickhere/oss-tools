# update.ps1
# Checks Forgejo for a newer version of the OSS toolkit and offers to update.
# Called by launcher.bat on startup. Fails silently if the server is unreachable.
#
# Hardening notes:
# - TLS 1.2+ enforced, and the server certificate issuer is verified against the
#   CAs that legitimately issue for hartforge.dev (pinned via CAA records). A
#   corporate SSL-inspection proxy or MITM presents its own CA and the update
#   aborts instead of executing whatever it serves.
# - Updates are staged to %TEMP% and mirrored per-directory, so files removed
#   upstream actually disappear locally instead of lingering forever.
# - launcher.bat is never overwritten while cmd is executing it: the new copy
#   lands as launcher.bat.new and a detached swap runs after the launcher exits.
# - Residual risk: a compromise of the git server itself can still ship code.
#   That box is CrowdSec-protected, Cloudflare-fronted and SSH is tailnet-only.

$repoHost     = "git.hartforge.dev"
$repoUrl      = "https://$repoHost/patrickhere/oss-tools"
$versionUrl   = "$repoUrl/raw/branch/main/version.txt"
$archiveUrl   = "$repoUrl/archive/main.zip"
$localFile    = Join-Path $PSScriptRoot "version.txt"

# CAs that may legitimately issue for hartforge.dev (matches the domain's CAA
# records: letsencrypt + the CAs cloudflare uses for edge certs)
$trustedIssuers = 'Let''s Encrypt|Google Trust Services|GTS CA|Cloudflare|DigiCert|SSL\.com|Sectigo|COMODO'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor 3072

function Test-ServerCertIssuer {
    # returns $true when the TLS cert chain looks like the real edge, $false on
    # an interception proxy. fails open only on plain network errors (offline).
    try {
        $tcp = New-Object Net.Sockets.TcpClient($repoHost, 443)
        try {
            $ssl = New-Object Net.Security.SslStream($tcp.GetStream(), $false, { $true })
            $ssl.AuthenticateAsClient($repoHost)
            $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
            return ($cert.Issuer -match $trustedIssuers)
        } finally { $tcp.Close() }
    } catch { return $null }  # unreachable - let the caller handle silence
}

$localVersion = if (Test-Path $localFile) { (Get-Content $localFile -Raw).Trim() } else { "0" }

$zipPath     = Join-Path $env:TEMP "oss-tools-update.zip"
$extractPath = Join-Path $env:TEMP "oss-tools-update"
$downloadOk  = $false

try {
    $certOk = Test-ServerCertIssuer
    if ($certOk -eq $false) {
        Write-Host "  WARNING: TLS certificate for $repoHost is not from an expected CA." -ForegroundColor Red
        Write-Host "  This network is likely intercepting HTTPS - update skipped for safety." -ForegroundColor Red
        exit 0
    }

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
    $src = $extracted.FullName

    # mirror content directories so upstream deletions take effect locally.
    # Logs\ and Backups\ are local-only and never part of the repo - untouched.
    foreach ($dir in Get-ChildItem -Path $src -Directory) {
        if ($dir.Name -in @('Logs','Backups')) { continue }
        $null = robocopy $dir.FullName (Join-Path $PSScriptRoot $dir.Name) /MIR /NFL /NDL /NJH /NJS
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $($dir.Name) (code $LASTEXITCODE)" }
    }

    # root files: everything except the launcher (cmd is still executing it)
    foreach ($file in Get-ChildItem -Path $src -File) {
        if ($file.Name -ieq 'launcher.bat') {
            Copy-Item $file.FullName (Join-Path $PSScriptRoot 'launcher.bat.new') -Force
        } else {
            Copy-Item $file.FullName (Join-Path $PSScriptRoot $file.Name) -Force
        }
    }

    # swap the launcher in after it has exited (exit 2 below stops it immediately)
    if (Test-Path (Join-Path $PSScriptRoot 'launcher.bat.new')) {
        Start-Process cmd -ArgumentList "/c ping -n 3 127.0.0.1 >nul & move /y `"$PSScriptRoot\launcher.bat.new`" `"$PSScriptRoot\launcher.bat`"" -WindowStyle Hidden
    }

    Write-Host "  updated to v$remoteVersion." -ForegroundColor Green
    Write-Host "  re-run the launcher to use the new version." -ForegroundColor Green
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
