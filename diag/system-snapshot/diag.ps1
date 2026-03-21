# diag.ps1
# Collects OS, domain, Outlook version, and key registry values -- saves to desktop

param([string]$ClientName = "", [string]$OutputDir = "", [switch]$NonInteractive)

. (Join-Path $PSScriptRoot '..\lib\DiagHelpers.ps1')

Write-Host "  BankOnIT OSS | System Snapshot" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
Invoke-UpdateCheck


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

    $outFile = Resolve-DiagOutput -Prefix 'OSS-snapshot' -Timestamp $timestamp -OutputDir $OutputDir -ClientName $ClientName
    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Snapshot saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
