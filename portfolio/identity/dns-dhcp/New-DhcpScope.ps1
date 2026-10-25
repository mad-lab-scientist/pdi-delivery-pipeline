#Requires -Version 5.1
#Requires -Modules DhcpServer
<#
.SYNOPSIS
    Create a Windows DHCP scope with router, DNS and domain options, exclusions and optional failover.
.DESCRIPTION
    Prompts for anything not supplied: scope name, network and prefix (or mask), pool start/end, default
    gateway (option 3), DNS servers (option 6), DNS domain (option 15), lease duration and exclusions.
    Everything is validated against the subnet before any change (pool inside the subnet, gateway inside the
    subnet and outside the pool). Authorizes the server in AD if needed, and can add the scope to an existing
    failover relationship (load balance or hot standby).
.EXAMPLE
    .\New-DhcpScope.ps1
.EXAMPLE
    .\New-DhcpScope.ps1 -Name 'VLAN30 Users' -Network 10.20.0.0 -PrefixLength 23 -StartRange 10.20.0.50 `
        -EndRange 10.20.1.240 -Router 10.20.0.1 -DnsServers 10.20.3.21,10.20.3.22 -DnsDomain corp.example.com `
        -LeaseDays 8 -Exclusions '10.20.0.50-10.20.0.60' -FailoverRelationship 'dhcp01-dhcp02'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name,
    [string]$Network,
    [ValidateRange(8, 30)][int]$PrefixLength,
    [string]$StartRange,
    [string]$EndRange,
    [string]$Router,
    [string[]]$DnsServers,
    [string]$DnsDomain,
    [ValidateRange(1, 365)][int]$LeaseDays = 8,
    [string[]]$Exclusions = @(),
    [string]$FailoverRelationship,
    [string]$ComputerName = $env:COMPUTERNAME
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\windows\modules\NetTools\NetTools.psd1') -Force

$isIp = { Test-IPv4Address $_ }
if (-not $Name) { $Name = Read-ValidatedInput -Prompt 'Scope name (e.g. VLAN30 Users)' }
if (-not $Network) { $Network = Read-ValidatedInput -Prompt 'Network address (e.g. 10.20.0.0)' -Validate $isIp }
if (-not $PrefixLength) {
    $p = Read-ValidatedInput -Prompt 'Prefix length (e.g. 24) or subnet mask' -Default '24' -Validate {
        ($_ -match '^\d{1,2}$' -and [int]$_ -ge 8 -and [int]$_ -le 30) -or (Test-IPv4Address $_)
    }
    $PrefixLength = if ($p -match '\.') { ConvertTo-PrefixLength $p } else { [int]$p }
}
$info = Get-IPv4NetworkInfo -Address $Network -PrefixLength $PrefixLength
if ($info.Network -ne $Network) { throw "$Network is not the network address of /$PrefixLength (did you mean $($info.Network)?)" }
$inSubnet = { (Test-IPv4Address $_) -and (Test-IPv4SameSubnet $_ $Network $PrefixLength) -and $_ -ne $info.Network -and $_ -ne $info.Broadcast }
if (-not $Router) { $Router = Read-ValidatedInput -Prompt 'Default gateway (option 3)' -Default $info.FirstUsable -Validate $inSubnet }
if (-not $StartRange) { $StartRange = Read-ValidatedInput -Prompt 'Pool start' -Default (ConvertFrom-IPv4UInt32 ((ConvertTo-IPv4UInt32 $info.FirstUsable) + 49)) -Validate $inSubnet }
if (-not $EndRange) { $EndRange = Read-ValidatedInput -Prompt 'Pool end' -Default (ConvertFrom-IPv4UInt32 ((ConvertTo-IPv4UInt32 $info.LastUsable) - 10)) -Validate $inSubnet }
if (-not $DnsServers) { $DnsServers = (Read-ValidatedInput -Prompt 'DNS servers (option 6, comma separated)' -Validate { @($_ -split '\s*,\s*' | Where-Object { -not (Test-IPv4Address $_) }).Count -eq 0 }) -split '\s*,\s*' }
if (-not $PSBoundParameters.ContainsKey('DnsDomain')) { $DnsDomain = Read-Host 'DNS domain name (option 15, e.g. corp.example.com)' }

foreach ($a in $StartRange, $EndRange, $Router) { if (-not ($a | ForEach-Object $inSubnet)) { throw "$a is not a usable address in $Network/$PrefixLength" } }
$start = ConvertTo-IPv4UInt32 $StartRange; $end = ConvertTo-IPv4UInt32 $EndRange; $gw = ConvertTo-IPv4UInt32 $Router
if ($start -gt $end) { throw 'Pool start is after pool end' }
if ($gw -ge $start -and $gw -le $end) { throw "Gateway $Router is inside the pool; exclude it or move the pool" }
foreach ($ex in $Exclusions) {
    $lo, $hi = $ex -split '-'
    if (-not $hi) { $hi = $lo }
    foreach ($x in $lo, $hi) { if (-not (Test-IPv4Address $x) -or (ConvertTo-IPv4UInt32 $x) -lt $start -or (ConvertTo-IPv4UInt32 $x) -gt $end) { throw "Exclusion $ex is outside the pool" } }
}

$cim = @{ ComputerName = $ComputerName }
if (Get-DhcpServerv4Scope @cim -ScopeId $Network -ErrorAction SilentlyContinue) { throw "Scope $Network already exists on $ComputerName" }
Write-Host ("`nScope '{0}' {1}/{2} pool {3}-{4} gw {5} dns {6} domain '{7}' lease {8}d" -f $Name, $Network, $PrefixLength, $StartRange, $EndRange, $Router, ($DnsServers -join ','), $DnsDomain, $LeaseDays)
if (-not $PSCmdlet.ShouldProcess("$ComputerName scope $Network/$PrefixLength", 'Create DHCP scope')) { return }

$fqdn = [System.Net.Dns]::GetHostEntry($ComputerName).HostName
if (-not (Get-DhcpServerInDC | Where-Object DnsName -EQ $fqdn)) { Add-DhcpServerInDC -DnsName $fqdn; Write-Host "Authorized $fqdn in Active Directory" }
Add-DhcpServerv4Scope @cim -Name $Name -StartRange $StartRange -EndRange $EndRange -SubnetMask $info.SubnetMask -LeaseDuration (New-TimeSpan -Days $LeaseDays) -State InActive
$options = @{ ScopeId = $Network; Router = $Router; DnsServer = $DnsServers }
if ($DnsDomain) { $options.DnsDomain = $DnsDomain }
Set-DhcpServerv4OptionValue @cim @options
foreach ($ex in $Exclusions) {
    $lo, $hi = $ex -split '-'
    Add-DhcpServerv4ExclusionRange @cim -ScopeId $Network -StartRange $lo -EndRange $(if ($hi) { $hi } else { $lo })
}
if ($FailoverRelationship) { Add-DhcpServerv4FailoverScope @cim -Name $FailoverRelationship -ScopeId $Network }
Set-DhcpServerv4Scope @cim -ScopeId $Network -State Active
Get-DhcpServerv4Scope @cim -ScopeId $Network | Format-List ScopeId, Name, SubnetMask, StartRange, EndRange, LeaseDuration, State
