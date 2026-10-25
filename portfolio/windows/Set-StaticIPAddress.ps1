#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure a static IPv4 address, gateway, DNS servers and DNS suffix on a Windows adapter, with
    automatic rollback if the gateway stops answering.
.DESCRIPTION
    Prompts for anything not supplied (adapter, IP address, prefix length, gateway, DNS servers,
    connection-specific DNS suffix), validates that the gateway is inside the subnet and the address is a
    usable host, saves the current settings, applies the new ones and tests the gateway. If the gateway does
    not answer, the previous configuration (static or DHCP) is restored.
.EXAMPLE
    .\Set-StaticIPAddress.ps1
    Interactive.
.EXAMPLE
    .\Set-StaticIPAddress.ps1 -InterfaceAlias Ethernet0 -IPAddress 10.20.3.30 -PrefixLength 25 `
        -DefaultGateway 10.20.3.1 -DnsServers 10.20.3.21,10.20.3.22 -DnsSuffix corp.example
.EXAMPLE
    .\Set-StaticIPAddress.ps1 -InterfaceAlias Ethernet0 -IPAddress 10.20.3.30 -PrefixLength 25 -DefaultGateway 10.20.3.1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$InterfaceAlias,
    [string]$IPAddress,
    [ValidateRange(8, 32)][int]$PrefixLength,
    [string]$DefaultGateway,
    [string[]]$DnsServers,
    [string]$DnsSuffix,
    [switch]$SkipRollback
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\NetTools\NetTools.psd1') -Force

# ---------------------------------------------------------------- gather input
$adapters = @(Get-NetAdapter -Physical | Where-Object Status -EQ 'Up')
if (-not $InterfaceAlias) {
    $adapters | Format-Table -AutoSize Name, InterfaceDescription, MacAddress, LinkSpeed | Out-Host
    $default = if ($adapters.Count -eq 1) { $adapters[0].Name } else { $null }
    $InterfaceAlias = Read-ValidatedInput -Prompt 'Adapter name' -Default $default -Validate { [bool](Get-NetAdapter -Name $_ -ErrorAction SilentlyContinue) }
}
$adapter = Get-NetAdapter -Name $InterfaceAlias
$current = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
$currentIp = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
if (-not $IPAddress) {
    $IPAddress = Read-ValidatedInput -Prompt 'IPv4 address' -Default ($currentIp | Select-Object -First 1).IPAddress -Validate { Test-IPv4Address $_ }
}
if (-not $PrefixLength) {
    $answer = Read-ValidatedInput -Prompt 'Prefix length (e.g. 24) or subnet mask (e.g. 255.255.255.0)' -Default '24' -Validate {
        if ($_ -match '^\d{1,2}$') { [int]$_ -ge 8 -and [int]$_ -le 32 }
        elseif (Test-IPv4Address $_) { try { $null = ConvertTo-PrefixLength $_; $true } catch { $false } }
        else { $false }
    }
    $PrefixLength = if ($answer -match '\.') { ConvertTo-PrefixLength $answer } else { [int]$answer }
}
$net = Get-IPv4NetworkInfo -Address $IPAddress -PrefixLength $PrefixLength
if (-not $net.IsHostAddress) { throw "$IPAddress is the network or broadcast address of $($net.Network)/$PrefixLength" }
if (-not $DefaultGateway) {
    $gwDefault = if ($current.IPv4DefaultGateway) { $current.IPv4DefaultGateway.NextHop } else { $net.FirstUsable }
    $DefaultGateway = Read-ValidatedInput -Prompt 'Default gateway' -Default $gwDefault -Validate {
        (Test-IPv4Address $_) -and (Test-IPv4SameSubnet $_ $IPAddress $PrefixLength) -and $_ -ne $IPAddress
    } -ErrorMessage "The gateway must be an address in $($net.Network)/$PrefixLength other than $IPAddress."
} elseif (-not (Test-IPv4SameSubnet $DefaultGateway $IPAddress $PrefixLength)) {
    throw "Gateway $DefaultGateway is not inside $($net.Network)/$PrefixLength"
}
if (-not $DnsServers) {
    $dnsDefault = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses -join ','
    $DnsServers = (Read-ValidatedInput -Prompt 'DNS servers (comma separated)' -Default $dnsDefault -Validate {
        @($_ -split '\s*,\s*' | Where-Object { -not (Test-IPv4Address $_) }).Count -eq 0
    }) -split '\s*,\s*'
}
foreach ($d in $DnsServers) { if (-not (Test-IPv4Address $d)) { throw "Invalid DNS server: $d" } }
if (-not $PSBoundParameters.ContainsKey('DnsSuffix')) {
    $DnsSuffix = Read-Host -Prompt 'Connection-specific DNS suffix (e.g. corp.example, blank for none)'
}

Write-Host ("`nPlan for {0}: {1}/{2} (mask {3}), gateway {4}, DNS {5}, suffix '{6}'" -f $InterfaceAlias, $IPAddress,
    $PrefixLength, $net.SubnetMask, $DefaultGateway, ($DnsServers -join ', '), $DnsSuffix)
