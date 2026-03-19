You are reviewing a collection of PowerShell and batch scripts used by an MSP technician on bank client machines (Windows 10/11, PowerShell 5.1). Review all scripts below for:

1. Bugs -- logic errors, incorrect assumptions, things that will silently fail or crash
2. PowerShell 5.1 compatibility issues (no PS7 features)
3. Edge cases that aren't handled -- missing paths, permissions, unexpected states
4. Recommendations -- missing error handling, things that should be added, better approaches
5. Anything that could cause harm on a production bank machine (unintended side effects, data loss risk, etc.)

For each finding include: file path, severity (BUG / WARN / REC), and a concrete fix or suggestion.

---

=== backup-tool/Backup.bat ===

=== backup-tool/Backup.bat ===
@echo off
REM Wrapper to call the main backup script in scripts\Backup.bat
REM See README.md in this folder for usage and scenarios.
REM Check for admin and self-elevate if needed
>nul 2>&1 net session
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    if "%~1"=="" (
        powershell -NoProfile -ExecutionPolicy Bypass ^
            -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass ^
            -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\Backup.ps1" %*
=== backup-tool/scripts/Backup.ps1 ===
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

        # Poll for report file -- search known fixed paths first, then fall back to
        # a recursive scan under Belarc's install dirs (handles path changes across versions)
        $belarcSearchRoots = @(
            "$env:ProgramFiles\Belarc",
            "${env:ProgramFiles(x86)}\Belarc",
            "$env:ProgramData\Belarc"
        )
        Write-Log "Waiting up to ${BelarcPollSecs}s for report to appear..."
        $deadline = (Get-Date).AddSeconds($BelarcPollSecs)
        $foundReport = $null
        while ((Get-Date) -lt $deadline -and -not $foundReport) {
            # Try fixed known paths first (fast)
            $foundReport = $BelarcReportPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            # Fall back: any .html recently written under Belarc dirs
            if (-not $foundReport) {
                $cutoff = $script:StartTime
                $foundReport = $belarcSearchRoots |
                    Where-Object { Test-Path $_ } |
                    ForEach-Object { Get-ChildItem -Path $_ -Recurse -Filter '*.html' -ErrorAction SilentlyContinue } |
                    Where-Object { $_.LastWriteTime -gt $cutoff } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1 -ExpandProperty FullName
            }
            if (-not $foundReport) { Start-Sleep -Seconds $BelarcPollInterval }
        }

        if ($foundReport) {
            $destReport = Join-Path $script:HostDir "$env:COMPUTERNAME.html"
            Copy-Item $foundReport $destReport -Force
            Write-Log "Belarc report found at: $foundReport"
            Write-Log "Belarc report saved to: $destReport"
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

=== backup-tool/scripts/Backup_Hirens.bat ===
@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Author: redacted
REM Contact: redacted@example.com
REM Last Updated: 10/20/2020 (layout and logging updated 11/21/2025)
REM This script is for the sole use of BankOnIT employees.

echo Setting variables and changing directory to Backups folder...
for /f "delims=" %%A in ('hostname') do set "hostname=%%A"

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%SCRIPT_DIR%..\"
set "ASSETS_DIR=%ROOT_DIR%assets\"
set "BIN_DIR=%ASSETS_DIR%bin\"
set "TXT_DIR=%ASSETS_DIR%txt\"

pushd "%ROOT_DIR%" >nul 2>&1 || (
    echo [ERROR] Unable to access root directory: %ROOT_DIR%
    pause
    goto end
)

if not exist "Backups" mkdir "Backups"
pushd "Backups" >nul 2>&1 || (
    echo [ERROR] Unable to access Backups directory.
    pause
    goto end
)

if not exist "%hostname%" mkdir "%hostname%"
set "LOG_PATH=%CD%\%hostname%\backuplog.txt"
> "%LOG_PATH%" echo Backup (Hirens) started %date% %time%
call :log "Hostname detected as %hostname%"
cls

echo Please specify the drive where Windows is. This is usually C.
echo If nothing is specified, C drive will be selected.
set /p drive="Drive (e.g. C): "
IF "%drive%"=="" set drive=C
call :log "Windows drive selected: %drive%"
echo.
:userselection
echo Please input user to back up.
set /p user="User:"

IF "%user%"=="" goto nouser

:belarc
call :log "Preparing Belarc Advisor assets..."
if not exist "%SYSTEMDRIVE%\BankOnIT" mkdir "%SYSTEMDRIVE%\BankOnIT"
if exist "%SYSTEMDRIVE%\BankOnIT\Belarc Advisor" (
    call :log "Belarc Advisor already installed under %SYSTEMDRIVE%\BankOnIT\Belarc Advisor"
) else (
    call :log "Belarc Advisor not found. Deploying installer from %BIN_DIR%advisorinstaller.exe"
    mkdir "%SYSTEMDRIVE%\BankOnIT\Belarc Advisor" 2>nul
    if exist "%BIN_DIR%advisorinstaller.exe" (
        copy "%BIN_DIR%advisorinstaller.exe" "%SYSTEMDRIVE%\BankOnIT\Belarc Advisor\" >nul
    ) else (
        call :log "WARNING: Belarc advisorinstaller.exe missing at %BIN_DIR%advisorinstaller.exe"
    )
    if exist "%BIN_DIR%Start_Belarc_Hirens.ps1" (
        powershell -ExecutionPolicy Bypass -File "%BIN_DIR%Start_Belarc_Hirens.ps1" >> "%LOG_PATH" 2>&1
    ) else (
        call :log "WARNING: Start_Belarc_Hirens.ps1 missing at %BIN_DIR%Start_Belarc_Hirens.ps1"
    )
)

call :log "Attempting to copy Belarc report HTML..."
if exist "%PROGRAMFILES%\Belarc\BelarcAdvisor\System\tmp\(%hostname%).html" (
    copy "%PROGRAMFILES%\Belarc\BelarcAdvisor\System\tmp\(%hostname%).html" "%hostname%\%hostname%.html" >nul
    call :log "Belarc report copied from Program Files."
)
if exist "%PROGRAMFILES(X86)%\Belarc\BelarcAdvisor\System\tmp\(%hostname%).html" (
    copy "%PROGRAMFILES(X86)%\Belarc\BelarcAdvisor\System\tmp\(%hostname%).html" "%hostname%\%hostname%.html" >nul
    call :log "Belarc report copied from Program Files (x86)."
)

REM choice /M "Skip backing up anything on local drive? This is useful when the local drive is unreadable."
REM set skipdrive=%ERRORLEVEL%

REM if skipdrive EQU 1 goto backup
REM if skipdrive EQU 2 goto ipconfig

:backup
REM echo Copying user office information (Outlook signatures, etc)...
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Microsoft\Office\*.*" "%hostname%\%user%\AppData\Roaming\Microsoft\Office\" /C /E /I /Y >> "%hostname%\backuplog.txt"
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Microsoft\Signatures\*.*" "%hostname%\%user%\AppData\Roaming\Microsoft\Signatures\" /C /E /I /Y >> "%hostname%\backuplog.txt"
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Microsoft\Outlook\*.*" "%hostname%\%user%\AppData\Roaming\Microsoft\Outlook\" /C /E /I /Y >> "%hostname%\backuplog.txt"
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Microsoft\Templates\*.*" "%hostname%\%user%\AppData\Roaming\Microsoft\Templates\" /C /E /I /Y >> "%hostname%\backuplog.txt"
REM xcopy "%drive%:\Users\%user%\AppData\Local\Microsoft\Outlook\*.*" "%hostname%\%user%\AppData\Local\Microsoft\Outlook\" /C /E /I /Y >> "%hostname%\backuplog.txt"

REM echo Copying user FireFox Profile...
REM xcopy "%drive%:\Users\%user%\AppData\Roaming\Mozilla\Firefox\Profiles\*.*" "%hostname%\%user%\AppData\Roaming\Mozilla\Firefox\Profiles" /C /E /I /Y >> "%hostname%\backuplog.txt"

REM echo Copying user Chrome Information...
REM xcopy "%drive%:\Users\%user%\AppData\Local\Google\Chrome\*.*" "%hostname%\%user%\AppData\Local\Google\Chrome\" /C /E /I /Y /EXCLUDE:%~dp0\backup_exclude_chrome.txt >> "%hostname%\backuplog.txt"

echo Copying Public Desktop...
call :log "Copying Public Desktop from %drive%: to backup."
if exist "%TXT_DIR%backup_exclude.txt" (
    xcopy "%drive%:\Users\Public\Desktop\*.*" "%hostname%\Public\Desktop" /C /E /I /Y /EXCLUDE:"%TXT_DIR%backup_exclude.txt" >> "%LOG_PATH%" 2>&1
) else (
    call :log "WARNING: backup_exclude.txt missing at %TXT_DIR%backup_exclude.txt. Copying without exclusions."
    xcopy "%drive%:\Users\Public\Desktop\*.*" "%hostname%\Public\Desktop" /C /E /I /Y >> "%LOG_PATH%" 2>&1
)

echo Starting Transwiz...
call :log "Launching Transwiz from %BIN_DIR%Transwiz_free.exe"
if exist "%BIN_DIR%Transwiz_free.exe" (
    "%BIN_DIR%Transwiz_free.exe" >> "%LOG_PATH%" 2>&1
) else (
    call :log "ERROR: Transwiz_free.exe missing at %BIN_DIR%Transwiz_free.exe"
)

:ipconfig
echo Running ipconfig /all and saving output to ipconfig.txt...
call :log "Capturing ipconfig /all output..."
ipconfig /all > "%hostname%\ipconfig.txt"

echo.

echo Please input the old name of the computer.
echo NOTE: This is only for identification purposes. Hirens names the computer a random name so it might be hard to identify which computer this backup came from.
echo This is not mandatory however. If you would like to keep the hostname the one Hirens assigned, just leave the field blank.
echo WARNING: If you are running the script twice to backup more than 1 profile, leave the name the same until the last profile is backed up!
echo.
set oldhostname=%hostname%
set /p hostname="Hostname of Old Computer:"
IF "%hostname%"=="" for /f "delims=" %%A in ('hostname') do set "hostname=%%A"
echo Old Hostname: %oldhostname%
echo New Hostname: %hostname%
rename %oldhostname% %hostname%
rename "%hostname%\%oldhostname%.html" "%hostname%.html"

echo.
echo Copying Restore batch files...
if exist "%ASSETS_DIR%IGNORE.bat" (
    copy "%ASSETS_DIR%IGNORE.bat" "%hostname%\Restore (run as admin).bat" >nul
) else (
    call :log "WARNING: IGNORE.bat (restore template) missing at %ASSETS_DIR%IGNORE.bat"
)

if exist "%TXT_DIR%IGNORE.txt" (
    copy "%TXT_DIR%IGNORE.txt" "%hostname%\restore_exclude.txt" >nul
) else (
    call :log "WARNING: IGNORE.txt (restore_exclude template) missing at %TXT_DIR%IGNORE.txt"
    type nul > "%hostname%\restore_exclude.txt"
)
echo %user%.trans.zip>> "%hostname%\restore_exclude.txt"
mkdir "%hostname%\Do Not Restore" 2>nul
echo Copying Transwiz.exe...
if exist "%BIN_DIR%Transwiz_free.exe" (
    copy "%BIN_DIR%Transwiz_free.exe" "%hostname%\Transwiz.exe" >nul
) else (
    call :log "WARNING: Transwiz_free.exe missing; cannot copy to backup folder."
)

call :log "Backup (Hirens) completed for user %user% on hostname %hostname%"
echo Backup completed. Log is saved at: Backups\%hostname%\backuplog.txt
echo Use %hostname%\restore_exclude.txt to specify files/folders that you do not want restored automatically.
echo e.g you copied a program folder into the backup directory that this script uses.
echo You can also put them into the Do Not Restore directory as well.

:end
pause
endlocal
exit /b 0

:nouser
echo No user specified. Please input a user and try again.
pause
cls
goto userselection

:nodrive
echo.
exit /b 0

:log
set "MESSAGE=%~1"
set "STAMP=%date% %time%"
echo [%STAMP%] %MESSAGE%
>> "%LOG_PATH%" echo [%STAMP%] %MESSAGE%
exit /b 0
=== backup-tool/assets/IGNORE.bat ===
@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Author: redacted
REM Contact: redacted@example.com
REM Last Updated: 8/17/2020
REM This script is for the sole use of BankOnIT employees.

call :ensureAdmin || goto end

:variables
echo Setting variables...
for /f "delims=" %%A in ('hostname') do set "hostname=%%A"
pushd "%~dp0"
for %%I in (.) do set old=%%~nxI

:newcomputer
echo Creating New_Computer.txt...
echo %hostname% > New_Computer.txt

:backup
echo Creating backup of Public Desktop folder (%old%\Backup (New Computer)\Public\Desktop)
mkdir "Backup (New Computer)"
xcopy "%SYSTEMDRIVE%\Users\Public\Desktop\*.*" "Backup (New Computer)\Public\Desktop" /C /E /I /Y

:profile
echo Restoring User Profiles back to system...
echo Running Transwiz.exe
Transwiz.exe
if not exist Logs mkdir Logs
xcopy *.* "%SYSTEMDRIVE%\Users" /C /E /I /Y /EXCLUDE:restore_exclude.txt >> Logs\restorelog.txt
copy Logs\restorelog.txt %SYSTEMDRIVE%\BankOnIT\restorelog.txt

REM echo Now getting moving outlook profile for one user to Documents\Outlook Files.
REM echo If this doesn't need to be done, or no one has outlook, just press enter.
REM set /p user="User:"
REM IF "%user%"=="" (goto cleanup) ELSE (goto outlook)
:outlook
REM echo Moving Outlook Data file (if present) to %SYSTEMDRIVE%\Users\%user%.old\Documents...
REM IF EXIST "%SYSTEMDRIVE%\Users\%user%.old\AppData\Local\Outlook" THEN move "%SYSTEMDRIVE%\Users\%user%.old\AppData\Local\Outlook\*.*" "%SYSTEMDRIVE%\Users\%user%.old\Documents\Outlook Files" ELSE echo No Outlook files were found.
REM IF EXIST "%SYSTEMDRIVE%\Users\%user%.old\Documents\Outlook Files\" THEN echo Remember to re-import the PST file after you have run through Outlook setup. (Or just replace it in %LOCALAPPDATA%\Microsoft\Outlook) && timeout /T 5

:cleanup
echo "Moving Old Computer info to %SYSTEMDRIVE%\BankOnIT\Old Computer..."
pushd %SYSTEMDRIVE%\Users
mkdir "%SYSTEMDRIVE%\BankOnIT\Old Computer"

move "%old%.html" "%SYSTEMDRIVE%\BankOnIT\Old Computer\"
move PrinterList.txt "%SYSTEMDRIVE%\BankOnIT\Old Computer\"
move ipconfig.txt "%SYSTEMDRIVE%\BankOnIT\Old Computer\"

echo Restore completed. Restore log is located at %SYSTEMDRIVE%\BankOnIT\restorelog.txt
echo Old Computer info (Belarc Advisor) is located at %SYSTEMDRIVE%\BankOnIT\Old Computer\%old%.html
echo If mapped drives did not copy over, double-click the registry file MappedDrives.reg in the user's folder. Otherwise, this batch file will move it to the %SYSTEMDRIVE%\BankOnIT\Old Computer folder once you press enter.
pause
move "%user%\MappedDrives.reg" "%SYSTEMDRIVE%\BankOnIT\Old Computer\"
goto end

:ensureAdmin
  fsutil dirty query %systemdrive% >nul 2>&1
  if %errorlevel%==0 (
    echo Running as admin...
  ) else (
    echo Running as non-admin...
    echo Please run as admin...
    pause
    exit /b 1
  )
  exit /b 0

:end
=== backup-tool/assets/bin/Start_Belarc.ps1 ===
Start-Process -FilePath "C:\BankOnIT\Belarc Advisor\advisorinstaller.exe" -Wait -ArgumentList '/S'
=== config/disable-ms-account-signin/config.ps1 ===
# config.ps1
# Blocks personal Microsoft account sign-in prompts in Office

Write-Host "  BankOnIT OSS | Disable MS Account Sign-in" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

try {
    $path = "HKLM:\Software\Policies\Microsoft\MicrosoftAccount"

    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "DisableUserAuth" -Value 1 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: Personal Microsoft account sign-in blocked." -ForegroundColor Green
    Write-Host "Office will no longer prompt users to sign in with personal accounts."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== config/disable-onedrive-autoinstall/config.ps1 ===
# config.ps1
# Disables consumer OneDrive auto-install and removes it from the startup run key

Write-Host "  BankOnIT OSS | Disable OneDrive Auto-Install" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

try {
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"

    if (!(Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }

    Set-ItemProperty -Path $policyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord
    Write-Host ""
    Write-Host "INFO: OneDrive file sync policy applied." -ForegroundColor Yellow

    # Remove OneDrive from the machine-wide startup run key if present
    $runPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $runProp = Get-ItemProperty -Path $runPath -Name "OneDrive" -ErrorAction SilentlyContinue
    if ($runProp) {
        Remove-ItemProperty -Path $runPath -Name "OneDrive" -Force
        Write-Host "INFO: OneDrive removed from startup run key." -ForegroundColor Yellow
    }
    else {
        Write-Host "INFO: OneDrive not present in startup run key (nothing to remove)." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "SUCCESS: OneDrive auto-install suppressed." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== config/disable-teams-autoinstall/config.ps1 ===
# config.ps1
# Prevents consumer Teams from auto-installing and launching on first logon

Write-Host "  BankOnIT OSS | Disable Teams Auto-Install" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

try {
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Teams"
    $teamsPath  = "HKLM:\SOFTWARE\Microsoft\Teams"

    foreach ($path in @($policyPath, $teamsPath)) {
        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }

    Set-ItemProperty -Path $policyPath -Name "PreventFirstLaunchAfterLogon" -Value 1 -Type DWord
    Set-ItemProperty -Path $policyPath -Name "PreventInstallationFromMsi"   -Value 1 -Type DWord
    Set-ItemProperty -Path $teamsPath  -Name "PreventFirstLaunchAfterLogon" -Value 1 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: Teams auto-install and first-launch suppressed." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== config/disable-update-autoreboot/config.ps1 ===
# config.ps1
# Prevents Windows Update from auto-rebooting when users are logged in

Write-Host "  BankOnIT OSS | Disable Update Auto-Reboot" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

try {
    $auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    if (!(Test-Path $auPath)) {
        New-Item -Path $auPath -Force | Out-Null
    }

    # Do not reboot while a user is logged in
    Set-ItemProperty -Path $auPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord
    # Auto-download but notify before installing (lets IT control timing)
    Set-ItemProperty -Path $auPath -Name "AUOptions" -Value 3 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: Windows Update auto-reboot suppressed." -ForegroundColor Green
    Write-Host "Updates will download automatically but will not install or reboot while users are logged in."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== config/edge-ie-mode-sites/config.ps1 ===
# config.ps1
# Enables IE mode in Edge and manages a local site list

Write-Host "  BankOnIT OSS | Edge IE Mode Sites" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

$siteListPath = "C:\ProgramData\BankOnIT\ie-sites.xml"
$policyPath   = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

# Ensure Edge IE mode policy is enabled
try {
    if (!(Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $policyPath -Name "InternetExplorerIntegrationLevel" -Value 1 -Type DWord
    Set-ItemProperty -Path $policyPath -Name "InternetExplorerIntegrationSiteList" -Value $siteListPath -Type String
}
catch {
    Write-Host ""
    Write-Host "ERROR: Failed to set Edge policy: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

# Load existing site list or create empty one
function Get-SiteList {
    if (Test-Path $siteListPath) {
        try {
            return [xml](Get-Content $siteListPath)
        }
        catch { }
    }
    $xml = [xml]'<site-list version="1"><created></created></site-list>'
    $xml."site-list".created = (Get-Date -Format "yyyy-MM-dd")
    return $xml
}

function Save-SiteList($xml) {
    $dir = Split-Path $siteListPath
    if (!(Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    # Increment version so Edge reloads it
    $ver = [int]$xml."site-list".version + 1
    $xml."site-list".version = "$ver"
    $xml.Save($siteListPath)
}

function Show-Sites($xml) {
    $sites = $xml."site-list".site
    if (!$sites) {
        Write-Host "  (no sites configured)" -ForegroundColor Yellow
        return
    }
    $i = 1
    foreach ($s in $sites) {
        Write-Host "  $i. $($s.url)"
        $i++
    }
}

# Interactive site list manager
while ($true) {
    $xml = Get-SiteList

    Write-Host ""
    Write-Host "IE mode site list  ($siteListPath):" -ForegroundColor Yellow
    Show-Sites $xml
    Write-Host ""
    Write-Host "  A. add site"
    Write-Host "  R. remove site"
    Write-Host "  Q. save and quit"
    Write-Host ""
    $action = Read-Host "select"

    if ($action -match '^[Qq]$') {
        break
    }
    elseif ($action -match '^[Aa]$') {
        $url = Read-Host "enter url (e.g. legacy.client.com)"
        $url = $url.Trim()
        if ($url) {
            $existing = $xml."site-list".site | Where-Object { $_.url -eq $url }
            if ($existing) {
                Write-Host "INFO: $url is already in the list." -ForegroundColor Yellow
            }
            else {
                $node = $xml.CreateElement("site")
                $node.SetAttribute("url", $url)
                $compat = $xml.CreateElement("compat-mode")
                $compat.InnerText = "IE11"
                $openIn = $xml.CreateElement("open-in")
                $openIn.InnerText = "IE11"
                $node.AppendChild($compat) | Out-Null
                $node.AppendChild($openIn) | Out-Null
                $xml."site-list".AppendChild($node) | Out-Null
                Save-SiteList $xml
                Write-Host "INFO: $url added." -ForegroundColor Green
            }
        }
    }
    elseif ($action -match '^[Rr]$') {
        $sites = @($xml."site-list".site)
        if (!$sites) {
            Write-Host "INFO: No sites to remove." -ForegroundColor Yellow
            continue
        }
        $idx = Read-Host "enter number to remove"
        if ($idx -match '^\d+$') {
            $i = [int]$idx - 1
            if ($i -ge 0 -and $i -lt $sites.Count) {
                $xml."site-list".RemoveChild($sites[$i]) | Out-Null
                Save-SiteList $xml
                Write-Host "INFO: Site removed." -ForegroundColor Green
            }
            else {
                Write-Host "ERROR: Invalid selection." -ForegroundColor Red
            }
        }
    }
}

Write-Host ""
Write-Host "SUCCESS: IE mode enabled. Site list saved to $siteListPath" -ForegroundColor Green
Write-Host "Edge will load the updated site list on next launch."
Write-Host ""
Read-Host "Press Enter to close"

=== diag/event-log-errors/diag.ps1 ===
# diag.ps1
# Pulls the last 100 Application and System errors from the past 24 hours and saves to desktop

param([string]$ClientName = "")

Write-Host "  BankOnIT OSS | Event Log Errors" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

try {
    $since  = (Get-Date).AddHours(-24)
    $output = [System.Collections.Generic.List[string]]::new()

    $output.Add("BankOnIT OSS | Event Log Errors (last 24h)")
    $output.Add("patrick hart - hartforge.dev")
    $output.Add("Generated: $(Get-Date)")
    $output.Add("Machine: $env:COMPUTERNAME")
    $output.Add("")

    foreach ($log in @("Application", "System")) {
        Write-Host ""
        Write-Host "INFO: Querying $log log..." -ForegroundColor Yellow

        $events = Get-WinEvent -FilterHashtable @{
            LogName   = $log
            Level     = 2       # Error
            StartTime = $since
        } -MaxEvents 50 -ErrorAction SilentlyContinue |
            Sort-Object TimeCreated -Descending

        $output.Add("=== $log ===")

        if (!$events) {
            $output.Add("  no errors in the past 24 hours")
        }
        else {
            Write-Host "  $($events.Count) error(s) found." -ForegroundColor Yellow
            foreach ($e in $events) {
                $output.Add("[$($e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))] ID:$($e.Id) | $($e.ProviderName)")
                $output.Add("  $($e.Message -replace '\r?\n',' ' -replace '\s+',' ')")
                $output.Add("")
            }
        }

        $output.Add("")
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $slug      = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { "" }
    $desktop   = [Environment]::GetFolderPath("Desktop")
    $outFile   = "$desktop\OSS-eventlog$slug-$timestamp.txt"

    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Event log errors saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== diag/exchange-connectivity/diag.ps1 ===
# diag.ps1
# Tests Exchange/M365 connectivity based on the selected environment

param([string]$Environment = "onprem", [string]$ClientName = "")

Write-Host "  BankOnIT OSS | Exchange Connectivity" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  environment: $Environment" -ForegroundColor DarkGray

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $output    = [System.Collections.Generic.List[string]]::new()

    $output.Add("BankOnIT OSS | Exchange Connectivity")
    $output.Add("patrick hart - hartforge.dev")
    $output.Add("Generated: $(Get-Date)")
    $output.Add("Environment: $Environment")
    $output.Add("")

    function Test-Port {
        param([string]$Host, [int]$Port)
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $conn = $tcp.BeginConnect($Host, $Port, $null, $null)
            $wait = $conn.AsyncWaitHandle.WaitOne(3000, $false)
            if ($wait -and !$tcp.Client.Connected) { return $false }
            $tcp.EndConnect($conn)
            $tcp.Close()
            return $wait
        }
        catch { return $false }
    }

    function Write-Result {
        param([string]$Label, [bool]$OK, [string]$Detail = "")
        $status = if ($OK) { "OK  " } else { "FAIL" }
        $color  = if ($OK) { "Green" } else { "Red" }
        $line   = "  [$status] $Label"
        if ($Detail) { $line += " -- $Detail" }
        Write-Host $line -ForegroundColor $color
        return $line
    }

    # On-prem checks
    if ($Environment -eq "onprem" -or $Environment -eq "hybrid") {
        $output.Add("=== On-Premises ===")
        Write-Host ""
        Write-Host "on-premises checks:" -ForegroundColor Yellow

        # DC reachability via nltest
        $nltest = nltest /dsgetdc: 2>&1
        $dcOk   = ($LASTEXITCODE -eq 0)
        $dcName = if ($dcOk) { ($nltest | Select-String "DC:").ToString().Trim() } else { "unreachable" }
        $output.Add((Write-Result "Domain Controller" $dcOk $dcName))

        # Autodiscover DNS
        $domain = $env:USERDNSDOMAIN
        if ($domain) {
            try {
                $adDns = [System.Net.Dns]::GetHostAddresses("autodiscover.$domain")
                $output.Add((Write-Result "autodiscover.$domain DNS" $true $adDns[0].IPAddressToString))
            }
            catch {
                $output.Add((Write-Result "autodiscover.$domain DNS" $false "no DNS record"))
            }
        }
        else {
            $output.Add((Write-Result "Autodiscover DNS" $false "USERDNSDOMAIN not set"))
        }

        $output.Add("")
    }

    # M365 checks
    if ($Environment -eq "m365" -or $Environment -eq "hybrid") {
        $output.Add("=== Microsoft 365 ===")
        Write-Host ""
        Write-Host "microsoft 365 checks:" -ForegroundColor Yellow

        $m365Endpoints = @(
            @{ Host = "outlook.office365.com"; Port = 443 },
            @{ Host = "login.microsoftonline.com"; Port = 443 },
            @{ Host = "graph.microsoft.com"; Port = 443 },
            @{ Host = "autodiscover-s.outlook.com"; Port = 443 }
        )

        foreach ($ep in $m365Endpoints) {
            $ok = Test-Port $ep.Host $ep.Port
            $output.Add((Write-Result "$($ep.Host):$($ep.Port)" $ok))
        }

        $output.Add("")
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    $slug    = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { "" }
    $outFile = "$desktop\OSS-connectivity$slug-$timestamp.txt"
    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Results saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== diag/network-info/diag.ps1 ===
# diag.ps1
# Dumps active network adapter info in a readable format and saves to desktop

param([string]$ClientName = "")

Write-Host "  BankOnIT OSS | Network Info" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

try {
    $output = [System.Collections.Generic.List[string]]::new()

    $output.Add("BankOnIT OSS | Network Info")
    $output.Add("patrick hart - hartforge.dev")
    $output.Add("Generated: $(Get-Date)")
    $output.Add("Machine: $env:COMPUTERNAME")
    $output.Add("")

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object InterfaceIndex

    if (!$adapters) {
        $output.Add("no active network adapters found")
    }

    foreach ($adapter in $adapters) {
        $output.Add("=== $($adapter.Name) ($($adapter.InterfaceDescription)) ===")
        $output.Add("  MAC:    $($adapter.MacAddress)")
        $output.Add("  Speed:  $([math]::Round($adapter.LinkSpeed / 1MB)) Mbps")

        $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue

        $ipv4 = $ipConfig.IPv4Address
        if ($ipv4) {
            $output.Add("  IP:     $($ipv4.IPAddress) / $($ipv4.PrefixLength)")
        }

        $gw = $ipConfig.IPv4DefaultGateway
        if ($gw) {
            $output.Add("  GW:     $($gw.NextHop)")
        }

        $dns = $ipConfig.DNSServer | Where-Object { $_.AddressFamily -eq 2 }
        if ($dns) {
            $output.Add("  DNS:    $($dns.ServerAddresses -join ', ')")
        }

        # DHCP info
        $dhcp = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($dhcp) {
            $isDhcp = ($dhcp.PrefixOrigin -eq "Dhcp")
            $output.Add("  DHCP:   $(if ($isDhcp) { 'yes' } else { 'no (static)' })")

            if ($isDhcp) {
                $dhcpDetail = Get-DhcpServerInDC -ErrorAction SilentlyContinue
                $netInfo = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 |
                    Select-Object -First 1
                if ($netInfo.ValidLifetime) {
                    $expires = (Get-Date).Add($netInfo.ValidLifetime)
                    $output.Add("  Lease:  expires $($expires.ToString('yyyy-MM-dd HH:mm'))")
                }
            }
        }

        $output.Add("")
    }

    # Also show the DNS suffix search list
    $suffixes = (Get-DnsClient | Select-Object -First 1).ConnectionSpecificSuffix
    $globalSuffixes = (Get-DnsClientGlobalSetting).SuffixSearchList
    if ($globalSuffixes) {
        $output.Add("DNS search suffixes: $($globalSuffixes -join ', ')")
        $output.Add("")
    }

    # Print everything to screen too
    $output | ForEach-Object { Write-Host $_ }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $slug      = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { "" }
    $desktop   = [Environment]::GetFolderPath("Desktop")
    $outFile   = "$desktop\OSS-network$slug-$timestamp.txt"

    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Network info saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== diag/office-license-status/diag.ps1 ===
# diag.ps1
# Checks Office activation/license status via ospp.vbs and saves output to desktop

param([string]$ClientName = "")

Write-Host "  BankOnIT OSS | Office License Status" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

try {
    $osppPaths = @(
        "$env:ProgramFiles\Microsoft Office\root\Office16\OSPP.VBS",
        "$env:ProgramFiles\Microsoft Office\Office16\OSPP.VBS",
        "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OSPP.VBS",
        "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS"
    )
    $ospp = $osppPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (!$ospp) {
        Write-Host ""
        Write-Host "ERROR: ospp.vbs not found. Office may not be installed or is a non-standard install." -ForegroundColor Red
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 1
    }

    Write-Host ""
    Write-Host "INFO: Running ospp.vbs /dstatus..." -ForegroundColor Yellow

    $result = & cscript //nologo $ospp /dstatus 2>&1

    Write-Host ""
    $result | ForEach-Object { Write-Host $_ }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $slug      = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { "" }
    $desktop   = [Environment]::GetFolderPath("Desktop")
    $outFile   = "$desktop\OSS-license$slug-$timestamp.txt"

    $output = @(
        "BankOnIT OSS | Office License Status",
        "patrick hart - hartforge.dev",
        "Generated: $(Get-Date)",
        "Machine: $env:COMPUTERNAME",
        ""
    ) + $result

    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Output saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== diag/outlook-config-dump/diag.ps1 ===
# diag.ps1
# Exports Outlook-related registry keys to a text file on the desktop

param([string]$ClientName = "")

Write-Host "  BankOnIT OSS | Outlook Config Dump" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $output    = [System.Collections.Generic.List[string]]::new()

    $output.Add("BankOnIT OSS | Outlook Config Dump")
    $output.Add("patrick hart - hartforge.dev")
    $output.Add("Generated: $(Get-Date)")
    $output.Add("User: $env:USERDOMAIN\$env:USERNAME")
    $output.Add("")

    $keys = @(
        "HKCU:\Software\Microsoft\Office\16.0\Outlook",
        "HKLM:\Software\Policies\Microsoft\Office\16.0\Outlook",
        "HKLM:\Software\Microsoft\Office\16.0\Common\Identity",
        "HKLM:\Software\Policies\Microsoft\Windows\WorkplaceJoin",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Teams"
    )

    foreach ($key in $keys) {
        $output.Add("=== $key ===")

        if (!(Test-Path $key)) {
            $output.Add("  (key not found)")
            $output.Add("")
            continue
        }

        # Top-level values
        $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($props) {
            $props.PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS' } |
                ForEach-Object { $output.Add("  $($_.Name) = $($_.Value)") }
        }

        # One level of subkeys
        Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
            $output.Add("")
            $output.Add("  [$($_.PSChildName)]")
            $sub = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($sub) {
                $sub.PSObject.Properties |
                    Where-Object { $_.Name -notmatch '^PS' } |
                    ForEach-Object { $output.Add("    $($_.Name) = $($_.Value)") }
            }
        }

        $output.Add("")
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    $slug    = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { "" }
    $outFile = "$desktop\OSS-outlook-config$slug-$timestamp.txt"
    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Config dump saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== diag/system-snapshot/diag.ps1 ===
# diag.ps1
# Collects OS, domain, Outlook version, and key registry values -- saves to desktop

param([string]$ClientName = "")

Write-Host "  BankOnIT OSS | System Snapshot" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $output    = [System.Collections.Generic.List[string]]::new()

    $output.Add("BankOnIT OSS | System Snapshot")
    $output.Add("patrick hart - hartforge.dev")
    $output.Add("Generated: $(Get-Date)")
    $output.Add("")

    # OS
    $output.Add("=== OS ===")
    $os = Get-WmiObject Win32_OperatingSystem
    $output.Add("Caption:    $($os.Caption)")
    $output.Add("Build:      $($os.BuildNumber)")
    $output.Add("Version:    $($os.Version)")
    $output.Add("Last Boot:  $($os.ConvertToDateTime($os.LastBootUpTime))")
    $output.Add("")

    # Domain / Machine
    $output.Add("=== Machine ===")
    $cs = Get-WmiObject Win32_ComputerSystem
    $output.Add("Computer:   $($cs.Name)")
    $output.Add("Domain:     $($cs.Domain)")
    $roles = @{0="Standalone Workstation";1="Member Workstation";2="Standalone Server";3="Member Server";4="DC Backup";5="DC Primary"}
    $output.Add("Role:       $($roles[[int]$cs.DomainRole])")
    $output.Add("")

    # Current user
    $output.Add("=== Current User ===")
    $output.Add("User:       $env:USERDOMAIN\$env:USERNAME")
    $output.Add("")

    # Office / Outlook version
    $output.Add("=== Office ===")
    $c2r = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
    if ($c2r) {
        $output.Add("Version:    $($c2r.VersionToReport)")
        $output.Add("Platform:   $($c2r.Platform)")
        $output.Add("Channel:    $($c2r.CDNBaseUrl)")
    }
    else {
        $output.Add("Version:    (not found via ClickToRun -- may be MSI install)")
    }
    $output.Add("")

    # Key registry values
    $output.Add("=== Key Registry Values ===")

    $adPath = "HKLM:\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover"
    $output.Add("[Autodiscover Policy]")
    if (Test-Path $adPath) {
        $ad = Get-ItemProperty $adPath -ErrorAction SilentlyContinue
        $output.Add("  ExcludeExplicitO365Endpoint : $($ad.ExcludeExplicitO365Endpoint)")
        $output.Add("  ExcludeHttpsRootDomain      : $($ad.ExcludeHttpsRootDomain)")
    }
    else {
        $output.Add("  (not set)")
    }
    $output.Add("")

    $wamPath = "HKLM:\Software\Microsoft\Office\16.0\Common\Identity"
    $output.Add("[WAM / Identity]")
    if (Test-Path $wamPath) {
        $wam = Get-ItemProperty $wamPath -ErrorAction SilentlyContinue
        $output.Add("  EnableADAL   : $($wam.EnableADAL)")
        $output.Add("  DisableAADWAM: $($wam.DisableAADWAM)")
    }
    else {
        $output.Add("  (not set)")
    }
    $output.Add("")

    $wjPath = "HKLM:\Software\Policies\Microsoft\Windows\WorkplaceJoin"
    $output.Add("[Workplace Join Policy]")
    if (Test-Path $wjPath) {
        $wj = Get-ItemProperty $wjPath -ErrorAction SilentlyContinue
        $output.Add("  BlockAADWorkplaceJoin: $($wj.BlockAADWorkplaceJoin)")
    }
    else {
        $output.Add("  (not set)")
    }
    $output.Add("")

    $teamsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Teams"
    $output.Add("[Teams Policy]")
    if (Test-Path $teamsPath) {
        $t = Get-ItemProperty $teamsPath -ErrorAction SilentlyContinue
        $output.Add("  PreventFirstLaunchAfterLogon: $($t.PreventFirstLaunchAfterLogon)")
        $output.Add("  PreventInstallationFromMsi  : $($t.PreventInstallationFromMsi)")
    }
    else {
        $output.Add("  (not set)")
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    $slug    = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { "" }
    $outFile = "$desktop\OSS-snapshot$slug-$timestamp.txt"
    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Snapshot saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/block-aad-workplacejoin/fix.ps1 ===
# fix.ps1
# Blocks Entra ID device registration nag on domain-joined machines

param([string]$Environment = "onprem")

Write-Host "  BankOnIT OSS | Block AAD Workplace Join" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  environment: $Environment" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

# Warn on M365/hybrid -- blocking workplace join can break Conditional Access
if ($Environment -eq "m365" -or $Environment -eq "hybrid") {
    Write-Host ""
    Write-Host "WARNING: This client is $Environment." -ForegroundColor Yellow
    Write-Host "Blocking AAD Workplace Join on M365 or hybrid environments can break" -ForegroundColor Yellow
    Write-Host "Conditional Access policies and modern authentication flows." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Proceed anyway? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host ""
        Write-Host "INFO: Aborted." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }
}

try {
    $path = "HKLM:\Software\Policies\Microsoft\Windows\WorkplaceJoin"

    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "BlockAADWorkplaceJoin" -Value 1 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: AAD Workplace Join blocked for this machine." -ForegroundColor Green
    Write-Host "The 'Your organization wants to manage this device' prompt will no longer appear."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/clear-office-cache/fix.ps1 ===
# fix.ps1
# Clears Office identity and license cache to fix account notice and activation loops

Write-Host "  BankOnIT OSS | Clear Office Cache" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

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
        Remove-Item -Path "$licensePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        $cleared += "Office license cache ($licensePath)"
    }

    # Office identity/token cache in registry
    $identityPath = "HKCU:\Software\Microsoft\Office\16.0\Common\Identity\Identities"
    if (Test-Path $identityPath) {
        Remove-Item -Path $identityPath -Recurse -Force -ErrorAction SilentlyContinue
        $cleared += "Office identity registry cache"
    }

    # Token broker cache
    $tokenPath = "$env:LOCALAPPDATA\Microsoft\TokenBroker\Cache"
    if (Test-Path $tokenPath) {
        Remove-Item -Path "$tokenPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        $cleared += "Token broker cache ($tokenPath)"
    }

    Write-Host ""
    if ($cleared.Count -gt 0) {
        Write-Host "SUCCESS: Cleared $($cleared.Count) cache location(s):" -ForegroundColor Green
        $cleared | ForEach-Object { Write-Host "  $_" }
    }
    else {
        Write-Host "INFO: No cache locations found -- nothing to clear." -ForegroundColor Yellow
    }
    Write-Host "Sign back in to Office after reopening."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/credential-cleanup/fix.ps1 ===
# fix.ps1
# Clears stale Exchange/Office credentials from the Windows Credential Manager

Write-Host "  BankOnIT OSS | Credential Cleanup" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

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
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/disable-wam/fix.ps1 ===
# fix.ps1
# Disables WAM (Web Account Manager) for Office authentication

param([string]$Environment = "onprem")

Write-Host "  BankOnIT OSS | Disable WAM" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  environment: $Environment" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

# WAM/ADAL is required for M365 modern auth -- do not disable on cloud-only clients
if ($Environment -eq "m365") {
    Write-Host ""
    Write-Host "WARNING: This client is M365 (cloud only)." -ForegroundColor Yellow
    Write-Host "Disabling WAM on an M365 environment will break modern authentication" -ForegroundColor Yellow
    Write-Host "and cause sign-in loops. This fix is not applicable here." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 0
}

# Hybrid -- warn but allow
if ($Environment -eq "hybrid") {
    Write-Host ""
    Write-Host "WARNING: This client is hybrid (Exchange + M365)." -ForegroundColor Yellow
    Write-Host "Disabling WAM on a hybrid environment can cause auth issues for M365 services." -ForegroundColor Yellow
    Write-Host "Only proceed if you have confirmed WAM is the root cause." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Proceed anyway? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host ""
        Write-Host "INFO: Aborted." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "Press Enter to close"
        exit 0
    }
}

try {
    $path = "HKLM:\Software\Microsoft\Office\16.0\Common\Identity"

    if (!(Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    Set-ItemProperty -Path $path -Name "EnableADAL" -Value 0 -Type DWord
    Set-ItemProperty -Path $path -Name "DisableAADWAM" -Value 1 -Type DWord

    Write-Host ""
    Write-Host "SUCCESS: WAM disabled for Office on this machine." -ForegroundColor Green
    Write-Host "Office will use legacy credential prompts instead of WAM."
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/fix-print-spooler/fix.ps1 ===
# fix.ps1
# Clears the print queue and restarts the spooler

Write-Host "  BankOnIT OSS | Fix Print Spooler" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

try {
    Write-Host ""
    Write-Host "INFO: Stopping print spooler..." -ForegroundColor Yellow
    Stop-Service -Name Spooler -Force -ErrorAction Stop

    Write-Host "INFO: Clearing spool queue..." -ForegroundColor Yellow
    $spoolPath = "$env:SystemRoot\System32\spool\PRINTERS"
    $files = Get-ChildItem -Path $spoolPath -ErrorAction SilentlyContinue
    if ($files) {
        Remove-Item -Path "$spoolPath\*" -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "INFO: $($files.Count) spool file(s) removed." -ForegroundColor Yellow
    }
    else {
        Write-Host "INFO: Spool queue already empty." -ForegroundColor Yellow
    }

    Write-Host "INFO: Starting print spooler..." -ForegroundColor Yellow
    Start-Service -Name Spooler -ErrorAction Stop

    Write-Host ""
    Write-Host "SUCCESS: Print spooler restarted and queue cleared." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "INFO: Attempting to restart spooler anyway..." -ForegroundColor Yellow
    Start-Service -Name Spooler -ErrorAction SilentlyContinue
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/flush-dns-winsock/fix.ps1 ===
# fix.ps1
# Flushes DNS cache and resets Winsock

Write-Host "  BankOnIT OSS | Flush DNS / Winsock Reset" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

try {
    Write-Host ""
    Write-Host "INFO: Flushing DNS cache..." -ForegroundColor Yellow
    $dns = ipconfig /flushdns 2>&1
    Write-Host "SUCCESS: DNS cache flushed." -ForegroundColor Green

    Write-Host ""
    Write-Host "INFO: Resetting Winsock..." -ForegroundColor Yellow
    $winsock = netsh winsock reset 2>&1
    Write-Host "SUCCESS: Winsock reset." -ForegroundColor Green

    Write-Host ""
    Write-Host "INFO: A reboot is required for the Winsock reset to fully take effect." -ForegroundColor Yellow
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/outlook-autodiscover/fix.ps1 ===
# fix.ps1
# Configures Outlook autodiscover registry keys for on-prem, M365, or hybrid

param([string]$Environment = "onprem")

Write-Host "  BankOnIT OSS | Outlook Autodiscover Fix" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  environment: $Environment" -ForegroundColor DarkGray

# Check for admin
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

$path = "HKLM:\Software\Policies\Microsoft\Office\16.0\Outlook\AutoDiscover"

try {
    if ($Environment -eq "m365") {
        # M365 only -- cloud autodiscover should work normally, remove any blocking keys
        Write-Host ""
        Write-Host "INFO: M365 environment -- removing any on-prem autodiscover blocks." -ForegroundColor Yellow
        if (Test-Path $path) {
            Remove-ItemProperty -Path $path -Name "ExcludeExplicitO365Endpoint" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $path -Name "ExcludeHttpsRootDomain" -ErrorAction SilentlyContinue
            Write-Host ""
            Write-Host "SUCCESS: Cloud autodiscover exclusion keys removed." -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "INFO: No exclusion keys found -- nothing to remove." -ForegroundColor Yellow
        }
    }
    elseif ($Environment -eq "hybrid") {
        # Hybrid -- exclude root domain lookup (causes on-prem/cloud confusion) but keep O365 endpoint accessible
        Write-Host ""
        Write-Host "INFO: Hybrid environment -- excluding root domain, keeping O365 endpoint." -ForegroundColor Yellow
        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        Set-ItemProperty -Path $path -Name "ExcludeHttpsRootDomain" -Value 1 -Type DWord
        Remove-ItemProperty -Path $path -Name "ExcludeExplicitO365Endpoint" -ErrorAction SilentlyContinue
        Write-Host ""
        Write-Host "SUCCESS: Hybrid autodiscover configured." -ForegroundColor Green
        Write-Host "Root domain excluded. O365 endpoint remains accessible."
    }
    else {
        # On-prem -- block both cloud endpoints
        if (!(Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        Set-ItemProperty -Path $path -Name "ExcludeExplicitO365Endpoint" -Value 1 -Type DWord
        Set-ItemProperty -Path $path -Name "ExcludeHttpsRootDomain" -Value 1 -Type DWord
        Write-Host ""
        Write-Host "SUCCESS: Autodiscover cloud exclusions set for all users." -ForegroundColor Green
        Write-Host "Restart Outlook on any active sessions to apply."
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/outlook-profile-rebuild/fix.ps1 ===
# fix.ps1
# Deletes Outlook profile(s) from registry so Outlook prompts for a fresh setup

Write-Host "  BankOnIT OSS | Outlook Profile Rebuild" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

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

    $profiles = Get-ChildItem -Path $profilesPath | Select-Object -ExpandProperty PSChildName

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
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/reset-outlook-navpane/fix.ps1 ===
# fix.ps1
# Resets the Outlook navigation pane to fix corrupt nav pane issues

Write-Host "  BankOnIT OSS | Reset Outlook Nav Pane" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

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
}

Write-Host ""
Read-Host "Press Enter to close"

=== fixes/reset-teams-cache/fix.ps1 ===
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

=== launcher.bat ===
@echo off
setlocal

:: Self-elevate to admin if not already elevated
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:SELECT_ENV
cls
echo ============================================================
echo  BankOnIT OSS Toolkit  v1.2
echo  patrick hart - hartforge.dev
echo ============================================================
echo.
echo  client mail environment:
echo.
echo   1. on-premises exchange only
echo   2. microsoft 365 (cloud only)
echo   3. hybrid (exchange + m365)
echo.
set /p env_choice="select environment: "
if "%env_choice%"=="1" set OSSENV=onprem & goto GET_CLIENT
if "%env_choice%"=="2" set OSSENV=m365   & goto GET_CLIENT
if "%env_choice%"=="3" set OSSENV=hybrid & goto GET_CLIENT
goto SELECT_ENV

:GET_CLIENT
echo.
set /p CLIENTNAME="client name / branch (e.g. FirstNational-Downtown): "
if "%CLIENTNAME%"=="" goto GET_CLIENT

:MENU
cls
echo ============================================================
echo  BankOnIT OSS Toolkit  v1.2  [%OSSENV%]  [%CLIENTNAME%]
echo  patrick hart - hartforge.dev
echo ============================================================
echo.
echo  -- FIXES --
echo   1. Outlook Autodiscover          (configure autodiscover for %OSSENV%)
echo   2. Block AAD Workplace Join      (suppress Entra ID device registration nag)
echo   3. Disable WAM                   (stop Office routing auth through WAM)
echo   4. Credential Cleanup            (purge stale Exchange/Office creds)
echo   5. Outlook Profile Rebuild       (delete and recreate Outlook profile)
echo   6. Clear Office Cache            (nuke Office identity/license cache)
echo   7. Reset Teams Cache             (clear Teams cache folders)
echo   8. Flush DNS / Winsock Reset     (flush DNS cache and reset winsock)
echo   9. Reset Outlook Nav Pane        (fix corrupt Outlook navigation pane)
echo  10. Fix Print Spooler             (clear queue and restart spooler)
echo.
echo  -- CONFIG --
echo   C1. Disable Teams Auto-Install       (prevent consumer Teams install)
echo   C2. Disable OneDrive Auto-Install    (prevent consumer OneDrive install)
echo   C3. Disable MS Account Sign-in       (block personal MS account prompts in Office)
echo   C4. Disable Update Auto-Reboot       (stop Windows Update mid-day reboots)
echo   C5. Edge IE Mode Sites               (enable IE mode and manage site list)
echo.
echo  -- DIAG --
echo   D1. System Snapshot              (OS, domain, Outlook version, key reg values)
echo   D2. Exchange Connectivity        (test DC/Exchange/M365 reachability)
echo   D3. Outlook Config Dump          (export Outlook registry to file)
echo   D4. Office License Status        (check Office activation via ospp.vbs)
echo   D5. Event Log Errors             (last 100 errors from App and System logs)
echo   D6. Network Info                 (IP, gateway, DNS, DHCP info for active adapters)
echo   DA. Run All Diag                 (run D1-D6 in sequence)
echo.
echo   Q. Quit
echo.
set /p choice="select option: "

if /i "%choice%"=="1"  goto RUN_AUTODISCOVER
if /i "%choice%"=="2"  goto RUN_WORKPLACEJOIN
if /i "%choice%"=="3"  goto RUN_WAM
if /i "%choice%"=="4"  goto RUN_CREDS
if /i "%choice%"=="5"  goto RUN_PROFILE
if /i "%choice%"=="6"  goto RUN_OFFICECACHE
if /i "%choice%"=="7"  goto RUN_TEAMSCACHE
if /i "%choice%"=="8"  goto RUN_DNS
if /i "%choice%"=="9"  goto RUN_NAVPANE
if /i "%choice%"=="10" goto RUN_SPOOLER
if /i "%choice%"=="C1" goto RUN_TEAMS
if /i "%choice%"=="C2" goto RUN_ONEDRIVE
if /i "%choice%"=="C3" goto RUN_MSACCOUNT
if /i "%choice%"=="C4" goto RUN_AUTOREBOOT
if /i "%choice%"=="C5" goto RUN_IEMODE
if /i "%choice%"=="D1" goto RUN_SNAPSHOT
if /i "%choice%"=="D2" goto RUN_EXCHCONN
if /i "%choice%"=="D3" goto RUN_OUTLOOKDUMP
if /i "%choice%"=="D4" goto RUN_LICENSE
if /i "%choice%"=="D5" goto RUN_EVENTLOG
if /i "%choice%"=="D6" goto RUN_NETINFO
if /i "%choice%"=="DA" goto RUN_ALL_DIAG
if /i "%choice%"=="Q"  exit /b
goto MENU

:LOG
echo %DATE% %TIME:~0,8% ^| %COMPUTERNAME% ^| %CLIENTNAME% ^| %OSSENV% ^| %LOGSCRIPT% >> "%USERPROFILE%\Desktop\OSS-session-log.txt"
goto %LOGBACK%

:RUN_AUTODISCOVER
set LOGSCRIPT=outlook-autodiscover & set LOGBACK=RUN_AUTODISCOVER_GO & goto LOG
:RUN_AUTODISCOVER_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\outlook-autodiscover\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_WORKPLACEJOIN
set LOGSCRIPT=block-aad-workplacejoin & set LOGBACK=RUN_WORKPLACEJOIN_GO & goto LOG
:RUN_WORKPLACEJOIN_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\block-aad-workplacejoin\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_WAM
set LOGSCRIPT=disable-wam & set LOGBACK=RUN_WAM_GO & goto LOG
:RUN_WAM_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\disable-wam\fix.ps1" -Environment "%OSSENV%"
goto MENU

:RUN_CREDS
set LOGSCRIPT=credential-cleanup & set LOGBACK=RUN_CREDS_GO & goto LOG
:RUN_CREDS_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\credential-cleanup\fix.ps1"
goto MENU

:RUN_PROFILE
set LOGSCRIPT=outlook-profile-rebuild & set LOGBACK=RUN_PROFILE_GO & goto LOG
:RUN_PROFILE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\outlook-profile-rebuild\fix.ps1"
goto MENU

:RUN_OFFICECACHE
set LOGSCRIPT=clear-office-cache & set LOGBACK=RUN_OFFICECACHE_GO & goto LOG
:RUN_OFFICECACHE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\clear-office-cache\fix.ps1"
goto MENU

:RUN_TEAMSCACHE
set LOGSCRIPT=reset-teams-cache & set LOGBACK=RUN_TEAMSCACHE_GO & goto LOG
:RUN_TEAMSCACHE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\reset-teams-cache\fix.ps1"
goto MENU

:RUN_DNS
set LOGSCRIPT=flush-dns-winsock & set LOGBACK=RUN_DNS_GO & goto LOG
:RUN_DNS_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\flush-dns-winsock\fix.ps1"
goto MENU

:RUN_NAVPANE
set LOGSCRIPT=reset-outlook-navpane & set LOGBACK=RUN_NAVPANE_GO & goto LOG
:RUN_NAVPANE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\reset-outlook-navpane\fix.ps1"
goto MENU

:RUN_SPOOLER
set LOGSCRIPT=fix-print-spooler & set LOGBACK=RUN_SPOOLER_GO & goto LOG
:RUN_SPOOLER_GO
powershell -ExecutionPolicy Bypass -File "%~dp0fixes\fix-print-spooler\fix.ps1"
goto MENU

:RUN_TEAMS
set LOGSCRIPT=disable-teams-autoinstall & set LOGBACK=RUN_TEAMS_GO & goto LOG
:RUN_TEAMS_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-teams-autoinstall\config.ps1"
goto MENU

:RUN_ONEDRIVE
set LOGSCRIPT=disable-onedrive-autoinstall & set LOGBACK=RUN_ONEDRIVE_GO & goto LOG
:RUN_ONEDRIVE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-onedrive-autoinstall\config.ps1"
goto MENU

:RUN_MSACCOUNT
set LOGSCRIPT=disable-ms-account-signin & set LOGBACK=RUN_MSACCOUNT_GO & goto LOG
:RUN_MSACCOUNT_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-ms-account-signin\config.ps1"
goto MENU

:RUN_AUTOREBOOT
set LOGSCRIPT=disable-update-autoreboot & set LOGBACK=RUN_AUTOREBOOT_GO & goto LOG
:RUN_AUTOREBOOT_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\disable-update-autoreboot\config.ps1"
goto MENU

:RUN_IEMODE
set LOGSCRIPT=edge-ie-mode-sites & set LOGBACK=RUN_IEMODE_GO & goto LOG
:RUN_IEMODE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0config\edge-ie-mode-sites\config.ps1"
goto MENU

:RUN_SNAPSHOT
set LOGSCRIPT=system-snapshot & set LOGBACK=RUN_SNAPSHOT_GO & goto LOG
:RUN_SNAPSHOT_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\system-snapshot\diag.ps1" -ClientName "%CLIENTNAME%"
goto MENU

:RUN_EXCHCONN
set LOGSCRIPT=exchange-connectivity & set LOGBACK=RUN_EXCHCONN_GO & goto LOG
:RUN_EXCHCONN_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\exchange-connectivity\diag.ps1" -Environment "%OSSENV%" -ClientName "%CLIENTNAME%"
goto MENU

:RUN_OUTLOOKDUMP
set LOGSCRIPT=outlook-config-dump & set LOGBACK=RUN_OUTLOOKDUMP_GO & goto LOG
:RUN_OUTLOOKDUMP_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\outlook-config-dump\diag.ps1" -ClientName "%CLIENTNAME%"
goto MENU

:RUN_LICENSE
set LOGSCRIPT=office-license-status & set LOGBACK=RUN_LICENSE_GO & goto LOG
:RUN_LICENSE_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\office-license-status\diag.ps1" -ClientName "%CLIENTNAME%"
goto MENU

:RUN_EVENTLOG
set LOGSCRIPT=event-log-errors & set LOGBACK=RUN_EVENTLOG_GO & goto LOG
:RUN_EVENTLOG_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\event-log-errors\diag.ps1" -ClientName "%CLIENTNAME%"
goto MENU

:RUN_NETINFO
set LOGSCRIPT=network-info & set LOGBACK=RUN_NETINFO_GO & goto LOG
:RUN_NETINFO_GO
powershell -ExecutionPolicy Bypass -File "%~dp0diag\network-info\diag.ps1" -ClientName "%CLIENTNAME%"
goto MENU

:RUN_ALL_DIAG
set LOGSCRIPT=run-all-diag & set LOGBACK=RUN_ALL_DIAG_GO & goto LOG
:RUN_ALL_DIAG_GO
echo running all diag tools -- output files will appear on your desktop.
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0diag\system-snapshot\diag.ps1"       -ClientName "%CLIENTNAME%"
powershell -ExecutionPolicy Bypass -File "%~dp0diag\exchange-connectivity\diag.ps1" -Environment "%OSSENV%" -ClientName "%CLIENTNAME%"
powershell -ExecutionPolicy Bypass -File "%~dp0diag\outlook-config-dump\diag.ps1"   -ClientName "%CLIENTNAME%"
powershell -ExecutionPolicy Bypass -File "%~dp0diag\office-license-status\diag.ps1" -ClientName "%CLIENTNAME%"
powershell -ExecutionPolicy Bypass -File "%~dp0diag\event-log-errors\diag.ps1"      -ClientName "%CLIENTNAME%"
powershell -ExecutionPolicy Bypass -File "%~dp0diag\network-info\diag.ps1"          -ClientName "%CLIENTNAME%"
echo.
echo all diag tools complete.
pause
goto MENU

=== package.bat ===
@echo off
echo packaging OSS toolkit to desktop...
powershell -Command "Compress-Archive -Path '%~dp0' -DestinationPath '%USERPROFILE%\Desktop\BankOnIT-OSS.zip' -Force"
echo.
echo done. BankOnIT-OSS.zip is on your desktop.
echo.
pause
