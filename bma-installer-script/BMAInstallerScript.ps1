param([switch]$DryRun)

$ClientNumber   = "CLIENTID"
$ClientPassword = 'CLIENTPASSWORD'
# Branch/site number for this location (HQ = 1, second branch = 2, third = 3, ...).
# Find it in SmartTrak. Use one installer folder per branch when a client has several.
$BMASite        = 1

#DON'T TOUCH BELOW THIS LINE
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$WorkDir           = 'C:\BankOnIT'
$LogDir            = Join-Path $WorkDir 'Logs'
$Log               = Join-Path $LogDir 'BMAInstall_Log.txt'
$fileDirectory     = Join-Path $WorkDir 'BMAInstaller'
$fileDirectoryZip  = Join-Path $WorkDir 'BMAInstaller.zip'
$WorkstationApiUrl = 'https://api.boit.us/downloads/workstationBinaries/BMAInstaller.zip'
$ServerApiUrl      = 'https://api.boit.us/downloads/serverBinaries/BMAInstaller.zip'

# Exit codes (RunBMAInstaller.bat and RMM tooling key alerting off these):
#   0 = success / desired state already met / dry run complete
#   1 = not elevated
#   2 = unsupported OS
#   3 = download or extract failed
#   4 = installer missing after extract
#   5 = installer failed to launch
#   6 = install ran but BMA services are not running

if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Roll the log once it passes 1 MB so it can't grow without bound on machines that re-run this each boot.
$MaxLogBytes = 1MB
if ((Test-Path $Log) -and (Get-Item $Log).Length -gt $MaxLogBytes) {
    Move-Item -Path $Log -Destination "$Log.1" -Force
}

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $Log -Value "$stamp  $Message"
    Write-Host "$stamp  $Message"
}

function Get-BmaServiceStatus {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) { return $svc.Status } else { return 'NotInstalled' }
}

function Test-BmaRunning {
    foreach ($name in 'BMA Maintenance Service','BMA Service') {
        if ((Get-BmaServiceStatus $name) -eq 'Running') { return $true }
    }
    return $false
}

# Scrubs credential-looking JSON fields and RSA key XML fragments from a file in-place.
function Protect-SensitiveFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    $content = Get-Content -Path $Path -Raw -ErrorAction SilentlyContinue
    if (-not $content) { return }
    $jsonFields = '"(endpointPassword|privateKey|password|clientPassword|ClientPassword|apiKey|token)":"[^"]*"'
    $content = [regex]::Replace($content, $jsonFields, '"$1":"***REDACTED***"')
    $content = [regex]::Replace($content, '<RSAKeyValue>.*?</RSAKeyValue>', '<RSAKeyValue>***REDACTED***</RSAKeyValue>', 'Singleline')
    Set-Content -Path $Path -Value $content
}

