#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for Backup.ps1 and Restore.ps1.
    Dot-source this file; it defines Write-Log, Read-Toggle, and Invoke-Robocopy.
    These functions reference $script:* variables from the calling script's scope.
#>

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
        Write-Host '  Please respond with Y or N.' -ForegroundColor DarkGray
    }
}

function Invoke-Robocopy {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $savedEAP = $ErrorActionPreference
    $exit     = 0
    $out      = $null
    try {
        $ErrorActionPreference = 'Continue'
        $out  = & robocopy @Arguments 2>&1
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedEAP
    }
    return [pscustomobject]@{ ExitCode = $exit; Output = $out }
}
