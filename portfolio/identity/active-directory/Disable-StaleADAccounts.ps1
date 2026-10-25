#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Disable and quarantine user and computer accounts that have not logged on for N days.
.DESCRIPTION
    Uses lastLogonTimestamp (replicated; accurate to about 14 days, so keep -Days well above 14). Each
    account found is disabled, stamped with a description ("Disabled <date> by stale-account cleanup, last
    logon <date>"), and moved to the quarantine OU. Exclusions: accounts in -ExcludeGroup, service accounts
    under -ExcludeOU, and accounts created within the window. Always run with -WhatIf first; every action
    is written to a CSV log.
.EXAMPLE
    .\Disable-StaleADAccounts.ps1 -Days 90 -QuarantineOU 'OU=Disabled,OU=Company,DC=corp,DC=example,DC=com' -WhatIf
.EXAMPLE
    .\Disable-StaleADAccounts.ps1 -Days 120 -Type Computer -QuarantineOU 'OU=Disabled,OU=Company,DC=corp,DC=example,DC=com'
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateRange(30, 3650)][int]$Days = 90,
    [ValidateSet('User', 'Computer', 'Both')][string]$Type = 'Both',
    [Parameter(Mandatory)][string]$QuarantineOU,
    [string[]]$ExcludeOU = @(),
    [string]$ExcludeGroup = 'SG-Stale-Exempt',
    [string]$LogPath = "stale-accounts-$(Get-Date -Format yyyyMMdd-HHmmss).csv"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$null = Get-ADOrganizationalUnit -Identity $QuarantineOU
$cutoff = (Get-Date).AddDays(-$Days)
$exempt = @()
if (Get-ADGroup -Filter "Name -eq '$ExcludeGroup'" -ErrorAction SilentlyContinue) {
    $exempt = @(Get-ADGroupMember -Identity $ExcludeGroup -Recursive | ForEach-Object DistinguishedName)
}
$props = 'LastLogonDate', 'WhenCreated', 'Description', 'DistinguishedName'
$candidates = @()
if ($Type -in 'User', 'Both') { $candidates += Get-ADUser -Filter 'Enabled -eq $true' -Properties $props }
if ($Type -in 'Computer', 'Both') { $candidates += Get-ADComputer -Filter 'Enabled -eq $true' -Properties $props }
$builtin = 'krbtgt', 'Administrator', 'Guest', 'DefaultAccount', 'WDAGUtilityAccount'

$log = foreach ($a in $candidates) {
    $last = $a.LastLogonDate
    if ($a.SamAccountName -in $builtin) { continue }
    if ($a.WhenCreated -gt $cutoff) { continue }
    if ($last -and $last -gt $cutoff) { continue }
    if ($a.DistinguishedName -in $exempt) { continue }
    if ($ExcludeOU | Where-Object { $a.DistinguishedName -like "*,$_" }) { continue }
    if ($a.DistinguishedName -like "*,$QuarantineOU") { continue }
    $lastText = if ($last) { $last.ToString('yyyy-MM-dd') } else { 'never' }
    $action = 'whatif'
    if ($PSCmdlet.ShouldProcess("$($a.SamAccountName) (last logon $lastText)", 'Disable and move to quarantine')) {
        try {
            $stamp = "Disabled $(Get-Date -Format yyyy-MM-dd) by stale-account cleanup, last logon $lastText. Was: $($a.DistinguishedName)"
            Set-ADObject -Identity $a.DistinguishedName -Replace @{ description = $stamp.Substring(0, [math]::Min(1024, $stamp.Length)) }
            Disable-ADAccount -Identity $a.DistinguishedName
            Move-ADObject -Identity $a.DistinguishedName -TargetPath $QuarantineOU
            $action = 'disabled'
        } catch { $action = "error: $($_.Exception.Message)" }
    }
    [pscustomobject]@{ Account = $a.SamAccountName; Class = $a.ObjectClass; LastLogon = $lastText; From = $a.DistinguishedName; Action = $action }
}
$log = @($log)
$log | Export-Csv -Path $LogPath -NoTypeInformation -Encoding UTF8
$log | Group-Object Class, Action | Format-Table Count, Name -AutoSize | Out-Host
Write-Host "$($log.Count) stale account(s) older than $Days days; log: $LogPath"