# Deploys the BMA Interface tray app (a no-interaction system-tray program) when it isn't
# already installed, and makes sure something starts it in the user's session at logon.
# BMAInstaller.exe normally handles this; this is a safety net for when it didn't. A tray
# icon can only appear in an interactive user session, so we never launch it from a
# SYSTEM/startup (session 0) run -- we deploy + register autostart and let logon start it.
function Confirm-BmaInterface {
    param([string]$SourceZip)
    $ifaceDir = 'C:\Program Files\BankOnIT\BMA\BMA Interface'
    $ifaceExe = Join-Path $ifaceDir 'BMAInterface.exe'

    # 1) Ensure the files are present; deploy from the zip if the exe is missing.
    if (Test-Path $ifaceExe) {
        Write-Log "BMA Interface already present at $ifaceExe."
    }
    elseif (-not (Test-Path $SourceZip)) {
        Write-Log "BMA Interface missing and source zip not found ($SourceZip); skipping interface deploy."
        return
    }
    else {
        Write-Log "BMA Interface not installed; deploying from $SourceZip ..."
        $stage = Join-Path $fileDirectory 'BMAInterface_stage'
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $SourceZip -DestinationPath $stage -Force
        # The zip nests its payload under a subfolder, so copy from wherever the exe actually landed.
        $staged = Get-ChildItem $stage -Recurse -Filter 'BMAInterface.exe' | Select-Object -First 1
        if (-not $staged) {
            Write-Log "BMAInterface.exe not found inside $SourceZip; aborting interface deploy."
            Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
            return
        }
        if (-not (Test-Path $ifaceDir)) { New-Item -ItemType Directory -Path $ifaceDir -Force | Out-Null }
        Copy-Item -Path (Join-Path $staged.DirectoryName '*') -Destination $ifaceDir -Recurse -Force
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $ifaceExe) { Write-Log "BMA Interface files deployed to $ifaceDir." }
        else { Write-Log "BMA Interface deploy failed; $ifaceExe still missing."; return }
    }

    # 2) Ensure it autostarts in the user session at logon -- but only if nothing already
    #    launches it, so we don't create a second tray icon next to whatever the installer set up.
    $runKey    = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    $autostart = $false
    try {
        $rk = Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue
        if ($rk) { foreach ($p in $rk.PSObject.Properties) { if ($p.Value -like '*BMAInterface.exe*') { $autostart = $true; break } } }
    } catch {}
    if (-not $autostart) {
        try {
            $t = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { ($_.Actions.Execute -join ';') -like '*BMAInterface.exe*' }
            if ($t) { $autostart = $true }
        } catch {}
    }
    if ($autostart) {
        Write-Log "BMA Interface autostart already configured; leaving it."
    }
    else {
        New-ItemProperty -Path $runKey -Name 'BMAInterface' -Value ('"{0}"' -f $ifaceExe) -PropertyType String -Force | Out-Null
        Write-Log "Registered BMA Interface autostart (HKLM Run) so it starts in the user session at logon."
    }

    # 3) Launch now ONLY in an interactive session (a tech running the .bat). From SYSTEM/startup
    #    (session 0) a launch can't show a tray icon, so we defer to the logon autostart above.
    if (Get-Process -Name 'BMAInterface' -ErrorAction SilentlyContinue) {
        Write-Log "BMA Interface is already running."
    }
    elseif ([Environment]::UserInteractive) {
        Write-Log "Interactive session; starting BMA Interface now."
        Start-Process -FilePath $ifaceExe -WorkingDirectory $ifaceDir
    }
    else {
        Write-Log "Non-interactive (SYSTEM) session; not launching the tray app now -- it will start at user logon."
    }
}

if ($DryRun) {
    Write-Log "==== DRY RUN: no download or install will occur ===="
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($DryRun) {
        Write-Log "[DRY RUN] Not elevated. A real run would require Administrator and exit here."
    }
    else {
        Write-Log "Not running elevated on $env:COMPUTERNAME. BMA install requires Administrator. Exiting."
        exit 1
    }
}

#Pre-Install Check
if (Test-BmaRunning) {
    if ($DryRun) {
        Write-Log "[DRY RUN] BMA is already running. A real run would exit here."
    }
    else {
        Write-Log "BMA is already running on $env:COMPUTERNAME. Exiting."
        exit 0
    }
}

# 1=workstation, 2=domain controller, 3=server
$productType = (Get-CimInstance Win32_OperatingSystem).ProductType
switch ($productType) {
    1            { $apiUrl = $WorkstationApiUrl; $role = 'workstation' }
    {$_ -in 2,3} { $apiUrl = $ServerApiUrl;      $role = 'server' }
    default {
        Write-Log "Unsupported OS ProductType '$productType' on $env:COMPUTERNAME. Exiting."
        exit 2
    }
}

Write-Log "Attempting BMA $role install on $env:COMPUTERNAME (Client=$ClientNumber, Site=$BMASite)"

if ($DryRun) {
    Write-Log "[DRY RUN] Would download from $apiUrl to $fileDirectoryZip and extract to $fileDirectory."
    Write-Log "[DRY RUN] Would run BMAInstaller.exe -ClientNumber $ClientNumber -BranchNumber $BMASite -ClientPassword ***REDACTED***"
    Write-Log "[DRY RUN] Would then ensure BMA Interface is deployed to 'C:\Program Files\BankOnIT\BMA\BMA Interface' and set to autostart at logon."
    Write-Log "[DRY RUN] Complete. All checks passed; nothing was downloaded or installed."
    exit 0
}

