#Requires -Version 7
<#
.SYNOPSIS
    Run all Pester tests for oss-tools helper modules.
    Usage: pwsh -File tests/run-tests.ps1
#>

$config = New-PesterConfiguration
$config.Run.Path      = $PSScriptRoot
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled    = $true
$config.TestResult.OutputPath = (Join-Path $PSScriptRoot 'results.xml')

$result = Invoke-Pester -Configuration $config

exit $result.FailedCount
