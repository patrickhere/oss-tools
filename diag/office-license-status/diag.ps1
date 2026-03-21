# diag.ps1
# Checks Office activation/license status via ospp.vbs and saves output to desktop

param([string]$ClientName = "", [string]$OutputDir = "", [switch]$NonInteractive)

. (Join-Path $PSScriptRoot '..\lib\DiagHelpers.ps1')

Write-Host "  BankOnIT OSS | Office License Status" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
Invoke-UpdateCheck


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
        if (-not $NonInteractive) { Read-Host "Press Enter to close" }
        exit 1
    }

    Write-Host ""
    Write-Host "INFO: Running ospp.vbs /dstatus..." -ForegroundColor Yellow

    $result = & cscript //nologo $ospp /dstatus 2>&1

    Write-Host ""
    $result | ForEach-Object { Write-Host $_ }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $outFile   = Resolve-DiagOutput -Prefix 'OSS-license' -Timestamp $timestamp -OutputDir $OutputDir -ClientName $ClientName

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
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