if (-not $PSCmdlet.ShouldProcess($InterfaceAlias, "Set static IPv4 $IPAddress/$PrefixLength")) { return }

# ---------------------------------------------------------------- save, apply, verify
$saved = [pscustomobject]@{
    Dhcp     = (Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).Dhcp
    Address  = $currentIp | Where-Object PrefixOrigin -NE 'WellKnown' | Select-Object IPAddress, PrefixLength
    Gateway  = if ($current.IPv4DefaultGateway) { $current.IPv4DefaultGateway.NextHop } else { $null }
    Dns      = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses
    Suffix   = (Get-DnsClient -InterfaceIndex $adapter.ifIndex).ConnectionSpecificSuffix
}
$backup = Join-Path $env:ProgramData "StaticIP\$InterfaceAlias-$(Get-Date -Format yyyyMMdd-HHmmss).json"
New-Item -ItemType Directory -Force -Path (Split-Path $backup) | Out-Null
$saved | ConvertTo-Json -Depth 4 | Set-Content -Path $backup -Encoding UTF8
Write-Verbose "Previous configuration saved to $backup"

function Clear-AdapterIPv4([int]$Index) {
    Set-NetIPInterface -InterfaceIndex $Index -Dhcp Disabled
    Get-NetIPAddress -InterfaceIndex $Index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
    Get-NetRoute -InterfaceIndex $Index -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false
}

Clear-AdapterIPv4 $adapter.ifIndex
New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $DefaultGateway | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DnsServers
Set-DnsClient -InterfaceIndex $adapter.ifIndex -ConnectionSpecificSuffix $DnsSuffix -RegisterThisConnectionsAddress $true
Start-Sleep -Seconds 3

$ok = Test-Connection -ComputerName $DefaultGateway -Count 3 -Quiet
if ($ok -or $SkipRollback) {
    Write-Host "Gateway $DefaultGateway answers. Static configuration applied (backup: $backup)." -ForegroundColor Green
    Register-DnsClient -ErrorAction SilentlyContinue
    return
}

Write-Warning "Gateway $DefaultGateway did not answer: restoring the previous configuration."
Clear-AdapterIPv4 $adapter.ifIndex
if ($saved.Dhcp -eq 'Enabled') {
    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -Dhcp Enabled
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses
} else {
    foreach ($a in @($saved.Address)) {
        $params = @{ InterfaceIndex = $adapter.ifIndex; IPAddress = $a.IPAddress; PrefixLength = $a.PrefixLength }
        if ($saved.Gateway) { $params.DefaultGateway = $saved.Gateway; $saved.Gateway = $null }
        New-NetIPAddress @params | Out-Null
    }
    if ($saved.Dns) { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $saved.Dns }
}
Set-DnsClient -InterfaceIndex $adapter.ifIndex -ConnectionSpecificSuffix $saved.Suffix
throw "Rolled back to the previous configuration (saved in $backup)."
