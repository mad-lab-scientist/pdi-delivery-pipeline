#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Active Directory health and security posture report (HTML + console summary).
.DESCRIPTION
    Health:   domain controllers and FSMO roles, replication failures and last successful replication per
              partner, dcdiag results per DC, time source of the PDC emulator, SYSVOL (DFSR) state.
    Security: privileged group membership (Domain/Enterprise/Schema Admins, Administrators), krbtgt password
              age, accounts with PasswordNeverExpires, AdminCount=1 orphans, stale users and computers,
              Kerberos pre-authentication disabled (AS-REP roastable), user accounts with an SPN.
    Read-only. Run from a domain-joined admin workstation or a DC with RSAT.
.EXAMPLE
    .\Get-ADHealthReport.ps1 -StaleDays 90 -HtmlPath C:\Reports\ad-health.html
#>
[CmdletBinding()]
param(
    [int]$StaleDays = 90,
    [string]$HtmlPath = "ad-health-$(Get-Date -Format yyyyMMdd).html",
    [switch]$SkipDcDiag
)
Set-StrictMode -Version Latest
$domain = Get-ADDomain
$forest = Get-ADForest
$cutoff = (Get-Date).AddDays(-$StaleDays)
$sections = [ordered]@{}
$issues = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------- health
$dcs = @(Get-ADDomainController -Filter * | Sort-Object Name)
$sections['Domain controllers'] = $dcs | Select-Object Name, Site, IPv4Address, OperatingSystem, IsGlobalCatalog, IsReadOnly
$sections['FSMO roles'] = @(
    [pscustomobject]@{ Role = 'Schema master'; Holder = $forest.SchemaMaster }
    [pscustomobject]@{ Role = 'Domain naming master'; Holder = $forest.DomainNamingMaster }
    [pscustomobject]@{ Role = 'PDC emulator'; Holder = $domain.PDCEmulator }
    [pscustomobject]@{ Role = 'RID master'; Holder = $domain.RIDMaster }
    [pscustomobject]@{ Role = 'Infrastructure master'; Holder = $domain.InfrastructureMaster }
)
$failures = @(Get-ADReplicationFailure -Target $forest.Name -Scope Forest -ErrorAction SilentlyContinue | Where-Object FailureCount -GT 0)
$sections['Replication failures'] = $failures | Select-Object Server, Partner, FailureCount, FirstFailureTime, LastError
if ($failures) { $issues.Add("$($failures.Count) replication link(s) failing") }
$partners = foreach ($dc in $dcs) {
    Get-ADReplicationPartnerMetadata -Target $dc.HostName -ErrorAction SilentlyContinue |
        Select-Object @{ n = 'Server'; e = { $dc.Name } }, @{ n = 'Partner'; e = { ($_.Partner -split ',')[1] -replace 'CN=' } },
            LastReplicationSuccess, ConsecutiveReplicationFailures
}
$sections['Replication partners'] = $partners
foreach ($p in @($partners)) {
    if ($p.LastReplicationSuccess -lt (Get-Date).AddHours(-24)) { $issues.Add("$($p.Server) <- $($p.Partner): no successful replication in 24 h") }
}
if (-not $SkipDcDiag) {
    $sections['dcdiag'] = foreach ($dc in $dcs) {
        $out = dcdiag /s:$($dc.HostName) /q 2>&1 | Out-String
        $failed = @([regex]::Matches($out, 'failed test (\S+)') | ForEach-Object { $_.Groups[1].Value })
        if ($failed) { $issues.Add("$($dc.Name): dcdiag failed $($failed -join ', ')") }
        [pscustomobject]@{ DC = $dc.Name; FailedTests = if ($failed) { $failed -join ', ' } else { 'none' } }
    }
}
$timeSource = (w32tm /query /computer:$($domain.PDCEmulator) /source 2>&1 | Out-String).Trim()
$sections['PDC emulator time source'] = [pscustomobject]@{ PDC = $domain.PDCEmulator; Source = $timeSource }
if ($timeSource -match 'Local CMOS Clock|Free-running') { $issues.Add('PDC emulator is not syncing with an external NTP source') }
$sections['SYSVOL (DFSR)'] = foreach ($dc in $dcs) {
    $state = Get-CimInstance -ComputerName $dc.HostName -Namespace root/microsoftdfs -ClassName DfsrReplicatedFolderInfo -Filter "ReplicatedFolderName = 'SYSVOL Share'" -ErrorAction SilentlyContinue
    $label = switch ($state.State) { 0 { 'Uninitialized' } 1 { 'Initialized' } 2 { 'Initial sync' } 3 { 'Auto recovery' } 4 { 'Normal' } 5 { 'In error' } default { 'unknown' } }
    if ($label -ne 'Normal') { $issues.Add("$($dc.Name): SYSVOL DFSR state $label") }
    [pscustomobject]@{ DC = $dc.Name; State = $label }
}

