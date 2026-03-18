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
