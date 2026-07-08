#Requires -Version 5.1
<#
.SYNOPSIS
    Navanta Restore Utility
.DESCRIPTION
    Restores user profile (Transwiz), Public Desktop, and browser bookmarks
    from a backup created by Backup.ps1. Can optionally stage the backup folder
    locally via robocopy first -- recommended for large profiles or slow links.
.PARAMETER SourcePath
    Override the source directory. Defaults to the folder this script lives in.
#>
param(
    [string]$SourcePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\Common.ps1')

# Global trap -- catch any unhandled terminating error, log it, then show summary
trap {
    $errMsg  = $_.Exception.Message
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
# CONFIG -- all paths defined here
# ---------------------------------------------------------------------------
$NavantaRoot  = "$env:SystemDrive\BankOnIT"
$OldComputerDir = Join-Path $NavantaRoot 'Old Computer'
$StagingRoot    = Join-Path $NavantaRoot 'Restore'

# ---------------------------------------------------------------------------
# TRACKING -- populated by Write-Log, consumed by Show-Summary
# ---------------------------------------------------------------------------
$script:WarnCount  = 0
$script:ErrorCount = 0
$script:Issues     = [System.Collections.Generic.List[string]]::new()
$script:LogPath    = $null
$script:StartTime  = Get-Date

# Component run-state tracking for summary
$script:RanStaging       = $false
$script:RanTranswiz      = $false
$script:RanPublicDesktop = $false
$script:RanBrowserData   = $false
$script:RanCleanup       = $false


# ---------------------------------------------------------------------------
# SHOW-SUMMARY
# ---------------------------------------------------------------------------
function Show-Summary {
    $elapsed    = (Get-Date) - $script:StartTime
    $elapsedStr = '{0:hh}:{0:mm}:{0:ss}' -f $elapsed

    $sep = '=' * 50
    Write-Host ''
    Write-Host $sep -ForegroundColor Cyan
    Write-Host '  Restore Summary' -ForegroundColor Cyan
    Write-Host $sep -ForegroundColor Cyan
    Write-Host ("  Computer  : {0}" -f $env:COMPUTERNAME)
    Write-Host ("  User      : {0}" -f $env:USERNAME)
    Write-Host ("  Source    : {0}" -f $script:SourceDir)
    Write-Host ("  Elapsed   : {0}" -f $elapsedStr)
    Write-Host ''

    $colW = 18
    Write-Host ("  {0,-$colW} {1}" -f 'Component', 'Status') -ForegroundColor White
    Write-Host ("  {0,-$colW} {1}" -f ('-' * ($colW - 1)), ('-' * 7)) -ForegroundColor DarkGray

    $components = @(
        @{ Name='Local Staging';  Ran=$script:RanStaging       },
        @{ Name='Transwiz';       Ran=$script:RanTranswiz      },
        @{ Name='Public Desktop'; Ran=$script:RanPublicDesktop },
        @{ Name='Browser Data';   Ran=$script:RanBrowserData   },
        @{ Name='Cleanup';        Ran=$script:RanCleanup       }
    )
    foreach ($c in $components) {
        $status = if ($c.Ran) { 'RAN' } else { 'SKIPPED' }
        $color  = if ($c.Ran) { 'Green' } else { 'DarkGray' }
        Write-Host ('  {0,-18} ' -f $c.Name) -NoNewline
        Write-Host $status -ForegroundColor $color
    }

    Write-Host ''
    $wColor = if ($script:WarnCount  -gt 0) { 'Yellow' } else { 'Green' }
    $eColor = if ($script:ErrorCount -gt 0) { 'Red'    } else { 'Green' }
    Write-Host ("  Warnings : {0}" -f $script:WarnCount)  -ForegroundColor $wColor
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
    Write-Host '[ERROR] Administrative privileges required. Right-click Restore.bat and choose "Run as administrator".' -ForegroundColor Red
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

    Navanta Restore Utility  --  PowerShell Edition
    patrick hart -- hartforge.dev
  ==================================================
  Computer : {0}
  Date     : {1}
  ==================================================

'@
Write-Host ($banner -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm')) -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# PHASE 2: SOURCE RESOLUTION
# ---------------------------------------------------------------------------
# PSScriptRoot works natively for UNC paths -- no pushd workaround needed
if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
    $script:SourceDir = $SourcePath.TrimEnd('\')
} else {
    $script:SourceDir = $PSScriptRoot
}

$script:PcName = Split-Path $script:SourceDir -Leaf

Write-Host ''
Write-Host 'Restore source:' -ForegroundColor White
Write-Host "  $($script:SourceDir)"
Write-Host "  PC name: $($script:PcName)"
Write-Host ''

if (-not (Test-Path $script:SourceDir)) {
    Write-Host "[ERROR] Source path not found: $($script:SourceDir)" -ForegroundColor Red
    Read-Host 'Press Enter to exit'
    exit 1
}

# Set up log
$null = New-Item -ItemType Directory -Path $OldComputerDir -Force
$script:LogPath = Join-Path $OldComputerDir 'restorelog.txt'
'' | Set-Content -Path $script:LogPath -Encoding UTF8

Write-Log "Restore started on $env:COMPUTERNAME"
Write-Log "Source: $($script:SourceDir)"
Write-Log "PC name: $($script:PcName)"

# ---------------------------------------------------------------------------
# PHASE 3: PROMPTS + TOGGLES
# ---------------------------------------------------------------------------
Write-Host 'Optional components (press Enter to accept default):' -ForegroundColor White
$DoStaging       = Read-Toggle -Prompt 'Stage backup locally via robocopy first (recommended for large profiles or slow links)' -Default $false
$DoTranswiz      = Read-Toggle -Prompt 'Restore user profile (Transwiz)'                                                        -Default $true
$DoPublicDesktop = Read-Toggle -Prompt 'Restore Public Desktop'                                                                  -Default $true
$DoBrowserData   = Read-Toggle -Prompt 'Restore browser bookmarks (Edge/Chrome/Firefox)'                                         -Default $true
$DoCleanup       = Read-Toggle -Prompt 'Move old computer files to C:\BankOnIT\Old Computer'                                     -Default $true

Write-Log "Staging: $(if ($DoStaging) {'enabled'} else {'skipped'})"
Write-Log "Transwiz: $(if ($DoTranswiz) {'enabled'} else {'skipped'})"
Write-Log "Public Desktop: $(if ($DoPublicDesktop) {'enabled'} else {'skipped'})"
Write-Log "Browser data: $(if ($DoBrowserData) {'enabled'} else {'skipped'})"
Write-Log "Cleanup: $(if ($DoCleanup) {'enabled'} else {'skipped'})"

# ---------------------------------------------------------------------------
# PHASE 4a: LOCAL STAGING (robocopy)
# ---------------------------------------------------------------------------
if ($DoStaging) {
    Write-Host ''
    Write-Log 'Staging backup folder locally via robocopy...'

    $stageDest = Join-Path $StagingRoot $script:PcName
    $null = New-Item -ItemType Directory -Path $stageDest -Force

    $robo = Invoke-Robocopy @($script:SourceDir, $stageDest, '/E', '/R:2', '/W:5', '/NP', '/NDL')

    if ($robo.ExitCode -ge 8) {
        Write-Log "robocopy failed with exit code $($robo.ExitCode) -- $($robo.Output -join ' | ')" -Severity ERROR
        Write-Log 'Continuing from original source.' -Severity WARN
    } else {
        Write-Log "Staging complete (robocopy exit $($robo.ExitCode)) -> $stageDest"
        $script:SourceDir = $stageDest
        $script:RanStaging = $true
    }
} else {
    Write-Log 'Skipping local staging per technician selection.'
}

# ---------------------------------------------------------------------------
# PHASE 4b: TRANSWIZ
# ---------------------------------------------------------------------------
if ($DoTranswiz) {
    Write-Host ''
    Write-Log 'Launching Transwiz...'

    $transwizExe = Join-Path $script:SourceDir 'Transwiz.exe'
    if (-not (Test-Path $transwizExe)) {
        Write-Log "Transwiz.exe not found at $transwizExe" -Severity ERROR
    } else {
        try {
            $proc     = Start-Process -FilePath $transwizExe -PassThru
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
# PHASE 4c: PUBLIC DESKTOP
# ---------------------------------------------------------------------------
if ($DoPublicDesktop) {
    Write-Host ''
    Write-Log 'Restoring Public Desktop...'

    $pubSrc = Join-Path $script:SourceDir 'Public'
    if (-not (Test-Path $pubSrc)) {
        Write-Log "Public folder not found in backup at $pubSrc" -Severity WARN
    } else {
        $pubDst  = "$env:SystemDrive\Users\Public"
        $xclFile = Join-Path $script:SourceDir 'restore_exclude.txt'

        $roboArgs = @($pubSrc, $pubDst, '/E', '/R:1', '/W:1', '/NP')
        if (Test-Path $xclFile) {
            $excludeLines = Get-Content $xclFile | Where-Object { $_.Trim() -ne '' }
            if ($excludeLines) {
                $roboArgs += '/XF'
                $roboArgs += $excludeLines
            }
        } else {
            Write-Log 'restore_exclude.txt not found -- copying without exclusions.' -Severity WARN
        }

        $robo = Invoke-Robocopy $roboArgs

        if ($robo.ExitCode -ge 8) {
            Write-Log "robocopy failed with exit code $($robo.ExitCode) -- $($robo.Output -join ' | ')" -Severity ERROR
        } else {
            Write-Log "Public Desktop restored (robocopy exit $($robo.ExitCode))"
            $script:RanPublicDesktop = $true
        }
    }
} else {
    Write-Log 'Skipping Public Desktop per technician selection.'
}

# ---------------------------------------------------------------------------
# PHASE 4d: BROWSER BOOKMARKS
# ---------------------------------------------------------------------------
if ($DoBrowserData) {
    Write-Host ''
    Write-Log 'Restoring browser bookmarks...'

    $browsersDir = Join-Path $script:SourceDir 'Browsers'
    if (-not (Test-Path $browsersDir)) {
        Write-Log 'No Browsers folder in backup -- skipping.' -Severity WARN
    } else {
        # Warn if browsers are running -- live Bookmarks file may be locked or overwritten on next launch
        $runningBrowsers = Get-Process -Name @('msedge','chrome') -ErrorAction SilentlyContinue |
                               Select-Object -ExpandProperty Name -Unique
        if ($runningBrowsers) {
            Write-Log "WARNING: $($runningBrowsers -join ', ') is running -- bookmark restore may fail or be overwritten. Close browsers for best results." -Severity WARN
        }
        $anyFound = $false
        foreach ($userDir in (Get-ChildItem -Path $browsersDir -Directory -ErrorAction SilentlyContinue)) {
            $userName = $userDir.Name

            # Edge
            $edgeSrc = Join-Path $userDir.FullName 'Edge\Bookmarks'
            if (Test-Path $edgeSrc) {
                $edgeDest = "$env:SystemDrive\Users\$userName\AppData\Local\Microsoft\Edge\User Data\Default"
                $null = New-Item -ItemType Directory -Path $edgeDest -Force
                Copy-Item $edgeSrc (Join-Path $edgeDest 'Bookmarks') -Force
                Write-Log "Edge bookmarks restored for $userName"
                $anyFound = $true
            }

            # Chrome
            $chromeSrc = Join-Path $userDir.FullName 'Chrome\Bookmarks'
            if (Test-Path $chromeSrc) {
                $chromeDest = "$env:SystemDrive\Users\$userName\AppData\Local\Google\Chrome\User Data\Default"
                $null = New-Item -ItemType Directory -Path $chromeDest -Force
                Copy-Item $chromeSrc (Join-Path $chromeDest 'Bookmarks') -Force
                Write-Log "Chrome bookmarks restored for $userName"
                $anyFound = $true
            }

            # Firefox -- profile dir has random name; copy to Navanta for manual import
            $ffSrc = Join-Path $userDir.FullName 'Firefox\places.sqlite'
            if (Test-Path $ffSrc) {
                $ffDest = Join-Path $NavantaRoot "Firefox\$userName"
                $null = New-Item -ItemType Directory -Path $ffDest -Force
                Copy-Item $ffSrc (Join-Path $ffDest 'places.sqlite') -Force
                Write-Log "Firefox bookmarks for $userName -> $ffDest"
                Write-Log "  Import: Firefox > Bookmarks > Manage Bookmarks > Import and Backup > Restore" -Severity WARN
                $anyFound = $true
            }
        }

        if ($anyFound) {
            $script:RanBrowserData = $true
        } else {
            Write-Log 'No browser bookmark files found in backup.' -Severity WARN
        }
    }
} else {
    Write-Log 'Skipping browser data per technician selection.'
}

# ---------------------------------------------------------------------------
# PHASE 4e: CLEANUP
# ---------------------------------------------------------------------------
if ($DoCleanup) {
    Write-Host ''
    Write-Log "Moving old computer files to $OldComputerDir..."

    $null = New-Item -ItemType Directory -Path $OldComputerDir -Force

    foreach ($item in @("$($script:PcName).html", 'ipconfig.txt', 'PrinterList.txt')) {
        $src = Join-Path $script:SourceDir $item
        if (Test-Path $src) {
            Move-Item $src (Join-Path $OldComputerDir $item) -Force
            Write-Log "Moved $item"
        }
    }

    # MappedDrives.reg -- lives inside a user profile subfolder
    Get-ChildItem -Path $script:SourceDir -Recurse -Filter 'MappedDrives.reg' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $destName = "$($_.Directory.Name)_MappedDrives.reg"
            Move-Item $_.FullName (Join-Path $OldComputerDir $destName) -Force
            Write-Log "Moved MappedDrives.reg ($($_.Directory.Name))"
        }

    $script:RanCleanup = $true
} else {
    Write-Log 'Skipping cleanup per technician selection.'
}

# ---------------------------------------------------------------------------
# PHASE 5: SUMMARY
# ---------------------------------------------------------------------------
Show-Summary

if ($script:RanCleanup) {
    Write-Host "  Old computer files: $OldComputerDir" -ForegroundColor DarkGray
    Write-Host ''
}

Read-Host 'Press Enter to close'
