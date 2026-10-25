#Requires -Version 7.4
<#
.SYNOPSIS
    Repository PowerShell quality gate: parse check, PSScriptAnalyzer and Pester for every .ps1/.psm1/.psd1.
.DESCRIPTION
    Used by CI (.github/workflows/ci.yml) and locally. Exits 1 on any parse error, analyzer finding
    (Error/Warning per PSScriptAnalyzerSettings.psd1) or failed test.
.EXAMPLE
    pwsh -File tools/Invoke-PowerShellLint.ps1
#>
[CmdletBinding()]
param([string[]]$Path = @('windows', 'identity', 'virtualization', 'cloud'))
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
$dirs = @($Path | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ })
$files = @($dirs | ForEach-Object { Get-ChildItem $_ -Recurse -Include *.ps1, *.psm1, *.psd1 -File })
$failed = 0

foreach ($f in $files) {
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    foreach ($e in @($errors)) { Write-Host "PARSE  $($f.FullName):$($e.Extent.StartLineNumber) $($e.Message)"; $failed++ }
}
$findings = @(foreach ($d in $dirs) { Invoke-ScriptAnalyzer -Path $d -Recurse -Settings $settings })
foreach ($x in $findings) { Write-Host "LINT   $($x.ScriptPath):$($x.Line) [$($x.Severity)] $($x.RuleName): $($x.Message)"; $failed++ }

$tests = @($dirs | ForEach-Object { Get-ChildItem $_ -Recurse -Filter *.Tests.ps1 -File })
$passed = 0
if ($tests) {
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = @($tests.FullName)
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Normal'
    $result = Invoke-Pester -Configuration $cfg
    $passed = $result.PassedCount
    $failed += $result.FailedCount
}
Write-Host "`n$($files.Count) PowerShell files: $(@($findings).Count) analyzer finding(s), $passed test(s) passed"
Write-Host "$($files.Count + $passed - $failed) passed, $failed failed"
exit ([int]($failed -gt 0))
