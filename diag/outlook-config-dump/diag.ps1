# diag.ps1
# Exports Outlook-related registry keys to a text file on the desktop

Write-Host "  BankOnIT OSS | Outlook Config Dump" -ForegroundColor DarkGray
Write-Host "  patrick hart - hartforge.dev" -ForegroundColor DarkGray

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $output    = [System.Collections.Generic.List[string]]::new()

    $output.Add("BankOnIT OSS | Outlook Config Dump")
    $output.Add("patrick hart - hartforge.dev")
    $output.Add("Generated: $(Get-Date)")
    $output.Add("User: $env:USERDOMAIN\$env:USERNAME")
    $output.Add("")

    $keys = @(
        "HKCU:\Software\Microsoft\Office\16.0\Outlook",
        "HKLM:\Software\Policies\Microsoft\Office\16.0\Outlook",
        "HKLM:\Software\Microsoft\Office\16.0\Common\Identity",
        "HKLM:\Software\Policies\Microsoft\Windows\WorkplaceJoin",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Teams"
    )

    foreach ($key in $keys) {
        $output.Add("=== $key ===")

        if (!(Test-Path $key)) {
            $output.Add("  (key not found)")
            $output.Add("")
            continue
        }

        # Top-level values
        $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($props) {
            $props.PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS' } |
                ForEach-Object { $output.Add("  $($_.Name) = $($_.Value)") }
        }

        # One level of subkeys
        Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
            $output.Add("")
            $output.Add("  [$($_.PSChildName)]")
            $sub = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($sub) {
                $sub.PSObject.Properties |
                    Where-Object { $_.Name -notmatch '^PS' } |
                    ForEach-Object { $output.Add("    $($_.Name) = $($_.Value)") }
            }
        }

        $output.Add("")
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    $outFile = "$desktop\OSS-outlook-config-$timestamp.txt"
    $output | Out-File $outFile -Encoding UTF8

    Write-Host ""
    Write-Host "SUCCESS: Config dump saved to $outFile" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Press Enter to close"
