# config.ps1
# Enables IE mode in Edge and manages a local site list

param([switch]$NonInteractive)

Write-Host "  BankOnIT OSS | Edge IE Mode Sites" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
# update check -- silent if server is unreachable
$_upd = Join-Path $PSScriptRoot "..\..\.\update.ps1"
if (Test-Path $_upd) { powershell -ExecutionPolicy Bypass -File $_upd; if ($LASTEXITCODE -eq 2) { exit 0 } }


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

# In non-interactive mode, policy is already set above -- just report and exit
if ($NonInteractive) {
    Write-Host ""
    Write-Host "SUCCESS: IE mode policy set. Run interactively to manage site list." -ForegroundColor Green
    exit 0
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
        # Always save on quit so the policy-referenced file exists even if no sites were added
        Save-SiteList $xml
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
if (-not $NonInteractive) { Read-Host "Press Enter to close" }
