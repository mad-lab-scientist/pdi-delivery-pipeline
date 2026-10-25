@{
    RootModule        = 'NetTools.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5b0d7f63-3f4e-4c2b-9a54-1d8f0e6c2a71'
    Author            = 'Pearson Cyber Defense'
    CompanyName       = 'Pearson Digital Infrastructure LLC'
    Copyright         = '(c) Pearson Digital Infrastructure LLC. All rights reserved.'
    Description       = 'IPv4 subnet math and input validation helpers for infrastructure scripts.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Test-IPv4Address', 'ConvertTo-IPv4UInt32', 'ConvertFrom-IPv4UInt32', 'ConvertTo-SubnetMask',
        'ConvertTo-PrefixLength', 'Get-IPv4NetworkInfo', 'Test-IPv4SameSubnet', 'Read-ValidatedInput')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('Networking', 'IPv4', 'Subnet') } }
}
