#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for diag scripts.
    Dot-source this file to use Invoke-UpdateCheck and Resolve-DiagOutput.
#>

function Invoke-UpdateCheck {
    # Skip if already checked by launcher (OSSMANAGED=1 set by launcher.bat after its own update check)
    if ($env:OSSMANAGED -eq '1') { return }
    $_upd = Join-Path $PSScriptRoot "..\..\update.ps1"
    if (Test-Path $_upd) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }
}

function Resolve-DiagOutput {
    param(
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$Timestamp,
        [string]$OutputDir  = '',
        [string]$ClientName = ''
    )
    $slug   = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { '' }
    $outDir = if ($OutputDir) {
        $null = New-Item -ItemType Directory -Path $OutputDir -Force -ErrorAction SilentlyContinue
        $OutputDir
    } else {
        [Environment]::GetFolderPath('Desktop')
    }
    return Join-Path $outDir "$Prefix$slug-$Timestamp.txt"
}
