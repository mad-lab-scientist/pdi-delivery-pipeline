#Requires -Version 5.1
#Requires -Modules VMware.VimAutomation.Core
<#
.SYNOPSIS
    Report vSphere snapshots by age and size, and optionally remove the old ones.
.DESCRIPTION
    Snapshots are not backups: delta disks grow, slow I/O and can fill datastores. This lists every
    snapshot with its VM, age, size and creator description, flags those older than -Days, and with
    -Remove deletes them one at a time (RunAsync off, so consolidation finishes before the next one),
    honouring -WhatIf/-Confirm. Snapshots whose name matches -KeepPattern are never removed.
.EXAMPLE
    .\Get-VMSnapshotReport.ps1 -Server vcenter.corp.example.com -Days 7
.EXAMPLE
    .\Get-VMSnapshotReport.ps1 -Server vcenter.corp.example.com -Days 14 -Remove -KeepPattern '^(golden|pre-upgrade)' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$Server,
    [pscredential]$Credential,
    [ValidateRange(1, 3650)][int]$Days = 7,
    [switch]$Remove,
    [string]$KeepPattern,
    [string]$CsvPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$connected = Get-Variable -Name DefaultVIServers -Scope Global -ValueOnly -ErrorAction SilentlyContinue
if (-not ($connected | Where-Object { $_.Name -eq $Server -and $_.IsConnected })) {
    $params = @{ Server = $Server }
    if ($Credential) { $params.Credential = $Credential }
    Connect-VIServer @params | Out-Null
}
$cutoff = (Get-Date).AddDays(-$Days)
$snaps = @(Get-VM | Get-Snapshot | Sort-Object Created)
$rows = foreach ($s in $snaps) {
    [pscustomobject]@{
        VM          = $s.VM.Name
        Snapshot    = $s.Name
        Created     = $s.Created
        AgeDays     = [int]((Get-Date) - $s.Created).TotalDays
        SizeGB      = [math]::Round($s.SizeGB, 2)
        Memory      = $s.PowerState -eq 'PoweredOn'
        Description = $s.Description
        Old         = $s.Created -lt $cutoff
        Keep        = [bool]($KeepPattern -and $s.Name -match $KeepPattern)
        Snap        = $s
    }
}
$rows | Format-Table VM, Snapshot, Created, AgeDays, SizeGB, Old, Keep -AutoSize | Out-Host
$old = @($rows | Where-Object { $_.Old -and -not $_.Keep })
Write-Host ("{0} snapshot(s) using {1} GB; {2} older than {3} days eligible for removal ({4} GB)" -f
    $snaps.Count, [math]::Round(($rows | Measure-Object SizeGB -Sum).Sum, 1), $old.Count, $Days, [math]::Round(($old | Measure-Object SizeGB -Sum).Sum, 1))
if ($CsvPath) { $rows | Select-Object -ExcludeProperty Snap | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 }
if ($Remove) {
    foreach ($r in $old) {
        if ($PSCmdlet.ShouldProcess("$($r.VM) / $($r.Snapshot) ($($r.AgeDays) days, $($r.SizeGB) GB)", 'Remove snapshot')) {
            Remove-Snapshot -Snapshot $r.Snap -Confirm:$false
            Write-Host "removed $($r.VM) / $($r.Snapshot)"
        }
    }
}
