#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Bulk-create Active Directory users from a CSV file, with validation and a per-row result log.
.DESCRIPTION
    CSV columns: GivenName, Surname, SamAccountName, Department, Title, OU (relative path like
    Company/Users/Employees or a full DN), Groups (semicolon separated), Manager (sAMAccountName, optional).

    Every row is validated first (required fields, duplicate names, OU and group existence); invalid rows are
    skipped and reported. New accounts get a random 20-character password and must change it at first logon.
    Secure by default: accounts are created DISABLED and no password is stored anywhere. With
    -HandoverFile, accounts are enabled and the temporary passwords are written to that file, readable
    only by you (ACL), for out-of-band delivery. Delete the file after use.
.EXAMPLE
    .\Import-ADUsersFromCsv.ps1 -Path new-hires.csv -UpnSuffix corp.example.com -WhatIf
.EXAMPLE
    .\Import-ADUsersFromCsv.ps1 -Path new-hires.csv -UpnSuffix corp.example.com -HandoverFile C:\Secure\initial-passwords.csv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })][string]$Path,
    [Parameter(Mandatory)][string]$UpnSuffix,
    [string]$HandoverFile,
    [string]$ResultPath = "ad-import-$(Get-Date -Format yyyyMMdd-HHmmss).csv",
    [string]$Server
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ad = @{}
if ($Server) { $ad.Server = $Server }
$domainDN = (Get-ADDomain @ad).DistinguishedName

function Get-RandomPassword([int]$Length = 20) {
    # Cryptographically random, guaranteed to contain upper, lower, digit and symbol characters.
    $sets = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '!#%+=?@^_-'
    $all = -join $sets
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $pick = { param($chars) $b = [byte[]]::new(4); $rng.GetBytes($b); $chars[[BitConverter]::ToUInt32($b, 0) % $chars.Length] }
    $chars = @($sets | ForEach-Object { & $pick $_ }) + @(1..($Length - $sets.Count) | ForEach-Object { & $pick $all })
    -join ($chars | Sort-Object { $b = [byte[]]::new(4); $rng.GetBytes($b); [BitConverter]::ToUInt32($b, 0) })
}
function Resolve-OU([string]$OU) {
    if ($OU -match '^(OU|CN)=') { return $OU }
    $parts = $OU.Split('/'); [array]::Reverse($parts)
    (($parts | ForEach-Object { "OU=$_" }) -join ',') + ",$domainDN"
}

$rows = @(Import-Csv -Path $Path)
$required = 'GivenName', 'Surname', 'SamAccountName', 'OU'
$results = [System.Collections.Generic.List[object]]::new()
$passwords = [System.Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($row in $rows) {
    $sam = "$($row.SamAccountName)".Trim()
    $problems = @()
    foreach ($col in $required) { if (-not "$($row.$col)".Trim()) { $problems += "missing $col" } }
    if ($sam -and $sam -notmatch '^[A-Za-z0-9._-]{1,20}$') { $problems += 'sAMAccountName must be 1-20 letters, digits, . _ -' }
    if ($sam -and $seen.ContainsKey($sam)) { $problems += 'duplicate in CSV' }
    $seen[$sam] = $true
    if ($sam -and (Get-ADUser @ad -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue)) { $problems += 'already exists in AD' }
    $ouDN = if ($row.OU) { Resolve-OU $row.OU } else { '' }
    if ($ouDN -and -not (Get-ADOrganizationalUnit @ad -Filter "DistinguishedName -eq '$ouDN'" -ErrorAction SilentlyContinue)) { $problems += "OU not found: $ouDN" }
    $groups = @("$($row.Groups)".Split(';') | ForEach-Object Trim | Where-Object { $_ })
    foreach ($g in $groups) { if (-not (Get-ADGroup @ad -Filter "SamAccountName -eq '$g'" -ErrorAction SilentlyContinue)) { $problems += "group not found: $g" } }
    if ($problems) {
        $results.Add([pscustomobject]@{ SamAccountName = $sam; Result = 'SKIPPED'; Detail = $problems -join '; ' }); continue
    }

    $display = "$($row.GivenName) $($row.Surname)".Trim()
    if (-not $PSCmdlet.ShouldProcess("$sam ($display) in $ouDN", 'Create user')) {
        $results.Add([pscustomobject]@{ SamAccountName = $sam; Result = 'WHATIF'; Detail = $ouDN }); continue
    }
    $plain = Get-RandomPassword
    $secure = [securestring]::new()
    foreach ($ch in $plain.ToCharArray()) { $secure.AppendChar($ch) }
    $secure.MakeReadOnly()
    try {
        $params = @{
            Name = $display; DisplayName = $display; GivenName = $row.GivenName; Surname = $row.Surname
            SamAccountName = $sam; UserPrincipalName = "$sam@$UpnSuffix"; Path = $ouDN
            AccountPassword = $secure
            ChangePasswordAtLogon = $true; Enabled = [bool]$HandoverFile
        }
        if ($row.PSObject.Properties['Department'] -and $row.Department) { $params.Department = $row.Department }
        if ($row.PSObject.Properties['Title'] -and $row.Title) { $params.Title = $row.Title }
        if ($row.PSObject.Properties['Manager'] -and $row.Manager) { $params.Manager = $row.Manager }
        New-ADUser @ad @params
        foreach ($g in $groups) { Add-ADGroupMember @ad -Identity $g -Members $sam }
        if ($HandoverFile) { $passwords.Add([pscustomobject]@{ SamAccountName = $sam; UserPrincipalName = "$sam@$UpnSuffix"; TemporaryPassword = $plain }) }
        $results.Add([pscustomobject]@{ SamAccountName = $sam; Result = 'CREATED'; Detail = if ($HandoverFile) { 'enabled' } else { 'disabled until a help-desk reset' } })
    } catch {
        $results.Add([pscustomobject]@{ SamAccountName = $sam; Result = 'FAILED'; Detail = $_.Exception.Message })
    } finally {
        $plain = $null
    }
}

$results | Export-Csv -Path $ResultPath -NoTypeInformation -Encoding UTF8
if ($passwords.Count) {
    $passwords | Export-Csv -Path $HandoverFile -NoTypeInformation -Encoding UTF8
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
    Set-Acl -Path $HandoverFile -AclObject $acl
    Write-Warning "Temporary passwords are in $HandoverFile (readable only by $me). Deliver them out of band, then delete the file."
}
$results | Group-Object Result | Format-Table Count, Name -AutoSize | Out-Host
Write-Host "Per-row results: $ResultPath"
