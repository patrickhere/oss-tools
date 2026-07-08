# fix.ps1
# Configures Outlook autodiscover registry keys for on-prem, M365, or hybrid

param(
    [ValidateSet('onprem','m365','hybrid')][string]$Environment = "onprem",
    [switch]$NonInteractive
)

Write-Host "  Navanta OSS | Outlook Autodiscover Fix" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (Test-Path $_upd) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    exit 1
}

Write-Host ""
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
