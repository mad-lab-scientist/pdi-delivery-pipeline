#Requires -Version 5.1
#Requires -Modules VMware.VimAutomation.Core
<#
.SYNOPSIS
    ESXi host security and health review aligned with the vSphere Security Configuration Guide.
.DESCRIPTION
    Per host: version/build, connection and maintenance state, uptime, lockdown mode, SSH and ESXi Shell
    services (running/startup policy), shell timeouts, NTP servers and service, remote syslog target,
    account lockout settings, transparent page sharing salting and CPU/memory usage. Each check is marked
    PASS/FAIL so the output reads as an audit worksheet. Read-only.
.EXAMPLE
    .\Get-ESXiSecurityReport.ps1 -Server vcenter.corp.example.com -CsvPath esxi-security.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Server,
    [pscredential]$Credential,
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
function Get-Setting($VMHost, [string]$Name) { (Get-AdvancedSetting -Entity $VMHost -Name $Name -ErrorAction SilentlyContinue).Value }

$rows = foreach ($h in Get-VMHost | Sort-Object Name) {
    $svc = Get-VMHostService -VMHost $h
    $ssh = $svc | Where-Object Key -EQ 'TSM-SSH'
    $shell = $svc | Where-Object Key -EQ 'TSM'
    $ntpd = $svc | Where-Object Key -EQ 'ntpd'
    $ntpServers = @(Get-VMHostNtpServer -VMHost $h)
    $syslog = Get-Setting $h 'Syslog.global.logHost'
    $lockdown = $h.ExtensionData.Config.LockdownMode
    $checks = [ordered]@{
        'Lockdown mode enabled'          = $lockdown -in 'lockdownNormal', 'lockdownStrict'
        'SSH stopped and not autostart'  = (-not $ssh.Running) -and $ssh.Policy -ne 'on'
        'ESXi Shell stopped'             = -not $shell.Running
        'Shell interactive timeout <= 900' = [int](Get-Setting $h 'UserVars.ESXiShellInteractiveTimeOut') -in 1..900
        'NTP servers configured'         = $ntpServers.Count -ge 2
        'NTP service running'            = [bool]$ntpd.Running
        'Remote syslog configured'       = [bool]$syslog
        'Account lockout <= 5 failures'  = [int](Get-Setting $h 'Security.AccountLockFailures') -in 1..5
        'TPS salting enabled (2)'        = [int](Get-Setting $h 'Mem.ShareForceSalting') -eq 2
    }
    $failed = @($checks.Keys | Where-Object { -not $checks[$_] })
    [pscustomobject]@{
        Host        = $h.Name
        Version     = "$($h.Version) build $($h.Build)"
        State       = $h.ConnectionState
        UptimeDays  = [math]::Round(((Get-Date) - $h.ExtensionData.Runtime.BootTime).TotalDays, 1)
        CPUPercent  = [math]::Round(100 * $h.CpuUsageMhz / [math]::Max(1, $h.CpuTotalMhz))
        MemPercent  = [math]::Round(100 * $h.MemoryUsageGB / [math]::Max(1, $h.MemoryTotalGB))
        Lockdown    = $lockdown
        SSH         = "$(if ($ssh.Running) { 'running' } else { 'stopped' }) / $($ssh.Policy)"
        NTP         = $ntpServers -join ', '
        Syslog      = $syslog
        Passed      = $checks.Count - $failed.Count
        Failed      = $failed -join '; '
    }
}
$rows | Format-Table Host, Version, State, UptimeDays, CPUPercent, MemPercent, Passed, Failed -AutoSize -Wrap | Out-Host
if ($CsvPath) { $rows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 }
$bad = @($rows | Where-Object Failed)
Write-Host "$(@($rows).Count) host(s); $($bad.Count) with failed checks."
