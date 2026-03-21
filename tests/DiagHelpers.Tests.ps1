#Requires -Version 7
<#
.SYNOPSIS
    Pester tests for diag/lib/DiagHelpers.ps1
    Tests Invoke-UpdateCheck and Resolve-DiagOutput.
#>

BeforeAll {
    $HelpersPath = Resolve-Path "$PSScriptRoot\..\diag\lib\DiagHelpers.ps1"
    . $HelpersPath
}

Describe 'Invoke-UpdateCheck' {
    It 'does nothing when OSSMANAGED is 1' {
        $env:OSSMANAGED = '1'
        # If the early-return works, Test-Path is never called (and powershell never spawned)
        # On macOS, powershell doesn't exist -- if the guard fails the test throws automatically
        { Invoke-UpdateCheck } | Should -Not -Throw
        $env:OSSMANAGED = $null
    }

    It 'skips update script when file does not exist' {
        $env:OSSMANAGED = $null
        # $PSScriptRoot points somewhere without update.ps1 -- Test-Path returns false, nothing runs
        Mock Test-Path { return $false }
        { Invoke-UpdateCheck } | Should -Not -Throw
    }
}

Describe 'Resolve-DiagOutput' {
    It 'returns a path ending with the expected filename pattern' {
        $result = Resolve-DiagOutput -Prefix 'OSS-snapshot' -Timestamp '2026-01-01_1200' -OutputDir $TestDrive -ClientName 'Acme-Downtown'

        $result | Should -Match 'OSS-snapshot-Acme-Downtown-2026-01-01_1200\.txt$'
    }

    It 'sanitizes special characters in ClientName' {
        $result   = Resolve-DiagOutput -Prefix 'OSS-test' -Timestamp '2026-01-01_1200' -OutputDir $TestDrive -ClientName 'First National/Branch #1'
        $filename = Split-Path $result -Leaf

        # Only alphanumeric and hyphens allowed in the filename slug
        $filename | Should -Not -Match '[/#]'
        $filename | Should -Match '^OSS-test-'
    }

    It 'omits slug when ClientName is empty' {
        $result = Resolve-DiagOutput -Prefix 'OSS-snapshot' -Timestamp '2026-01-01_1200' -OutputDir $TestDrive -ClientName ''

        $result | Should -Match 'OSS-snapshot-2026-01-01_1200\.txt$'
        $result | Should -Not -Match 'OSS-snapshot--'
    }

    It 'creates OutputDir if it does not exist' {
        $newDir = Join-Path $TestDrive 'newsubdir'
        $newDir | Should -Not -Exist

        Resolve-DiagOutput -Prefix 'OSS-test' -Timestamp '2026-01-01_1200' -OutputDir $newDir -ClientName '' | Out-Null

        $newDir | Should -Exist
    }

    It 'uses Desktop when OutputDir is empty' {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $result  = Resolve-DiagOutput -Prefix 'OSS-test' -Timestamp '2026-01-01_1200' -OutputDir '' -ClientName ''

        $result | Should -Match ([regex]::Escape($desktop))
    }

    It 'puts the output file inside the specified OutputDir' {
        $result = Resolve-DiagOutput -Prefix 'OSS-test' -Timestamp '2026-01-01_1200' -OutputDir $TestDrive -ClientName 'Acme'

        $result | Should -Match ([regex]::Escape($TestDrive.ToString()))
    }
}