# $installerStillRunning gates payload cleanup below: if the installer is left resident
# past the wait cap, we leave its files in place rather than yanking them mid-install.
$installerStillRunning = $false
try {
    Write-Log "Downloading BMA package from $apiUrl ..."
    try {
        Invoke-WebRequest -Uri $apiUrl -OutFile $fileDirectoryZip -TimeoutSec 300
        $zipMB = [math]::Round((Get-Item $fileDirectoryZip).Length / 1MB, 1)
        Write-Log "Download complete ($zipMB MB). Extracting to $fileDirectory ..."
        Expand-Archive   -Path $fileDirectoryZip -DestinationPath $fileDirectory -Force
        Write-Log "Extraction complete."
    }
    catch {
        Write-Log "Download/extract failed: $($_.Exception.Message). Exiting."
        exit 3
    }

    # Flatten if the archive double-nests BMAInstaller\BMAInstaller\...
    $nested = Join-Path $fileDirectory 'BMAInstaller'
    if (Test-Path $nested) {
        Move-Item -Path (Join-Path $nested '*') -Destination $fileDirectory -Force
    }

    $installerExe = Join-Path $fileDirectory 'BMAInstaller.exe'
    if (-not (Test-Path $installerExe)) {
        Write-Log "Installer not found at $installerExe after extraction. Exiting."
        exit 4
    }

    $stdoutFile = Join-Path $LogDir 'BMAInstaller_stdout.log'
    $stderrFile = Join-Path $LogDir 'BMAInstaller_stderr.log'
    Remove-Item $stdoutFile,$stderrFile -ErrorAction SilentlyContinue

    Write-Log "Launching BMAInstaller.exe (this can take several minutes; installer runs silently)..."
    try {
        $proc = Start-Process -FilePath $installerExe `
            -ArgumentList @('-ClientNumber', $ClientNumber, '-BranchNumber', "$BMASite", '-ClientPassword', $ClientPassword) `
            -WorkingDirectory $fileDirectory `
            -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    }
    catch {
        Write-Log "Installer failed to launch: $($_.Exception.Message). Exiting."
        exit 5
    }

    # Wait with a cap instead of blocking forever. Some BMA installers hand off to a
    # service and leave the launcher process resident, which makes an open-ended
    # -Wait hang even though the install has actually finished.
    $installTimeoutSec = 600
    if ($proc.WaitForExit($installTimeoutSec * 1000)) {
        Write-Log "Installer exited with code $($proc.ExitCode)"
    }
    else {
        $installerStillRunning = $true
        Write-Log "Installer still running after ${installTimeoutSec}s; proceeding to verify BMA services."
    }

    Protect-SensitiveFile $stdoutFile
    Protect-SensitiveFile $stderrFile

    if ((Test-Path $stdoutFile) -and (Get-Item $stdoutFile).Length -gt 0) {
        Get-Content $stdoutFile | ForEach-Object { Write-Log "installer> $_" }
    }
    if ((Test-Path $stderrFile) -and (Get-Item $stderrFile).Length -gt 0) {
        Get-Content $stderrFile | ForEach-Object { Write-Log "installer! $_" }
    }

    # Make sure the BMA Interface tray app is deployed (the core installer sometimes misses it).
    Confirm-BmaInterface -SourceZip (Join-Path $fileDirectory 'BMAInterface.zip')

    #Check if install Succeeded
    $maint = Get-BmaServiceStatus 'BMA Maintenance Service'
    $core  = Get-BmaServiceStatus 'BMA Service'
    if ($maint -eq 'Running' -and $core -eq 'Running') {
        Write-Log 'Startup Script Completed: BMA is Installed and Running'
        exit 0
    }
    else {
        Write-Log "Startup Script Failed: BMA Maintenance Service=$maint, BMA Service=$core"
        exit 6
    }
}
finally {
    # Remove the downloaded/extracted payload; it can contain the client password in config.
    # Skip while the installer is still resident so we don't delete files it's actively using.
    if (-not $installerStillRunning) {
        Remove-Item -Path $fileDirectory, $fileDirectoryZip -Recurse -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Log "Leaving payload in $fileDirectory because the installer is still running."
    }
}
