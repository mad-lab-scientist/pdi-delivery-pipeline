#Requires -Version 5.1
#Requires -Modules VMware.VimAutomation.Core
<#
.SYNOPSIS
    vSphere VM inventory: sizing, placement, guest OS and IPs, VMware Tools and hardware version.
.DESCRIPTION
    Connects to vCenter (or reuses an existing connection) and reports every VM with its cluster, host,
    datastores, CPU/memory, provisioned/used storage, guest OS, IP addresses, VMware Tools status, virtual
    hardware version and snapshot count. Exports CSV or HTML; flags VMs whose Tools are not running or
    out of date.
.EXAMPLE
    .\Get-VMInventoryReport.ps1 -Server vcenter.corp.example.com -Path vm-inventory.csv
.EXAMPLE
    .\Get-VMInventoryReport.ps1 -Server vcenter.corp.example.com -Cluster Prod -Path vm-inventory.html
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Server,
    [pscredential]$Credential,
    [string]$Cluster,
    [string]$Path = "vm-inventory-$(Get-Date -Format yyyyMMdd).csv"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$connected = Get-Variable -Name DefaultVIServers -Scope Global -ValueOnly -ErrorAction SilentlyContinue
if (-not ($connected | Where-Object { $_.Name -eq $Server -and $_.IsConnected })) {
    $params = @{ Server = $Server }
    if ($Credential) { $params.Credential = $Credential }
    Connect-VIServer @params | Out-Null
}
$vms = if ($Cluster) { Get-Cluster -Name $Cluster | Get-VM } else { Get-VM }
$rows = foreach ($vm in $vms | Sort-Object Name) {
    $view = $vm.ExtensionData
    [pscustomobject]@{
        Name            = $vm.Name
        PowerState      = $vm.PowerState
        Cluster         = ($vm.VMHost | Get-Cluster -ErrorAction SilentlyContinue).Name
        Host            = $vm.VMHost.Name
        Datastores      = ($vm | Get-Datastore).Name -join ', '
        vCPU            = $vm.NumCpu
        MemoryGB        = $vm.MemoryGB
        ProvisionedGB   = [math]::Round($vm.ProvisionedSpaceGB, 1)
        UsedGB          = [math]::Round($vm.UsedSpaceGB, 1)
        GuestOS         = $view.Guest.GuestFullName
        Hostname        = $view.Guest.HostName
        IPAddresses     = ($vm.Guest.IPAddress | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' }) -join ', '
        ToolsStatus     = $view.Guest.ToolsRunningStatus
        ToolsVersion    = $view.Guest.ToolsVersionStatus2
        HardwareVersion = $view.Config.Version
        Snapshots       = @($vm | Get-Snapshot -ErrorAction SilentlyContinue).Count
        Folder          = $vm.Folder.Name
        Notes           = ($vm.Notes -replace '\r?\n', ' ')
    }
}
if ($Path -match '\.html?$') {
    $rows | ConvertTo-Html -Title "VM inventory $Server" -PreContent "<h2>VM inventory: $Server ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))</h2>" |
        Set-Content -Path $Path -Encoding UTF8
} else {
    $rows | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
}
$on = @($rows | Where-Object PowerState -EQ 'PoweredOn')
$tools = @($on | Where-Object { $_.ToolsStatus -ne 'guestToolsRunning' -or $_.ToolsVersion -notin 'guestToolsCurrent', 'guestToolsUnmanaged' })
Write-Host ("{0} VM(s), {1} powered on, {2} vCPU / {3} GB RAM allocated, {4} with Tools not running or outdated. Report: {5}" -f
    @($rows).Count, $on.Count, ($rows | Measure-Object vCPU -Sum).Sum, ($rows | Measure-Object MemoryGB -Sum).Sum, $tools.Count, $Path)