# ---------------------------------------------------------------- security posture
$privileged = foreach ($g in 'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators') {
    Get-ADGroupMember -Identity $g -Recursive -ErrorAction SilentlyContinue | Where-Object objectClass -EQ 'user' |
        ForEach-Object { Get-ADUser $_ -Properties LastLogonDate, PasswordLastSet, Enabled } |
        Select-Object @{ n = 'Group'; e = { $g } }, SamAccountName, Enabled, LastLogonDate, PasswordLastSet
}
$sections['Privileged accounts'] = $privileged
if (@($privileged | Where-Object Group -EQ 'Schema Admins').Count) { $issues.Add('Schema Admins is not empty (keep it empty except during schema changes)') }
$krbtgt = Get-ADUser krbtgt -Properties PasswordLastSet
$krbAge = [int]((Get-Date) - $krbtgt.PasswordLastSet).TotalDays
$sections['krbtgt'] = [pscustomobject]@{ PasswordLastSet = $krbtgt.PasswordLastSet; AgeDays = $krbAge }
if ($krbAge -gt 180) { $issues.Add("krbtgt password is $krbAge days old (rotate twice, 10+ hours apart)") }
$neverExpire = @(Get-ADUser -Filter 'PasswordNeverExpires -eq $true -and Enabled -eq $true' -Properties PasswordLastSet)
$sections['PasswordNeverExpires (enabled)'] = $neverExpire | Select-Object SamAccountName, PasswordLastSet
$asrep = @(Get-ADUser -Filter 'DoesNotRequirePreAuth -eq $true' )
$sections['Kerberos pre-auth disabled'] = $asrep | Select-Object SamAccountName, Enabled
if ($asrep) { $issues.Add("$($asrep.Count) account(s) without Kerberos pre-authentication (AS-REP roasting risk)") }
$spnUsers = @(Get-ADUser -Filter 'ServicePrincipalName -like "*"' -Properties ServicePrincipalName, PasswordLastSet | Where-Object SamAccountName -NE 'krbtgt')
$sections['User accounts with SPNs (Kerberoastable)'] = $spnUsers | Select-Object SamAccountName, PasswordLastSet, @{ n = 'SPNs'; e = { $_.ServicePrincipalName -join '; ' } }
$adminCount = @(Get-ADUser -Filter 'AdminCount -eq 1' -Properties AdminCount, MemberOf | Where-Object { -not ($privileged.SamAccountName -contains $_.SamAccountName) -and $_.SamAccountName -ne 'krbtgt' })
$sections['AdminCount=1 outside privileged groups'] = $adminCount | Select-Object SamAccountName, Enabled
$staleUsers = @(Get-ADUser -Filter 'Enabled -eq $true' -Properties LastLogonDate | Where-Object { $_.LastLogonDate -and $_.LastLogonDate -lt $cutoff })
$staleComputers = @(Get-ADComputer -Filter 'Enabled -eq $true' -Properties LastLogonDate, OperatingSystem | Where-Object { $_.LastLogonDate -and $_.LastLogonDate -lt $cutoff })
$sections["Stale users (> $StaleDays days)"] = $staleUsers | Select-Object SamAccountName, LastLogonDate
$sections["Stale computers (> $StaleDays days)"] = $staleComputers | Select-Object Name, OperatingSystem, LastLogonDate
if ($staleUsers.Count + $staleComputers.Count) { $issues.Add("$($staleUsers.Count) stale user(s), $($staleComputers.Count) stale computer(s) (Disable-StaleADAccounts.ps1)") }

# ---------------------------------------------------------------- output
$style = '<style>body{font-family:Segoe UI,Arial;margin:24px}h1{font-size:20px}h2{font-size:15px;margin-top:22px}table{border-collapse:collapse;font-size:12px}td,th{border:1px solid #ccc;padding:3px 8px;text-align:left}th{background:#eef}.bad{color:#b00}</style>'
$body = "<h1>Active Directory health: $($domain.DNSRoot) ($(Get-Date -Format 'yyyy-MM-dd HH:mm'))</h1>"
$body += if ($issues) { '<h2 class="bad">Issues</h2><ul>' + (($issues | ForEach-Object { "<li>$([System.Net.WebUtility]::HtmlEncode($_))</li>" }) -join '') + '</ul>' } else { '<h2>No issues found</h2>' }
foreach ($name in $sections.Keys) {
    $data = @($sections[$name])
    $body += "<h2>$name ($($data.Count))</h2>" + $(if ($data.Count) { ($data | ConvertTo-Html -Fragment) -join '' } else { '<p>none</p>' })
}
ConvertTo-Html -Head $style -Body $body -Title "AD health $($domain.DNSRoot)" | Set-Content -Path $HtmlPath -Encoding UTF8
Write-Host "`n$($domain.DNSRoot): $($dcs.Count) DC(s), $($issues.Count) issue(s)" -ForegroundColor $(if ($issues) { 'Yellow' } else { 'Green' })
$issues | ForEach-Object { Write-Host "  - $_" }
Write-Host "Report: $HtmlPath"
