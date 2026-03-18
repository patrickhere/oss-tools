# diag.ps1
# Dumps active network adapter info in a readable format and saves to desktop

param([string]$ClientName = "")

Write-Host "  BankOnIT OSS | Network Info" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

try {
    $output = [System.Collections.Generic.List[string]]::new()

    $output.Add("BankOnIT OSS | Network Info")
    $output.Add("patrick hart - hartforge.dev")
    $output.Add("Generated: $(Get-Date)")
    $output.Add("Machine: $env:COMPUTERNAME")
    $output.Add("")

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Sort-Object InterfaceIndex

    if (!$adapters) {
        $output.Add("no active network adapters found")
    }

    foreach ($adapter in $adapters) {
        $output.Add("=== $($adapter.Name) ($($adapter.InterfaceDescription)) ===")
        $output.Add("  MAC:    $($adapter.MacAddress)")
        $output.Add("  Speed:  $([math]::Round($adapter.LinkSpeed / 1MB)) Mbps")

        $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue

        $ipv4 = $ipConfig.IPv4Address
        if ($ipv4) {
            $output.Add("  IP:     $($ipv4.IPAddress) / $($ipv4.PrefixLength)")
        }

        $gw = $ipConfig.IPv4DefaultGateway
        if ($gw) {
            $output.Add("  GW:     $($gw.NextHop)")
        }

        $dns = $ipConfig.DNSServer | Where-Object { $_.AddressFamily -eq 2 }
        if ($dns) {
            $output.Add("  DNS:    $($dns.ServerAddresses -join ', ')")
        }

        # DHCP info
        $dhcp = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($dhcp) {
            $isDhcp = ($dhcp.PrefixOrigin -eq "Dhcp")
            $output.Add("  DHCP:   $(if ($isDhcp) { 'yes' } else { 'no (static)' })")

            if ($isDhcp) {
                $dhcpDetail = Get-DhcpServerInDC -ErrorAction SilentlyContinue
                $netInfo = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 |
                    Select-Object -First 1
                if ($netInfo.ValidLifetime) {
                    $expires = (Get-Date).Add($netInfo.ValidLifetime)
                    $output.Add("  Lease:  expires $($expires.ToString('yyyy-MM-dd HH:mm'))")
                }
            }
        }

        $output.Add("")
    }

    # Also show the DNS suffix search list
    $suffixes = (Get-DnsClient | Select-Object -First 1).ConnectionSpecificSuffix
    $globalSuffixes = (Get-DnsClientGlobalSetting).SuffixSearchList
    if ($globalSuffixes) {
        $output.Add("DNS search suffixes: $($globalSuffixes -join ', ')")
        $output.Add("")
    }

    # Print everything to screen too
    $output | ForEach-Object { Write-Host $_ }

    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $slug      = if ($ClientName) { "-$($ClientName -replace '[^a-zA-Z0-9\-]','-')" } else { "" }
    $desktop   = [Environment]::GetFolderPath("Desktop")
    $outFile   = "$desktop\OSS-network$slug-$timestamp.txt"

    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Network info saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
