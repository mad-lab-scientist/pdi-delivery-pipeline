#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Build (or reconcile) a tiered OU and group structure from a data file. Idempotent.
.DESCRIPTION
    Reads ou-structure.psd1 (or -DefinitionPath), creates missing OUs parent-first with accidental-deletion
    protection, creates missing groups, and reports what already existed. Safe to re-run after editing the
    data file; nothing is ever deleted or moved.
.EXAMPLE
    .\New-ADOUStructure.ps1 -WhatIf
.EXAMPLE
    .\New-ADOUStructure.ps1 -DefinitionPath .\ou-structure.psd1 -Server dc01.corp.example.com
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DefinitionPath = (Join-Path $PSScriptRoot 'ou-structure.psd1'),
    [string]$Server
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$definition = Import-PowerShellDataFile -Path $DefinitionPath
$ad = @{}
if ($Server) { $ad.Server = $Server }
$domainDN = (Get-ADDomain @ad).DistinguishedName

function ConvertTo-DistinguishedName([string]$Path) {
    $parts = $Path.Split('/')
    [array]::Reverse($parts)
    (($parts | ForEach-Object { "OU=$_" }) -join ',') + ",$domainDN"
}

$created = 0; $existing = 0
foreach ($ou in ($definition.OrganizationalUnits | Sort-Object { $_.Path.Split('/').Count })) {
    $dn = ConvertTo-DistinguishedName $ou.Path
    $name = $ou.Path.Split('/')[-1]
    $parent = $dn.Substring($dn.IndexOf(',') + 1)
    if (Get-ADOrganizationalUnit @ad -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue) {
        $existing++; Write-Verbose "exists: $dn"; continue
    }
    if ($PSCmdlet.ShouldProcess($dn, 'Create OU')) {
        $params = @{ Name = $name; Path = $parent; ProtectedFromAccidentalDeletion = $true }
        if ($ou.ContainsKey('Description')) { $params.Description = $ou.Description }
        New-ADOrganizationalUnit @ad @params
        $created++; Write-Host "created OU  $dn"
    }
}
foreach ($g in $definition.Groups) {
    if (Get-ADGroup @ad -Filter "SamAccountName -eq '$($g.Name)'" -ErrorAction SilentlyContinue) { $existing++; continue }
    $path = ConvertTo-DistinguishedName $g.Path
    if ($PSCmdlet.ShouldProcess("$($g.Name) in $path", 'Create group')) {
        New-ADGroup @ad -Name $g.Name -SamAccountName $g.Name -GroupScope $g.Scope -GroupCategory Security -Path $path -Description $g.Description
        $created++; Write-Host "created group $($g.Name)"
    }
}
Write-Host "Done: $created created, $existing already present."
