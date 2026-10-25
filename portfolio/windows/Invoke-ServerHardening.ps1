#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Audit or apply a CIS-aligned security baseline on Windows Server 2016-2025 and Windows 10/11.
.DESCRIPTION
    Each control is checked first and reported as Compliant / NonCompliant; with -Apply, non-compliant
    controls are remediated (honouring -WhatIf). Controls:
      SMBv1 off, SMB signing required, LLMNR off, NetBIOS over TCP/IP off (optional), TLS 1.0/1.1 and
      SSL 3.0 off (SCHANNEL), RDP Network Level Authentication, LSA protection (RunAsPPL), WDigest
      plaintext credentials off, all firewall profiles on, PowerShell script block logging, and an advanced
      audit policy for logon, account management, process creation and policy change events.
    Some changes (SCHANNEL, LSA protection) take effect after a reboot.
.EXAMPLE
    .\Invoke-ServerHardening.ps1                      # audit only
.EXAMPLE
    .\Invoke-ServerHardening.ps1 -Apply -WhatIf       # show what would change
.EXAMPLE
    .\Invoke-ServerHardening.ps1 -Apply -DisableNetBIOS -ReportPath C:\Temp\hardening.csv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [switch]$DisableNetBIOS,
    [string]$ReportPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-RegistryValue([string]$Path, [string]$Name) {
    (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
}
function Write-RegistryValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}
function Get-RegistryControl([string]$Id, [string]$Name, [string]$Path, [string]$Value, $Expected) {
    [pscustomobject]@{
        Id = $Id; Name = $Name
        Test = { (Read-RegistryValue $Path $Value) -eq $Expected }.GetNewClosure()
        Fix = { Write-RegistryValue $Path $Value $Expected }.GetNewClosure()
    }
}

$schannel = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
$controls = [System.Collections.Generic.List[object]]::new()
$controls.Add([pscustomobject]@{
    Id = 'SMB-01'; Name = 'SMBv1 server protocol disabled'
    Test = { -not (Get-SmbServerConfiguration).EnableSMB1Protocol }
    Fix = { Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force }
})
$controls.Add([pscustomobject]@{
    Id = 'SMB-02'; Name = 'SMB server signing required'
    Test = { (Get-SmbServerConfiguration).RequireSecuritySignature }
    Fix = { Set-SmbServerConfiguration -RequireSecuritySignature $true -EnableSecuritySignature $true -Force }
})
$controls.Add((Get-RegistryControl 'NET-01' 'LLMNR disabled (multicast name resolution)' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0))
foreach ($proto in 'SSL 3.0', 'TLS 1.0', 'TLS 1.1') {
    foreach ($side in 'Server', 'Client') {
        $p = "$schannel\$proto\$side"
        $controls.Add([pscustomobject]@{
            Id = "TLS-$($proto -replace '\D', '')-$side"; Name = "$proto disabled ($side)"
            Test = { (Read-RegistryValue $p 'Enabled') -eq 0 -and (Read-RegistryValue $p 'DisabledByDefault') -eq 1 }.GetNewClosure()
            Fix = { Write-RegistryValue $p 'Enabled' 0; Write-RegistryValue $p 'DisabledByDefault' 1 }.GetNewClosure()
        })
    }
}
$controls.Add((Get-RegistryControl 'RDP-01' 'RDP requires Network Level Authentication' 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'UserAuthentication' 1))
$controls.Add((Get-RegistryControl 'LSA-01' 'LSA protection (RunAsPPL) enabled' 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL' 1))
$controls.Add((Get-RegistryControl 'LSA-02' 'WDigest does not cache plaintext credentials' 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential' 0))
$controls.Add((Get-RegistryControl 'PS-01' 'PowerShell script block logging enabled' 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging' 1))
$controls.Add([pscustomobject]@{
    Id = 'FW-01'; Name = 'Windows Firewall enabled on Domain, Private and Public profiles'
    Test = { @(Get-NetFirewallProfile | Where-Object { -not $_.Enabled }).Count -eq 0 }
    Fix = { Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True }
})
$auditSubcategories = @{
    'Logon' = 'Success,Failure'; 'Account Lockout' = 'Failure'; 'Special Logon' = 'Success'
    'User Account Management' = 'Success,Failure'; 'Security Group Management' = 'Success'
    'Process Creation' = 'Success'; 'Audit Policy Change' = 'Success'; 'Authentication Policy Change' = 'Success'
    'Credential Validation' = 'Success,Failure'; 'Kerberos Authentication Service' = 'Success,Failure'
}
foreach ($sub in $auditSubcategories.Keys) {
    $want = $auditSubcategories[$sub]
    $controls.Add([pscustomobject]@{
        Id = "AUD-$($sub -replace '\s', '')"; Name = "Audit '$sub' = $want"
        Test = {
            $line = (auditpol /get /subcategory:"$sub" /r | ConvertFrom-Csv | Select-Object -First 1).'Inclusion Setting'
            ($want -split ',' | Where-Object { $line -notmatch $_ }).Count -eq 0
        }.GetNewClosure()
        Fix = {
            $s = if ($want -match 'Success') { 'enable' } else { 'disable' }
            $f = if ($want -match 'Failure') { 'enable' } else { 'disable' }
            auditpol /set /subcategory:"$sub" /success:$s /failure:$f | Out-Null
        }.GetNewClosure()
    })
}
if ($DisableNetBIOS) {
    $controls.Add([pscustomobject]@{
        Id = 'NET-02'; Name = 'NetBIOS over TCP/IP disabled on all adapters'
        Test = { @(Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' | Where-Object TcpipNetbiosOptions -NE 2).Count -eq 0 }
        Fix = { Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]2 } | Out-Null }
    })
}

$report = foreach ($c in $controls) {
    $before = try { [bool](& $c.Test) } catch { $false }
    $after = $before
    $action = 'none'
    if (-not $before -and $Apply -and $PSCmdlet.ShouldProcess($c.Name, 'Remediate')) {
        try { & $c.Fix; $after = [bool](& $c.Test); $action = 'remediated' }
        catch { $action = "error: $($_.Exception.Message)" }
    }
    [pscustomobject]@{
        Id     = $c.Id
        Control = $c.Name
        Before = if ($before) { 'Compliant' } else { 'NonCompliant' }
        Action = $action
        After  = if ($after) { 'Compliant' } else { 'NonCompliant' }
    }
}
$report | Sort-Object Id | Format-Table -AutoSize | Out-Host
$compliant = @($report | Where-Object After -EQ 'Compliant').Count
Write-Host ("{0}/{1} controls compliant on {2}{3}" -f $compliant, $report.Count, $env:COMPUTERNAME,
    $(if ($Apply -and @($report | Where-Object Action -EQ 'remediated').Count) { ' (reboot to finish SCHANNEL/LSA changes)' }))
if ($ReportPath) { $report | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8 }
