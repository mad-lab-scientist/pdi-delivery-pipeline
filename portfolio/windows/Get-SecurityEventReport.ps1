#Requires -Version 5.1
<#
.SYNOPSIS
    Summarise security-relevant Windows events: failed logons, lockouts, privileged group changes,
    new accounts and services, and cleared logs.
.DESCRIPTION
    Queries the Security and System logs with server-side filtering (FilterHashtable) on one or more
    computers, then groups the results so a reviewer sees patterns (top failed accounts and source IPs)
    instead of thousands of raw events. Run on domain controllers for domain-wide authentication events.
      4625 failed logon        4740 account locked out    4720 user created
      4728/4732/4756 member added to a security-enabled global/local/universal group
      1102 Security log cleared                           7045 service installed
.EXAMPLE
    .\Get-SecurityEventReport.ps1 -Hours 24
.EXAMPLE
    .\Get-SecurityEventReport.ps1 -ComputerName dc01, dc02 -Hours 168 -CsvPath C:\Reports\security-week.csv
#>
[CmdletBinding()]
param(
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    [ValidateRange(1, 2160)][int]$Hours = 24,
    [string]$CsvPath
)
Set-StrictMode -Version Latest
$since = (Get-Date).AddHours(-$Hours)
$queries = @(
    @{ Log = 'Security'; Ids = 4625, 4740, 4720, 4728, 4732, 4756, 1102 }
    @{ Log = 'System'; Ids = 7045 }
)
$labels = @{
    4625 = 'Failed logon'; 4740 = 'Account locked out'; 4720 = 'User account created'; 4728 = 'Added to global group'
    4732 = 'Added to local group'; 4756 = 'Added to universal group'; 1102 = 'Security log cleared'; 7045 = 'Service installed'
}

$rows = foreach ($computer in $ComputerName) {
    foreach ($q in $queries) {
        try {
            $events = Get-WinEvent -ComputerName $computer -FilterHashtable @{ LogName = $q.Log; Id = $q.Ids; StartTime = $since } -ErrorAction Stop
        } catch [System.Exception] {
            if ($_.Exception.Message -match 'No events were found') { continue }
            Write-Warning "${computer} $($q.Log): $($_.Exception.Message)"; continue
        }
        foreach ($e in $events) {
            $x = [xml]$e.ToXml()
            $d = @{}
            foreach ($node in $x.Event.EventData.Data) { $d[$node.Name] = $node.'#text' }
            [pscustomobject]@{
                Time      = $e.TimeCreated
                Computer  = $computer
                EventId   = $e.Id
                Event     = $labels[$e.Id]
                Account   = @($d['TargetUserName'], $d['SubjectUserName'], $d['AccountName']) | Where-Object { $_ } | Select-Object -First 1
                Group     = if ($e.Id -in 4728, 4732, 4756) { $d['TargetUserName'] } else { '' }
                Member    = if ($e.Id -in 4728, 4732, 4756) { $d['MemberName'] } else { '' }
                SourceIP  = $d['IpAddress']
                Detail    = if ($e.Id -eq 7045) { "$($d['ServiceName']) -> $($d['ImagePath'])" } elseif ($e.Id -eq 4625) { "status $($d['Status']) substatus $($d['SubStatus']) type $($d['LogonType'])" } else { '' }
                By        = $d['SubjectUserName']
            }
        }
    }
}
$rows = @($rows)
Write-Host "`nSecurity events since $($since.ToString('yyyy-MM-dd HH:mm')) on $($ComputerName -join ', '): $($rows.Count)" -ForegroundColor Cyan
$rows | Group-Object Event | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize | Out-Host

$failed = $rows | Where-Object EventId -EQ 4625
if ($failed) {
    Write-Host 'Top failed-logon accounts' -ForegroundColor Yellow
    $failed | Group-Object Account | Sort-Object Count -Descending | Select-Object -First 10 Count, Name | Format-Table -AutoSize | Out-Host
    Write-Host 'Top failed-logon source addresses' -ForegroundColor Yellow
    $failed | Where-Object { $_.SourceIP -and $_.SourceIP -ne '-' } | Group-Object SourceIP | Sort-Object Count -Descending |
        Select-Object -First 10 Count, Name | Format-Table -AutoSize | Out-Host
}
$critical = $rows | Where-Object EventId -In 1102, 4728, 4732, 4756, 4720, 7045
if ($critical) {
    Write-Host 'Changes to review' -ForegroundColor Red
    $critical | Sort-Object Time | Format-Table Time, Computer, Event, Account, Group, Member, Detail, By -AutoSize -Wrap | Out-Host
}
if ($CsvPath) {
    $rows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Details written to $CsvPath"
}
