#Requires -Version 5.1
#Requires -Modules VMware.VimAutomation.Core
<#
.SYNOPSIS
    Deploy a vSphere VM from a template with guest customization: hostname, static IP, gateway, DNS
    servers and domain (Linux or Windows), on a chosen cluster, datastore and port group.
.DESCRIPTION
    Prompts for any value not supplied, validates the network values (address and gateway in the same
    subnet), builds a non-persistent OS customization specification, clones the template, attaches the NIC
    to the port group, powers on and waits for VMware Tools to report the address. Windows guests join a
    domain when -DomainCredential is given, otherwise a workgroup.
.EXAMPLE
    .\New-VMFromTemplate.ps1 -Server vcenter.corp.example.com
.EXAMPLE
    .\New-VMFromTemplate.ps1 -Server vcenter.corp.example.com -Name app01 -Template tpl-ubuntu-2404 -Cluster Prod `
        -Datastore ds-ssd-01 -PortGroup VLAN30-Servers -IPAddress 10.20.3.40 -PrefixLength 25 -Gateway 10.20.3.1 `
        -DnsServers 10.20.3.21,10.20.3.22 -Domain corp.example.com -CPU 4 -MemoryGB 8
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Server,
    [pscredential]$Credential,
    [ValidatePattern('^[A-Za-z0-9-]{1,15}$')][string]$Name,
    [string]$Template,
    [string]$Cluster,
    [string]$Datastore,
    [string]$PortGroup,
    [string]$IPAddress,
    [ValidateRange(8, 30)][int]$PrefixLength,
    [string]$Gateway,
    [string[]]$DnsServers,
    [string]$Domain,
    [ValidateRange(1, 64)][int]$CPU = 2,
    [ValidateRange(1, 1024)][int]$MemoryGB = 4,
    [ValidateSet('Linux', 'Windows')][string]$GuestOS = 'Linux',
    [securestring]$AdminPassword,
    [pscredential]$DomainCredential
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\windows\modules\NetTools\NetTools.psd1') -Force
$connected = Get-Variable -Name DefaultVIServers -Scope Global -ValueOnly -ErrorAction SilentlyContinue
if (-not ($connected | Where-Object { $_.Name -eq $Server -and $_.IsConnected })) {
    $params = @{ Server = $Server }
    if ($Credential) { $params.Credential = $Credential }
    Connect-VIServer @params | Out-Null
}

function Select-FromList([string]$Prompt, [string[]]$Choices) {
    for ($n = 0; $n -lt $Choices.Count; $n++) { Write-Host ("  {0,2}. {1}" -f ($n + 1), $Choices[$n]) }
    $pick = Read-ValidatedInput -Prompt $Prompt -Validate { $_ -match '^\d+$' -and [int]$_ -ge 1 -and [int]$_ -le $Choices.Count }
    $Choices[[int]$pick - 1]
}
if (-not $Name) { $Name = Read-ValidatedInput -Prompt 'VM name / hostname' -Validate { $_ -match '^[A-Za-z0-9-]{1,15}$' } }
if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "A VM named $Name already exists" }
if (-not $Template) { $Template = Select-FromList 'Template' (Get-Template | Sort-Object Name).Name }
if (-not $Cluster) { $Cluster = Select-FromList 'Cluster' (Get-Cluster | Sort-Object Name).Name }
$clusterObj = Get-Cluster -Name $Cluster
if (-not $Datastore) {
    $ds = $clusterObj | Get-VMHost | Get-Datastore | Sort-Object FreeSpaceGB -Descending | Select-Object -Unique
    $Datastore = Select-FromList 'Datastore' ($ds | ForEach-Object { $_.Name })
}
if (-not $PortGroup) {
    $pgs = @(Get-VDPortgroup -ErrorAction SilentlyContinue).Name + @($clusterObj | Get-VMHost | Get-VirtualPortGroup -Standard -ErrorAction SilentlyContinue).Name | Sort-Object -Unique
    $PortGroup = Select-FromList 'Port group' $pgs
}
if (-not $IPAddress) { $IPAddress = Read-ValidatedInput -Prompt 'IPv4 address' -Validate { Test-IPv4Address $_ } }
if (-not $PrefixLength) { $PrefixLength = [int](Read-ValidatedInput -Prompt 'Prefix length' -Default '24' -Validate { $_ -match '^\d{1,2}$' -and [int]$_ -ge 8 -and [int]$_ -le 30 }) }
$net = Get-IPv4NetworkInfo -Address $IPAddress -PrefixLength $PrefixLength
if (-not $net.IsHostAddress) { throw "$IPAddress is not a usable host address in $($net.Network)/$PrefixLength" }
if (-not $Gateway) { $Gateway = Read-ValidatedInput -Prompt 'Default gateway' -Default $net.FirstUsable -Validate { (Test-IPv4Address $_) -and (Test-IPv4SameSubnet $_ $IPAddress $PrefixLength) } }
if (-not $DnsServers) { $DnsServers = (Read-ValidatedInput -Prompt 'DNS servers (comma separated)' -Validate { @($_ -split '\s*,\s*' | Where-Object { -not (Test-IPv4Address $_) }).Count -eq 0 }) -split '\s*,\s*' }
if (-not $Domain) { $Domain = Read-ValidatedInput -Prompt 'DNS domain (e.g. corp.example.com)' -Validate { $_ -match '^([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$' } }

