#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Promote a Windows Server to the first domain controller of a new Active Directory forest (with DNS).
.DESCRIPTION
    Prompts for the forest root domain (FQDN), NetBIOS name and Directory Services Restore Mode password,
    checks prerequisites (static IP, a DNS server configured, valid names), installs the AD DS role, runs
    Test-ADDSForestInstallation and then Install-ADDSForest. The server reboots when promotion completes.
.EXAMPLE
    .\New-ADForest.ps1
.EXAMPLE
    .\New-ADForest.ps1 -DomainName corp.example.com -NetbiosName CORP -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidatePattern('^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$')]
    [string]$DomainName,
    [ValidatePattern('^[A-Za-z0-9-]{1,15}$')]
    [string]$NetbiosName,
    [securestring]$SafeModeAdministratorPassword,
    [ValidateSet('WinThreshold', 'Win2025')]
    [string]$FunctionalLevel = 'WinThreshold',
    [string]$DatabasePath = "$env:SystemRoot\NTDS",
    [string]$SysvolPath = "$env:SystemRoot\SYSVOL"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\windows\modules\NetTools\NetTools.psd1') -Force

if (-not $DomainName) {
    $DomainName = Read-ValidatedInput -Prompt 'Forest root domain FQDN (e.g. corp.example.com; avoid .local)' -Validate {
        $_ -match '^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$'
    }
}
if (-not $NetbiosName) {
    $suggest = ($DomainName.Split('.')[0]).ToUpper()
    if ($suggest.Length -gt 15) { $suggest = $suggest.Substring(0, 15) }
    $NetbiosName = Read-ValidatedInput -Prompt 'NetBIOS domain name' -Default $suggest -Validate { $_ -match '^[A-Za-z0-9-]{1,15}$' }
}
if (-not $SafeModeAdministratorPassword) {
    do {
        $SafeModeAdministratorPassword = Read-Host -AsSecureString -Prompt 'DSRM (safe mode) administrator password'
        $confirm = Read-Host -AsSecureString -Prompt 'Confirm DSRM password'
        $match = [Net.NetworkCredential]::new('', $SafeModeAdministratorPassword).Password -ceq [Net.NetworkCredential]::new('', $confirm).Password
        if (-not $match) { Write-Warning 'Passwords do not match.' }
    } until ($match)
}

# ---------------------------------------------------------------- prerequisites
$ipConfig = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
if (-not $ipConfig) { throw 'No connected adapter with a default gateway.' }
if ((Get-NetIPInterface -InterfaceIndex $ipConfig.InterfaceIndex -AddressFamily IPv4).Dhcp -eq 'Enabled') {
    throw "Adapter '$($ipConfig.InterfaceAlias)' uses DHCP; a domain controller needs a static IP (windows\Set-StaticIPAddress.ps1)."
}
if ($env:COMPUTERNAME -match '^WIN-[A-Z0-9]{11}$') {
    Write-Warning "The computer still has its generated name ($env:COMPUTERNAME); rename it (Rename-Computer) before promotion."
}
if ($DomainName -match '\.local$') { Write-Warning '.local conflicts with multicast DNS (RFC 6762); a subdomain of a domain you own is recommended.' }

Write-Host "`nForest: $DomainName  NetBIOS: $NetbiosName  Level: $FunctionalLevel  DC: $env:COMPUTERNAME ($(($ipConfig.IPv4Address).IPAddress))"
if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Install AD DS and create forest $DomainName")) { return }

Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
Import-Module ADDSDeployment
$params = @{
    DomainName                    = $DomainName
    DomainNetbiosName             = $NetbiosName.ToUpper()
    ForestMode                    = $FunctionalLevel
    DomainMode                    = $FunctionalLevel
    InstallDns                    = $true
    DatabasePath                  = $DatabasePath
    LogPath                       = $DatabasePath
    SysvolPath                    = $SysvolPath
    SafeModeAdministratorPassword = $SafeModeAdministratorPassword
    NoRebootOnCompletion          = $false
    Force                         = $true
}
$test = Test-ADDSForestInstallation @params -WarningAction SilentlyContinue
if ($test.Status -ne 'Success') { throw "Prerequisite check failed: $($test.Message)" }
Install-ADDSForest @params
