# diag.ps1
# Tests Exchange/M365 connectivity based on the selected environment

param([string]$Environment = "onprem", [string]$ClientName = "")

Write-Host "  BankOnIT OSS | Exchange Connectivity" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  environment: $Environment" -ForegroundColor DarkGray

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $output    = [System.Collections.Generic.List[string]]::new()

    $output.Add("BankOnIT OSS | Exchange Connectivity")
    $output.Add("patrick hart - hartforge.dev")
    $output.Add("Generated: $(Get-Date)")
    $output.Add("Environment: $Environment")
    $output.Add("")

    function Test-Port {
        param([string]$Host, [int]$Port)
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $conn = $tcp.BeginConnect($Host, $Port, $null, $null)
            $wait = $conn.AsyncWaitHandle.WaitOne(3000, $false)
            if ($wait -and !$tcp.Client.Connected) { return $false }
            $tcp.EndConnect($conn)
            $tcp.Close()
            return $wait
        }
        catch { return $false }
    }

    function Write-Result {
        param([string]$Label, [bool]$OK, [string]$Detail = "")
        $status = if ($OK) { "OK  " } else { "FAIL" }
        $color  = if ($OK) { "Green" } else { "Red" }
        $line   = "  [$status] $Label"
        if ($Detail) { $line += " -- $Detail" }
        Write-Host $line -ForegroundColor $color
        return $line
    }

    # On-prem checks
    if ($Environment -eq "onprem" -or $Environment -eq "hybrid") {
        $output.Add("=== On-Premises ===")
        Write-Host ""
        Write-Host "on-premises checks:" -ForegroundColor Yellow

        # DC reachability via nltest
        $nltest = nltest /dsgetdc: 2>&1
        $dcOk   = ($LASTEXITCODE -eq 0)
        $dcName = if ($dcOk) { ($nltest | Select-String "DC:").ToString().Trim() } else { "unreachable" }
        $output.Add((Write-Result "Domain Controller" $dcOk $dcName))

        # Autodiscover DNS
        $domain = $env:USERDNSDOMAIN
        if ($domain) {
            try {
                $adDns = [System.Net.Dns]::GetHostAddresses("autodiscover.$domain")
                $output.Add((Write-Result "autodiscover.$domain DNS" $true $adDns[0].IPAddressToString))
            }
            catch {
                $output.Add((Write-Result "autodiscover.$domain DNS" $false "no DNS record"))
            }
        }
        else {
            $output.Add((Write-Result "Autodiscover DNS" $false "USERDNSDOMAIN not set"))
        }

        $output.Add("")
    }

    # M365 checks
    if ($Environment -eq "m365" -or $Environment -eq "hybrid") {
        $output.Add("=== Microsoft 365 ===")
        Write-Host ""
        Write-Host "microsoft 365 checks:" -ForegroundColor Yellow

        $m365Endpoints = @(
            @{ Host = "outlook.office365.com"; Port = 443 },
            @{ Host = "login.microsoftonline.com"; Port = 443 },
            @{ Host = "graph.microsoft.com"; Port = 443 },
            @{ Host = "autodiscover-s.outlook.com"; Port = 443 }
        )

        foreach ($ep in $m365Endpoints) {
            $ok = Test-Port $ep.Host $ep.Port
            $output.Add((Write-Result "$($ep.Host):$($ep.Port)" $ok))
        }

        $output.Add("")
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    $slug    = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { "" }
    $outFile = "$desktop\OSS-connectivity$slug-$timestamp.txt"
    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Results saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
