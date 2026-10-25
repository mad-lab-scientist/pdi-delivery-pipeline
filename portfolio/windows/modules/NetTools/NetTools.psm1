#Requires -Version 5.1
<#
.SYNOPSIS
    IPv4 helpers shared by the Windows and identity scripts (subnet math and input validation).
.DESCRIPTION
    Pure functions with no OS dependencies, so they run on Windows PowerShell 5.1 and PowerShell 7 on
    any platform and are covered by Pester tests (Tests\NetTools.Tests.ps1).
#>
Set-StrictMode -Version Latest

function Test-IPv4Address {
    <# .SYNOPSIS True when the string is a dotted-quad IPv4 address (no leading zeros, each octet 0-255). #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Address)
    process {
        if ($Address -notmatch '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') { return $false }
        foreach ($octet in $Matches[1..4]) {
            if ([int]$octet -gt 255 -or ($octet.Length -gt 1 -and $octet.StartsWith('0'))) { return $false }
        }
        return $true
    }
}

function ConvertTo-IPv4UInt32 {
    [CmdletBinding()]
    [OutputType([uint32])]
    param([Parameter(Mandatory)][string]$Address)
    if (-not (Test-IPv4Address $Address)) { throw "Not an IPv4 address: $Address" }
    $o = $Address.Split('.') | ForEach-Object { [uint32]$_ }
    return [uint32](($o[0] -shl 24) + ($o[1] -shl 16) + ($o[2] -shl 8) + $o[3])
}

function ConvertFrom-IPv4UInt32 {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][uint32]$Value)
    return '{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255)
}

function ConvertTo-SubnetMask {
    <# .SYNOPSIS 24 -> 255.255.255.0 #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][ValidateRange(0, 32)][int]$PrefixLength)
    if ($PrefixLength -eq 0) { return '0.0.0.0' }
    $mask = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $PrefixLength))
    return ConvertFrom-IPv4UInt32 $mask
}

function ConvertTo-PrefixLength {
    <# .SYNOPSIS 255.255.255.128 -> 25 (rejects non-contiguous masks). #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$SubnetMask)
    $value = ConvertTo-IPv4UInt32 $SubnetMask
    $bits = [Convert]::ToString([int64]$value, 2).PadLeft(32, '0')
    if ($bits -notmatch '^1*0*$') { throw "Not a contiguous subnet mask: $SubnetMask" }
    return [regex]::Matches($bits, '1').Count
}

function Get-IPv4NetworkInfo {
    <#
    .SYNOPSIS
        Network, broadcast, usable range and host count for an address and prefix.
    .EXAMPLE
        Get-IPv4NetworkInfo -Address 10.20.3.10 -PrefixLength 25
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Address,
        [Parameter(Mandatory)][ValidateRange(0, 32)][int]$PrefixLength
    )
    $ip = ConvertTo-IPv4UInt32 $Address
    $mask = ConvertTo-IPv4UInt32 (ConvertTo-SubnetMask $PrefixLength)
    $network = [uint32]($ip -band $mask)
    $broadcast = [uint32]($network + ([math]::Pow(2, 32 - $PrefixLength) - 1))
    if ($PrefixLength -ge 31) {
        $first = $network; $last = $broadcast; $hosts = [math]::Pow(2, 32 - $PrefixLength)
    } else {
        $first = $network + 1; $last = $broadcast - 1; $hosts = [math]::Pow(2, 32 - $PrefixLength) - 2
    }
    [pscustomobject]@{
        Address      = $Address
        PrefixLength = $PrefixLength
        SubnetMask   = ConvertTo-SubnetMask $PrefixLength
        Network      = ConvertFrom-IPv4UInt32 $network
        Broadcast    = ConvertFrom-IPv4UInt32 $broadcast
        FirstUsable  = ConvertFrom-IPv4UInt32 ([uint32]$first)
        LastUsable   = ConvertFrom-IPv4UInt32 ([uint32]$last)
        UsableHosts  = [int64]$hosts
        IsHostAddress = ($PrefixLength -ge 31) -or ($ip -ne $network -and $ip -ne $broadcast)
    }
}

function Test-IPv4SameSubnet {
    <# .SYNOPSIS True when both addresses fall in the same subnet for the given prefix. #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Address,
        [Parameter(Mandatory)][string]$OtherAddress,
        [Parameter(Mandatory)][ValidateRange(0, 32)][int]$PrefixLength
    )
    $mask = ConvertTo-IPv4UInt32 (ConvertTo-SubnetMask $PrefixLength)
    return ((ConvertTo-IPv4UInt32 $Address) -band $mask) -eq ((ConvertTo-IPv4UInt32 $OtherAddress) -band $mask)
}

function Read-ValidatedInput {
    <#
    .SYNOPSIS
        Prompt until the answer passes a validation scriptblock (used by the interactive scripts).
    .EXAMPLE
        Read-ValidatedInput -Prompt 'Default gateway' -Validate { Test-IPv4Address $_ }
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default,
        [scriptblock]$Validate = { $true },
        [string]$ErrorMessage = 'Invalid value, try again.'
    )
    while ($true) {
        $label = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
        $answer = Read-Host -Prompt $label
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        if (-not [string]::IsNullOrWhiteSpace($answer) -and ($answer | ForEach-Object $Validate)) { return $answer.Trim() }
        Write-Warning $ErrorMessage
    }
}

Export-ModuleMember -Function Test-IPv4Address, ConvertTo-IPv4UInt32, ConvertFrom-IPv4UInt32, ConvertTo-SubnetMask,
    ConvertTo-PrefixLength, Get-IPv4NetworkInfo, Test-IPv4SameSubnet, Read-ValidatedInput