Write-Host "`n$Name from $Template on $Cluster/$Datastore, $PortGroup, $IPAddress/$PrefixLength gw $Gateway dns $($DnsServers -join ',') domain $Domain, $CPU vCPU, $MemoryGB GB"
if (-not $PSCmdlet.ShouldProcess($Name, 'Deploy VM from template')) { return }

$specName = "tmp-$Name-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
if ($GuestOS -eq 'Linux') {
    $spec = New-OSCustomizationSpec -Name $specName -Type NonPersistent -OSType Linux -Domain $Domain -DnsServer $DnsServers -DnsSuffix $Domain -NamingScheme Fixed -NamingPrefix $Name
} else {
    if (-not $AdminPassword) { $AdminPassword = Read-Host -AsSecureString 'Local Administrator password for the new VM' }
    $plainAdmin = [Net.NetworkCredential]::new('', $AdminPassword).Password
    $winParams = @{ Name = $specName; Type = 'NonPersistent'; OSType = 'Windows'; FullName = 'IT'; OrgName = $Domain; NamingScheme = 'Fixed'
                    NamingPrefix = $Name; AdminPassword = $plainAdmin; ChangeSid = $true; TimeZone = 'Central Standard Time' }
    if ($DomainCredential) { $winParams.Domain = $Domain; $winParams.DomainCredentials = $DomainCredential } else { $winParams.Workgroup = 'WORKGROUP' }
    $spec = New-OSCustomizationSpec @winParams
}
$nicParams = @{ IpMode = 'UseStaticIP'; IpAddress = $IPAddress; SubnetMask = $net.SubnetMask; DefaultGateway = $Gateway }
if ($GuestOS -eq 'Windows') { $nicParams.Dns = $DnsServers }
$spec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping @nicParams | Out-Null

try {
    $vmHost = $clusterObj | Get-VMHost | Where-Object ConnectionState -EQ 'Connected' | Sort-Object { $_.MemoryUsageGB / $_.MemoryTotalGB } | Select-Object -First 1
    $vm = New-VM -Name $Name -Template (Get-Template -Name $Template) -VMHost $vmHost -Datastore $Datastore -OSCustomizationSpec $spec
    $vm = Set-VM -VM $vm -NumCpu $CPU -MemoryGB $MemoryGB -Confirm:$false
    $vm | Get-NetworkAdapter | Select-Object -First 1 | Set-NetworkAdapter -Portgroup $PortGroup -StartConnected $true -Confirm:$false | Out-Null
    Start-VM -VM $vm | Out-Null
    Write-Host 'Powered on; waiting for guest customization and VMware Tools (up to 15 minutes)...'
    $vm = Wait-Tools -VM $vm -TimeoutSeconds 900
    $deadline = (Get-Date).AddMinutes(10)
    do { Start-Sleep -Seconds 15; $ip = (Get-VM -Name $Name).Guest.IPAddress | Where-Object { $_ -eq $IPAddress } } until ($ip -or (Get-Date) -gt $deadline)
    if ($ip) { Write-Host "$Name is up at $IPAddress" -ForegroundColor Green } else { Write-Warning "$Name is running but has not reported $IPAddress yet; check the customization events in vCenter." }
} finally {
    Remove-OSCustomizationSpec -OSCustomizationSpec $spec -Confirm:$false -ErrorAction SilentlyContinue
}
