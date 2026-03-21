#Requires -Version 7
<#
.SYNOPSIS
    Pester tests for backup-tool/assets/lib/Common.ps1
    Tests Write-Log, Read-Toggle, and Invoke-Robocopy without needing Windows.
#>

BeforeAll {
    $CommonPath = Resolve-Path "$PSScriptRoot\..\backup-tool\assets\lib\Common.ps1"
}

Describe 'Write-Log' {
    BeforeEach {
        # Set up the script-scope variables Write-Log expects
        $script:WarnCount  = 0
        $script:ErrorCount = 0
        $script:Issues     = [System.Collections.Generic.List[string]]::new()
        $script:LogPath    = $null

        . $CommonPath
    }

    It 'increments WarnCount and adds to Issues on WARN' {
        Write-Log 'something went sideways' -Severity WARN 6>&1 | Out-Null

        $script:WarnCount  | Should -Be 1
        $script:ErrorCount | Should -Be 0
        $script:Issues[0]  | Should -Be '[WARN] something went sideways'
    }

    It 'increments ErrorCount and adds to Issues on ERROR' {
        Write-Log 'it exploded' -Severity ERROR 6>&1 | Out-Null

        $script:ErrorCount | Should -Be 1
        $script:WarnCount  | Should -Be 0
        $script:Issues[0]  | Should -Be '[ERROR] it exploded'
    }

    It 'does not increment counts for INFO' {
        Write-Log 'all good' 6>&1 | Out-Null

        $script:WarnCount  | Should -Be 0
        $script:ErrorCount | Should -Be 0
        $script:Issues     | Should -BeNullOrEmpty
    }

    It 'writes to log file when LogPath is set' {
        $logFile = Join-Path $TestDrive 'test.log'
        $script:LogPath = $logFile

        Write-Log 'hello log' 6>&1 | Out-Null

        $logFile | Should -Exist
        Get-Content $logFile | Should -Match '\[INFO\] hello log'
    }

    It 'does not throw when LogPath is null' {
        $script:LogPath = $null
        { Write-Log 'no log file' 6>&1 | Out-Null } | Should -Not -Throw
    }

    It 'output line includes severity tag' {
        $output = Write-Log 'tagged message' -Severity WARN 6>&1
        $output | Should -Match '\[WARN\]'
        $output | Should -Match 'tagged message'
    }
}

Describe 'Read-Toggle' {
    BeforeAll {
        . $CommonPath
    }

    It 'returns true when user presses Enter with default true' {
        Mock Read-Host { return '' }
        $result = Read-Toggle -Prompt 'Continue' -Default $true
        $result | Should -Be $true
    }

    It 'returns false when user presses Enter with default false' {
        Mock Read-Host { return '' }
        $result = Read-Toggle -Prompt 'Continue' -Default $false
        $result | Should -Be $false
    }

    It 'returns true when user types Y' {
        Mock Read-Host { return 'Y' }
        $result = Read-Toggle -Prompt 'Continue' -Default $false
        $result | Should -Be $true
    }

    It 'returns true when user types y (lowercase)' {
        Mock Read-Host { return 'y' }
        $result = Read-Toggle -Prompt 'Continue' -Default $false
        $result | Should -Be $true
    }

    It 'returns false when user types N' {
        Mock Read-Host { return 'N' }
        $result = Read-Toggle -Prompt 'Continue' -Default $true
        $result | Should -Be $false
    }

    It 'retries on invalid input then accepts Y' {
        $script:mockCallCount = 0
        Mock Read-Host {
            $script:mockCallCount++
            if ($script:mockCallCount -eq 1) { return 'garbage' }
            return 'Y'
        }
        $result = Read-Toggle -Prompt 'Continue' -Default $false
        $result                  | Should -Be $true
        $script:mockCallCount    | Should -Be 2
    }
}

Describe 'Invoke-Robocopy' {
    BeforeAll {
        . $CommonPath
        # robocopy is Windows-only; define a stub so Pester can mock it on macOS
        function robocopy { }
    }

    It 'returns ExitCode and Output properties' {
        Mock robocopy { 'mocked output'; $global:LASTEXITCODE = 1 }

        $result = Invoke-Robocopy @('src', 'dst', '/E')

        $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
        $result.PSObject.Properties.Name | Should -Contain 'Output'
    }

    It 'restores ErrorActionPreference after success' {
        $ErrorActionPreference = 'Stop'
        Mock robocopy { $global:LASTEXITCODE = 0 }

        Invoke-Robocopy @('src', 'dst')

        $ErrorActionPreference | Should -Be 'Stop'
    }

    It 'restores ErrorActionPreference even when robocopy throws' {
        $ErrorActionPreference = 'Stop'
        Mock robocopy { throw 'simulated robocopy error' }

        try { Invoke-Robocopy @('src', 'dst') } catch {}

        $ErrorActionPreference | Should -Be 'Stop'
    }

    It 'captures robocopy exit code 0' {
        Mock robocopy { $global:LASTEXITCODE = 0 }
        $result = Invoke-Robocopy @('src', 'dst')
        $result.ExitCode | Should -Be 0
    }

    It 'captures robocopy exit code 8' {
        Mock robocopy { $global:LASTEXITCODE = 8 }
        $result = Invoke-Robocopy @('src', 'dst')
        $result.ExitCode | Should -Be 8
    }
}
