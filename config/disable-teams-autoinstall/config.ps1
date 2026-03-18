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
