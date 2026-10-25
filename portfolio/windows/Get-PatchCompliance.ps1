#Requires -Version 5.1
<#
.SYNOPSIS
    Missing Windows updates, last patch date and pending-reboot state across many servers.
.DESCRIPTION
    Runs the Windows Update Agent search (the same API Windows Update uses) on each computer through
    PowerShell remoting, in parallel, and checks the three registry locations that signal a pending reboot
    (Component Based Servicing, Windows Update, pending file renames). Read-only: nothing is installed.
.EXAMPLE
    .\Get-PatchCompliance.ps1
.EXAMPLE
    .\Get-PatchCompliance.ps1 -ComputerName (Get-Content servers.txt) -MaxDaysSincePatch 35 -CsvPath patch-report.csv
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [pscredential]$Credential,
    [int]$MaxDaysSincePatch = 35,
    [string]$CsvPath
)
Set-StrictMode -Version Latest

$probe = {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $pending = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'").Updates
    $missing = foreach ($u in $pending) {
        [pscustomobject]@{
            Title    = $u.Title
            KB       = ($u.KBArticleIDs | ForEach-Object { "KB$_" }) -join ','
            Severity = if ($u.MsrcSeverity) { $u.MsrcSeverity } else { 'Unrated' }
        }
    }
    $last = Get-HotFix | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
    $reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
              (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
              [bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Missing      = @($missing)
        LastPatch    = if ($last) { $last.InstalledOn } else { $null }
        LastKB       = if ($last) { $last.HotFixID } else { '' }
        RebootNeeded = $reboot
        OS           = (Get-CimInstance Win32_OperatingSystem).Caption
    }
}

$params = @{ ScriptBlock = $probe; ErrorAction = 'SilentlyContinue'; ErrorVariable = 'remoteErrors' }
$remote = @($ComputerName | Where-Object { $_ -notin $env:COMPUTERNAME, 'localhost', '.' }).Count -gt 0
if ($remote) {
    $params.ComputerName = $ComputerName
    if ($Credential) { $params.Credential = $Credential }
}
$raw = Invoke-Command @params
foreach ($err in $remoteErrors) { Write-Warning "$($err.TargetObject): $($err.Exception.Message)" }

$report = foreach ($r in @($raw)) {
    $name = if ($r.PSObject.Properties['PSComputerName']) { $r.PSComputerName } else { $env:COMPUTERNAME }
    $days = if ($r.LastPatch) { [int]((Get-Date) - [datetime]$r.LastPatch).TotalDays } else { $null }
    $crit = @($r.Missing | Where-Object Severity -In 'Critical', 'Important').Count
    [pscustomobject]@{
        Computer        = $name
        OS              = $r.OS
        MissingTotal    = @($r.Missing).Count
        CriticalOrImportant = $crit
        LastPatch       = if ($r.LastPatch) { ([datetime]$r.LastPatch).ToString('yyyy-MM-dd') } else { 'unknown' }
        DaysSincePatch  = $days
        RebootPending   = $r.RebootNeeded
        Compliant       = ($crit -eq 0) -and ($null -ne $days) -and ($days -le $MaxDaysSincePatch) -and (-not $r.RebootNeeded)
        MissingKBs      = (@($r.Missing) | ForEach-Object KB | Where-Object { $_ }) -join ' '
    }
}
$report | Sort-Object Compliant, Computer | Format-Table Computer, MissingTotal, CriticalOrImportant, LastPatch, DaysSincePatch, RebootPending, Compliant -AutoSize | Out-Host
$ok = @($report | Where-Object Compliant).Count
Write-Host "$ok of $(@($report).Count) computer(s) compliant (no critical/important updates missing, patched within $MaxDaysSincePatch days, no pending reboot)."
if ($CsvPath) { $report | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 }
