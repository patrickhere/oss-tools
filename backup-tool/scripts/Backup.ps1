#Requires -Version 5.1
<#
.SYNOPSIS
    BankOnIT Backup Utility
.DESCRIPTION
    Backs up Belarc report, launches Transwiz, copies Public Desktop, and captures
    network configuration. Generates restore assets for engineering handoff.
    Original script by redacted. Rewritten in PowerShell by Patrick Hart.
.PARAMETER BackupDest
    Override the backup destination path. Also accepts the BACKUP_DEST environment variable.
.EXAMPLE
    .\Backup.ps1
    .\Backup.ps1 -BackupDest "E:\Backups"
    .\Backup.ps1 -BackupDest "\\fileserver\BankOnIT\PC-Backups"
#>
param(
    [string]$BackupDest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Global trap -- catch any unhandled terminating error, log it, then show summary
trap {
    $errMsg = $_.Exception.Message
    $errLine = $_.InvocationInfo.ScriptLineNumber
    if ($script:LogPath) {
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -Path $script:LogPath -Value "[$stamp] [ERROR] Unhandled error at line ${errLine}: $errMsg" -Encoding UTF8
    }
    Write-Host ''
    Write-Host "[ERROR] Script stopped at line ${errLine}: $errMsg" -ForegroundColor Red
    if ($script:LogPath) {
        Write-Host "        Check $($script:LogPath) for details." -ForegroundColor Red
    }
    Write-Host ''
    Read-Host 'Press Enter to close'
    exit 1
}

# ---------------------------------------------------------------------------
# CONFIG -- all paths and thresholds defined here
# ---------------------------------------------------------------------------
$RootDir       = Split-Path $PSScriptRoot -Parent
$AssetsDir     = Join-Path $RootDir 'assets'
$BinDir        = Join-Path $AssetsDir 'bin'
$TxtDir        = Join-Path $AssetsDir 'txt'

$TranswizExe    = Join-Path $BinDir 'Transwiz_free.exe'
$TranswizConfig = Join-Path $BinDir 'Transwiz.config'
$BelarcInstaller = Join-Path $BinDir 'advisorinstaller.exe'
$ExcludeFile    = Join-Path $TxtDir 'backup_exclude_robocopy.txt'
$RestoreScript  = Join-Path $AssetsDir 'IGNORE.bat'
$RestoreExclude = Join-Path $TxtDir 'IGNORE.txt'

$BelarcPaths    = @(
    "$env:ProgramFiles\Belarc\BelarcAdvisor\BelarcAdvisor.exe",
    "${env:ProgramFiles(x86)}\Belarc\BelarcAdvisor\BelarcAdvisor.exe"
)
$BelarcReportPaths = @(
    # Belarc names its report files with literal parentheses: (COMPUTERNAME).html
    "$env:ProgramFiles\Belarc\BelarcAdvisor\System\tmp\($env:COMPUTERNAME).html",
    "${env:ProgramFiles(x86)}\Belarc\BelarcAdvisor\System\tmp\($env:COMPUTERNAME).html",
    "$env:ProgramData\Belarc\BelarcAdvisor\System\tmp\($env:COMPUTERNAME).html"
)

$DiskSpaceWarnMB  = 500
$BelarcPollSecs   = 90
$BelarcPollInterval = 3

# ---------------------------------------------------------------------------
# TRACKING -- populated by Write-Log, consumed by Show-Summary
# ---------------------------------------------------------------------------
$script:WarnCount  = 0
$script:ErrorCount = 0
$script:Issues     = [System.Collections.Generic.List[string]]::new()
$script:LogPath    = $null
$script:StartTime  = Get-Date

# Component run-state tracking for summary
$script:RanBelarc        = $false
$script:RanTranswiz      = $false
$script:RanPublicDesktop = $false
$script:RanIpconfig      = $false

# ---------------------------------------------------------------------------
# WRITE-LOG
# ---------------------------------------------------------------------------
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Severity = 'INFO'
    )

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = "[$stamp] [$Severity] $Message"

    switch ($Severity) {
        'WARN'  {
            Write-Host $line -ForegroundColor Yellow
            $script:WarnCount++
            $script:Issues.Add("[WARN] $Message")
        }
        'ERROR' {
            Write-Host $line -ForegroundColor Red
            $script:ErrorCount++
            $script:Issues.Add("[ERROR] $Message")
        }
        default { Write-Host $line }
    }

    if ($script:LogPath) {
        Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# READ-TOGGLE -- Y/N prompt helper
# ---------------------------------------------------------------------------
function Read-Toggle {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [bool]$Default = $true
    )
    $hint = if ($Default) { 'Y' } else { 'N' }
    while ($true) {
        Write-Host "$($Prompt)? [$hint]: " -ForegroundColor White -NoNewline
        $raw = Read-Host
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        $val = $raw.Trim().Substring(0,1).ToUpper()
        if ($val -eq 'Y') { return $true }
        if ($val -eq 'N') { return $false }
        Write-Host "  Please respond with Y or N." -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# RESOLVE-BACKUPDESTINATION -- classify and validate destination
# ---------------------------------------------------------------------------
function Resolve-BackupDestination {
    param([Parameter(Mandatory)][string]$Path)

    # Classify
    $type = if ($Path -match '^\\\\') { 'UNC' }
            elseif ($Path -match '^[A-Za-z]:') { 'Local' }
            else { 'Local' }

    # Disk space check (local only)
    if ($type -eq 'Local') {
        try {
            $drive = [System.IO.Path]::GetPathRoot($Path)
            $info  = [System.IO.DriveInfo]::new($drive)
            $freeMB = [math]::Round($info.AvailableFreeSpace / 1MB)
            if ($freeMB -lt $DiskSpaceWarnMB) {
                Write-Log "Drive $drive has only ${freeMB} MB free -- consider a different destination" -Severity WARN
            }
        } catch {
            Write-Log "Could not check disk space for ${Path}: $_" -Severity WARN
        }
    }

    # Write access test
    $dirCreated = $false
    try {
        $testFile = Join-Path $Path ('.baktest_' + [System.IO.Path]::GetRandomFileName())
        if (-not (Test-Path $Path)) {
            $null = New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop
            $dirCreated = $true
        }
        [System.IO.File]::WriteAllText($testFile, 'ok')
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    } catch {
        if ($dirCreated) { Remove-Item $Path -Force -ErrorAction SilentlyContinue }
        $msg = switch -Regex ($_.ToString()) {
            'network path|unreachable|not found' { "Cannot reach $Path -- check network connection" }
            'Access.*denied|unauthorized'         { "Access denied to $Path -- check credentials or share permissions" }
            default                               { "Cannot write to $Path -- path may be read-only or locked ($_)" }
        }
        return [pscustomobject]@{ Path=$Path; Type=$type; Valid=$false; Message=$msg }
    }

    return [pscustomobject]@{ Path=$Path; Type=$type; Valid=$true; Message='' }
}

# ---------------------------------------------------------------------------
# SHOW-SUMMARY
# ---------------------------------------------------------------------------
function Show-Summary {
    $elapsed = (Get-Date) - $script:StartTime
    $elapsedStr = '{0:mm}:{0:ss}' -f $elapsed

    $sep = '=' * 50
    Write-Host ''
    Write-Host $sep -ForegroundColor Cyan
    Write-Host '  Backup Summary' -ForegroundColor Cyan
    Write-Host $sep -ForegroundColor Cyan
    Write-Host ("  Computer  : {0}" -f $env:COMPUTERNAME)
    Write-Host ("  User      : {0}" -f $env:USERNAME)
    Write-Host ("  Backup to : {0}" -f $script:HostDir)
    Write-Host ("  Elapsed   : {0}" -f $elapsedStr)
    Write-Host ''

    $colW = 18
    Write-Host ("  {0,-$colW} {1}" -f 'Component', 'Status') -ForegroundColor White
    Write-Host ("  {0,-$colW} {1}" -f ('-' * ($colW - 1)), ('-' * 7)) -ForegroundColor DarkGray

    $components = @(
        @{ Name='Belarc';         Ran=$script:RanBelarc        },
        @{ Name='Transwiz';       Ran=$script:RanTranswiz      },
        @{ Name='Public Desktop'; Ran=$script:RanPublicDesktop },
        @{ Name='ipconfig';       Ran=$script:RanIpconfig      },
        @{ Name='Restore Assets'; Ran=$true                    }
    )
    foreach ($c in $components) {
        $status = if ($c.Ran) { 'RAN' } else { 'SKIPPED' }
        $color  = if ($c.Ran) { 'Green' } else { 'DarkGray' }
        Write-Host ('  {0,-18} ' -f $c.Name) -NoNewline
        Write-Host $status -ForegroundColor $color
    }

    Write-Host ''
    $wColor = if ($script:WarnCount -gt 0)  { 'Yellow' } else { 'Green' }
    $eColor = if ($script:ErrorCount -gt 0) { 'Red'    } else { 'Green' }
    Write-Host ("  Warnings : {0}" -f $script:WarnCount) -ForegroundColor $wColor
    Write-Host ("  Errors   : {0}" -f $script:ErrorCount) -ForegroundColor $eColor

    if ($script:Issues.Count -gt 0) {
        Write-Host ''
        Write-Host '  Issues:' -ForegroundColor White
        foreach ($issue in $script:Issues) {
            $iColor = if ($issue -match '^\[ERROR\]') { 'Red' } else { 'Yellow' }
            Write-Host ("    $issue") -ForegroundColor $iColor
        }
    }

    if ($script:ErrorCount -gt 0) {
        Write-Host ''
        Write-Host '  Investigate errors before proceeding.' -ForegroundColor Red
    }

    Write-Host $sep -ForegroundColor Cyan

    if ($script:LogPath) {
        Write-Log "Summary: $($script:WarnCount) warnings, $($script:ErrorCount) errors"
        Write-Host ''
        Write-Host "  Log saved at: $($script:LogPath)" -ForegroundColor DarkGray
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# ADMIN CHECK
# ---------------------------------------------------------------------------
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[ERROR] Administrative privileges required. Right-click Backup.bat and choose "Run as administrator".' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# BANNER
# ---------------------------------------------------------------------------
$banner = @'

  ==================================================
    ____              _     ___       ___ _____
   | __ )  __ _ _ __ | | __/ _ \ _ _|_ _|_   _|
   |  _ \ / _` | '_ \| |/ / | | | '_ \| |  | |
   | |_) | (_| | | | |   <| |_| | | | | |  | |
   |____/ \__,_|_| |_|_|\_\\___/|_| |_|___| |_|

    BankOnIT Backup Utility  --  PowerShell Edition
    patrick hart -- hartforge.dev
  ==================================================
  Computer : {0}
  Date     : {1}
  ==================================================

'@
Write-Host ($banner -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# PHASE 2: PRE-FLIGHT + DIRECTORY SETUP
# ---------------------------------------------------------------------------

# Resolve destination (3-tier: param > env var > default)
$defaultDest = Join-Path $RootDir 'Backups'
if (-not [string]::IsNullOrWhiteSpace($BackupDest)) {
    $resolvedDest = $BackupDest
} elseif (-not [string]::IsNullOrWhiteSpace($env:BACKUP_DEST)) {
    $resolvedDest = $env:BACKUP_DEST
} else {
    $resolvedDest = $defaultDest
}

Write-Host ''
Write-Host 'Backup destination:' -ForegroundColor White
Write-Host "  Current default: $resolvedDest"
Write-Host '  Override destination (leave blank to accept default): ' -NoNewline
$destInput = Read-Host
if (-not [string]::IsNullOrWhiteSpace($destInput)) {
    $resolvedDest = $destInput.Trim()
}

# Validate destination
Write-Host ''
Write-Host 'Validating destination...' -ForegroundColor DarkGray
$destResult = Resolve-BackupDestination -Path $resolvedDest
if (-not $destResult.Valid) {
    Write-Host ''
    Write-Host "[ERROR] $($destResult.Message)" -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
}

$BackupDestRoot = $resolvedDest
$script:HostDir = Join-Path $BackupDestRoot $env:COMPUTERNAME

$null = New-Item -ItemType Directory -Path $script:HostDir -Force

$script:LogPath = Join-Path $script:HostDir 'backuplog.txt'
'' | Set-Content -Path $script:LogPath -Encoding UTF8  # create/truncate

Write-Log "Backup started on $env:COMPUTERNAME"
Write-Log "Destination: $BackupDestRoot"
Write-Log "Host backup dir: $($script:HostDir)"

# ---------------------------------------------------------------------------
# PHASE 3: PROMPTS + TOGGLES
# ---------------------------------------------------------------------------
Write-Log "Current user: $env:USERNAME"

Write-Host ''
Write-Host 'Optional components (press Enter to accept default):' -ForegroundColor White
$DoBelarc        = Read-Toggle -Prompt 'Run Belarc Advisor scan'       -Default $true
$DoTranswiz      = Read-Toggle -Prompt 'Launch Transwiz'               -Default $true
$DoPublicDesktop = Read-Toggle -Prompt 'Copy Public Desktop'           -Default $true
$DoIpconfig      = Read-Toggle -Prompt 'Capture ipconfig /all'         -Default $true

Write-Log "Belarc: $(if ($DoBelarc) {'enabled'} else {'skipped'})"
Write-Log "Transwiz: $(if ($DoTranswiz) {'enabled'} else {'skipped'})"
Write-Log "Public Desktop: $(if ($DoPublicDesktop) {'enabled'} else {'skipped'})"
Write-Log "ipconfig: $(if ($DoIpconfig) {'enabled'} else {'skipped'})"

# ---------------------------------------------------------------------------
# PHASE 4a: BELARC
# ---------------------------------------------------------------------------
if ($DoBelarc) {
    Write-Host ''
    Write-Log 'Starting Belarc Advisor workflow...'

    # Find or install BelarcAdvisor.exe
    $belarcExe = $BelarcPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $belarcExe) {
        Write-Log 'BelarcAdvisor.exe not found -- attempting silent installation...'
        if (Test-Path $BelarcInstaller) {
            try {
                Start-Process -FilePath $BelarcInstaller -ArgumentList '/S' -Wait -NoNewWindow
                Write-Log 'Belarc installer completed.'
            } catch {
                Write-Log "Belarc installer failed: $_" -Severity WARN
            }
        } else {
            Write-Log "Belarc installer not found at $BelarcInstaller -- cannot install." -Severity WARN
        }
        $belarcExe = $BelarcPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if (-not $belarcExe) {
        Write-Log 'Cannot locate BelarcAdvisor.exe after install attempt.' -Severity WARN
    } else {
        Write-Log "Launching Belarc from: $belarcExe"
        Write-Host '  A browser window will open with the Belarc report -- this is expected.' -ForegroundColor DarkGray
        Write-Host '  Leave the browser open until the script continues.' -ForegroundColor DarkGray

        try {
            Start-Process -FilePath $belarcExe
        } catch {
            Write-Log "Failed to launch Belarc: $_" -Severity WARN
        }

        # Poll for report file
        Write-Log "Waiting up to ${BelarcPollSecs}s for report to appear..."
        $deadline = (Get-Date).AddSeconds($BelarcPollSecs)
        $foundReport = $null
        while ((Get-Date) -lt $deadline -and -not $foundReport) {
            $foundReport = $BelarcReportPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $foundReport) { Start-Sleep -Seconds $BelarcPollInterval }
        }

        if ($foundReport) {
            $destReport = Join-Path $script:HostDir "$env:COMPUTERNAME.html"
            Copy-Item $foundReport $destReport -Force
            Write-Log "Belarc report saved to $destReport"
            $script:RanBelarc = $true
        } else {
            Write-Log "Belarc report not found after ${BelarcPollSecs}s -- scan may still be in progress." -Severity WARN
        }
    }
} else {
    Write-Log 'Skipping Belarc per technician selection.'
}

# ---------------------------------------------------------------------------
# PHASE 4b: TRANSWIZ
# ---------------------------------------------------------------------------
if ($DoTranswiz) {
    Write-Host ''
    Write-Log 'Launching Transwiz...'

    if (-not (Test-Path $TranswizExe)) {
        Write-Log "Transwiz executable not found at $TranswizExe" -Severity ERROR
    } else {
        try {
            $proc = Start-Process -FilePath $TranswizExe -PassThru
            # 30 minute timeout -- Transwiz is interactive but should not block indefinitely
            $finished = $proc.WaitForExit(1800000)
            if ($finished) { $proc.WaitForExit() }  # flush async event handling so ExitCode is reliable
            if (-not $finished) {
                Write-Log 'Transwiz did not exit within 30 minutes -- continuing anyway.' -Severity WARN
            } elseif ($proc.ExitCode -ne 0) {
                Write-Log "Transwiz exited with code $($proc.ExitCode)" -Severity WARN
            } else {
                Write-Log 'Transwiz completed.'
                $script:RanTranswiz = $true
            }
        } catch {
            Write-Log "Transwiz failed to launch: $_" -Severity ERROR
        }
    }
} else {
    Write-Log 'Skipping Transwiz per technician selection.'
}

# ---------------------------------------------------------------------------
# PHASE 4c: IPCONFIG
# ---------------------------------------------------------------------------
if ($DoIpconfig) {
    Write-Host ''
    Write-Log 'Capturing network configuration...'
    try {
        $ipconfigOut = Join-Path $script:HostDir 'ipconfig.txt'
        ipconfig /all | Out-File -FilePath $ipconfigOut -Encoding UTF8
        Write-Log "ipconfig saved to $ipconfigOut"
        $script:RanIpconfig = $true
    } catch {
        Write-Log "ipconfig capture failed: $_" -Severity ERROR
    }
} else {
    Write-Log 'Skipping ipconfig per technician selection.'
}

# ---------------------------------------------------------------------------
# PHASE 4d: PUBLIC DESKTOP (robocopy)
# ---------------------------------------------------------------------------
if ($DoPublicDesktop) {
    Write-Host ''
    Write-Log 'Copying Public Desktop...'

    $pubSrc = "$env:SystemDrive\Users\Public\Desktop"
    $pubDst = Join-Path $script:HostDir 'Public\Desktop'
    $null = New-Item -ItemType Directory -Path $pubDst -Force

    if (-not (Test-Path $pubSrc)) {
        Write-Log "Public Desktop not found at $pubSrc" -Severity WARN
    } else {
        # Parse robocopy exclude file
        $xdArgs = [System.Collections.Generic.List[string]]::new()
        $xfArgs = [System.Collections.Generic.List[string]]::new()

        if (Test-Path $ExcludeFile) {
            Get-Content $ExcludeFile |
                Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } |
                ForEach-Object {
                    if ($_ -match '^DIR:(.+)')  { $xdArgs.Add($Matches[1].Trim()) }
                    elseif ($_ -match '^FILE:(.+)') { $xfArgs.Add($Matches[1].Trim()) }
                }
        } else {
            Write-Log "Robocopy exclude file not found at $ExcludeFile -- copying without exclusions." -Severity WARN
        }

        $roboArgs = @($pubSrc, $pubDst, '/E', '/R:1', '/W:1', '/NP')
        if ($xdArgs.Count -gt 0) { $roboArgs += '/XD'; $roboArgs += $xdArgs.ToArray() }
        if ($xfArgs.Count -gt 0) { $roboArgs += '/XF'; $roboArgs += $xfArgs.ToArray() }

        # Temporarily allow non-terminating errors so robocopy stderr output
        # does not trigger $ErrorActionPreference = 'Stop' before we check $LASTEXITCODE
        $savedEAP = $ErrorActionPreference
        $robocopyExit = 0
        $roboOutput   = $null
        try {
            $ErrorActionPreference = 'Continue'
            $roboOutput   = & robocopy @roboArgs 2>&1
            $robocopyExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedEAP
        }

        if ($robocopyExit -ge 8) {
            Write-Log "robocopy failed with exit code $robocopyExit -- $($roboOutput -join ' | ')" -Severity ERROR
        } else {
            Write-Log "Public Desktop copied (robocopy exit $robocopyExit)"
            $script:RanPublicDesktop = $true
        }
    }
} else {
    Write-Log 'Skipping Public Desktop per technician selection.'
}

# ---------------------------------------------------------------------------
# PHASE 5: RESTORE ASSETS
# ---------------------------------------------------------------------------
Write-Host ''
Write-Log 'Staging restore assets...'

# Restore batch
if (Test-Path $RestoreScript) {
    Copy-Item $RestoreScript (Join-Path $script:HostDir 'Restore (run as admin).bat') -Force
} else {
    Write-Log "Restore script template not found at $RestoreScript" -Severity WARN
}

# Restore exclude list
$restoreExcludeDest = Join-Path $script:HostDir 'restore_exclude.txt'
if (Test-Path $RestoreExclude) {
    # Re-encode to UTF8 on write to ensure consistent encoding before appending
    $templateContent = Get-Content $RestoreExclude -Raw
    Set-Content -Path $restoreExcludeDest -Value $templateContent -Encoding UTF8
} else {
    Write-Log "Restore exclude template not found at $RestoreExclude -- creating empty file." -Severity WARN
    Set-Content -Path $restoreExcludeDest -Value '' -Encoding UTF8
}

# Do Not Restore directory
$null = New-Item -ItemType Directory -Path (Join-Path $script:HostDir 'Do Not Restore') -Force

# Transwiz binaries (only if Transwiz was run)
if ($DoTranswiz) {
    if (Test-Path $TranswizExe) {
        Copy-Item $TranswizExe (Join-Path $script:HostDir 'Transwiz.exe') -Force
    } else {
        Write-Log "Transwiz_free.exe not found -- cannot copy to backup folder." -Severity WARN
    }
    if (Test-Path $TranswizConfig) {
        Copy-Item $TranswizConfig (Join-Path $script:HostDir 'Transwiz.config') -Force
    } else {
        Write-Log "Transwiz.config not found -- restore may require manual config." -Severity WARN
    }
}

Write-Log "Restore assets staged at $($script:HostDir)"
Write-Log "Use restore_exclude.txt or the 'Do Not Restore' folder to omit items from restore."

# ---------------------------------------------------------------------------
# PHASE 6: SUMMARY
# ---------------------------------------------------------------------------
Show-Summary

Write-Host 'Backup complete.' -ForegroundColor Green
Write-Host ''
Read-Host 'Press Enter to close'
