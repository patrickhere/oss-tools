# diag.ps1
# Pulls the last 100 Application and System errors from the past 24 hours and saves to desktop

param([string]$ClientName = "", [string]$OutputDir = "", [switch]$NonInteractive)

. (Join-Path $PSScriptRoot '..\lib\DiagHelpers.ps1')

Write-Host "  Navanta OSS | Event Log Errors" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
Invoke-UpdateCheck


try {
    $since  = (Get-Date).AddHours(-24)
    $output = [System.Collections.Generic.List[string]]::new()

    $output.Add("Navanta OSS | Event Log Errors (last 24h)")
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
    $outFile   = Resolve-DiagOutput -Prefix 'OSS-eventlog' -Timestamp $timestamp -OutputDir $OutputDir -ClientName $ClientName

    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Event log errors saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
