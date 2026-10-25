#Requires -Version 5.1
#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Hyper-V host and VM report: capacity, VM state, integration services, checkpoints, replication health.
.DESCRIPTION
    For one or more Hyper-V hosts (or failover cluster nodes): host CPU/memory capacity, and per VM the
    state, uptime, vCPU, assigned vs demanded memory, VHD size, integration services that are not OK,
    checkpoint count and age of the oldest, and Hyper-V Replica health. Flags common problems.
.EXAMPLE
    .\Get-HyperVHostReport.ps1
.EXAMPLE
    .\Get-HyperVHostReport.ps1 -ComputerName hv01, hv02 -HtmlPath C:\Reports\hyperv.html
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [int]$CheckpointWarnDays = 7,
    [string]$HtmlPath
)
Set-StrictMode -Version Latest
$problems = [System.Collections.Generic.List[string]]::new()
$hosts = foreach ($c in $ComputerName) {
    $h = Get-VMHost -ComputerName $c
    $os = Get-CimInstance -ComputerName $c Win32_OperatingSystem
    [pscustomobject]@{
        Host = $c; LogicalCPUs = $h.LogicalProcessorCount
        MemoryGB = [math]::Round($h.MemoryCapacity / 1GB); FreeMemoryGB = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 1)
        VMs = @(Get-VM -ComputerName $c).Count; NumaSpanning = $h.NumaSpanningEnabled
    }
}
$vms = foreach ($c in $ComputerName) {
    foreach ($vm in Get-VM -ComputerName $c) {
        $checkpoints = @(Get-VMSnapshot -VM $vm -ErrorAction SilentlyContinue)
        $oldest = if ($checkpoints) { [int]((Get-Date) - ($checkpoints | Sort-Object CreationTime | Select-Object -First 1).CreationTime).TotalDays } else { $null }
        $badIs = @(Get-VMIntegrationService -VM $vm | Where-Object { $_.Enabled -and $_.PrimaryStatusDescription -notin 'OK', $null -and $vm.State -eq 'Running' }).Name
        $repl = Get-VMReplication -VM $vm -ErrorAction SilentlyContinue
        $vhdGB = (Get-VMHardDiskDrive -VM $vm | ForEach-Object { (Get-VHD -ComputerName $c -Path $_.Path -ErrorAction SilentlyContinue).FileSize } | Measure-Object -Sum).Sum / 1GB
        $row = [pscustomobject]@{
            Host = $c; VM = $vm.Name; State = $vm.State; Uptime = $vm.Uptime.ToString('d\.hh\:mm')
            vCPU = $vm.ProcessorCount; AssignedGB = [math]::Round($vm.MemoryAssigned / 1GB, 1); DemandGB = [math]::Round($vm.MemoryDemand / 1GB, 1)
            VhdGB = [math]::Round($vhdGB, 1); Generation = $vm.Generation; Version = $vm.Version
            Checkpoints = $checkpoints.Count; OldestCheckpointDays = $oldest
            Replication = if ($repl) { "$($repl.Health) ($($repl.State))" } else { '-' }
            IntegrationIssues = $badIs -join ', '
        }
        if ($oldest -gt $CheckpointWarnDays) { $problems.Add("$($vm.Name): checkpoint $oldest days old") }
        if ($repl -and $repl.Health -ne 'Normal') { $problems.Add("$($vm.Name): replication $($repl.Health)") }
        if ($badIs) { $problems.Add("$($vm.Name): integration services not OK ($($badIs -join ', '))") }
        if ($vm.State -eq 'Running' -and $vm.MemoryDemand -gt $vm.MemoryAssigned) { $problems.Add("$($vm.Name): memory demand exceeds assignment (pressure)") }
        $row
    }
}
$hosts | Format-Table -AutoSize | Out-Host
$vms | Sort-Object Host, VM | Format-Table Host, VM, State, Uptime, vCPU, AssignedGB, DemandGB, VhdGB, Checkpoints, OldestCheckpointDays, Replication -AutoSize | Out-Host
if ($problems) { Write-Host 'Problems:' -ForegroundColor Yellow; $problems | ForEach-Object { Write-Host "  - $_" } } else { Write-Host 'No problems found.' -ForegroundColor Green }
if ($HtmlPath) {
    $body = '<h2>Hosts</h2>' + ($hosts | ConvertTo-Html -Fragment) + '<h2>Virtual machines</h2>' + ($vms | ConvertTo-Html -Fragment) +
        '<h2>Problems</h2><ul>' + (($problems | ForEach-Object { "<li>$([System.Net.WebUtility]::HtmlEncode($_))</li>" }) -join '') + '</ul>'
    ConvertTo-Html -Title 'Hyper-V report' -Body $body | Set-Content -Path $HtmlPath -Encoding UTF8
    Write-Host "Report: $HtmlPath"
}
