@{
    # PSScriptAnalyzer settings for windows/, identity/, virtualization/ and cloud/ (Invoke-ScriptAnalyzer -Settings ./PSScriptAnalyzerSettings.psd1)
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'   # interactive operator scripts print coloured status lines on purpose
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1', '7.4') }
    }
}
