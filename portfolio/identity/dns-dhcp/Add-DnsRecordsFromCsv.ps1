#Requires -Version 5.1
#Requires -Modules DnsServer
<#
.SYNOPSIS
    Bulk-create DNS records (A with optional PTR, CNAME) on a Windows DNS server from CSV. Idempotent.
.DESCRIPTION
    CSV columns: Name, Type (A or CNAME), Value (IPv4 address or target FQDN), Zone, TtlMinutes (optional),
    CreatePtr (true/false, A records only). Existing identical records are skipped; a different existing
    value is reported as a conflict and left untouched unless -Overwrite. Missing reverse zones are created
    (AD-integrated, /24) when -CreateReverseZones is set.
.EXAMPLE
    .\Add-DnsRecordsFromCsv.ps1 -Path records.csv -WhatIf
.EXAMPLE
    .\Add-DnsRecordsFromCsv.ps1 -Path records.csv -ComputerName dc01 -CreateReverseZones
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })][string]$Path,
    [string]$ComputerName = $env:COMPUTERNAME,
    [switch]$CreateReverseZones,
    [switch]$Overwrite
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$dns = @{ ComputerName = $ComputerName }
$results = foreach ($r in Import-Csv -Path $Path) {
    $name = $r.Name.Trim(); $zone = $r.Zone.Trim(); $type = $r.Type.Trim().ToUpper(); $value = $r.Value.Trim()
    $ttl = if ($r.PSObject.Properties['TtlMinutes'] -and $r.TtlMinutes) { New-TimeSpan -Minutes ([int]$r.TtlMinutes) } else { New-TimeSpan -Hours 1 }
    $status = ''
    try {
        $existing = @(Get-DnsServerResourceRecord @dns -ZoneName $zone -Name $name -RRType $type -ErrorAction SilentlyContinue)
        $current = switch ($type) {
            'A' { $existing | ForEach-Object { $_.RecordData.IPv4Address.IPAddressToString } }
            'CNAME' { $existing | ForEach-Object { $_.RecordData.HostNameAlias.TrimEnd('.') } }
            default { throw "unsupported type $type" }
        }
        if ($current -contains $value.TrimEnd('.')) { $status = 'exists' }
        elseif ($existing -and -not $Overwrite) { $status = "CONFLICT (has $($current -join ', '))" }
        elseif ($PSCmdlet.ShouldProcess("$name.$zone $type $value", 'Create DNS record')) {
            if ($existing) { $existing | Remove-DnsServerResourceRecord @dns -ZoneName $zone -Force }
            if ($type -eq 'A') {
                $ptr = $r.PSObject.Properties['CreatePtr'] -and $r.CreatePtr -match '^(true|yes|1)$'
                if ($ptr -and $CreateReverseZones) {
                    $o = $value.Split('.')
                    $revZone = "$($o[2]).$($o[1]).$($o[0]).in-addr.arpa"
                    if (-not (Get-DnsServerZone @dns -Name $revZone -ErrorAction SilentlyContinue)) {
                        Add-DnsServerPrimaryZone @dns -NetworkId "$($o[0]).$($o[1]).$($o[2]).0/24" -ReplicationScope Domain
                    }
                }
                Add-DnsServerResourceRecordA @dns -ZoneName $zone -Name $name -IPv4Address $value -TimeToLive $ttl -CreatePtr:$ptr
            } else {
                Add-DnsServerResourceRecordCName @dns -ZoneName $zone -Name $name -HostNameAlias $value -TimeToLive $ttl
            }
            $status = if ($existing) { 'replaced' } else { 'created' }
        } else { $status = 'whatif' }
    } catch { $status = "ERROR: $($_.Exception.Message)" }
    [pscustomobject]@{ Record = "$name.$zone"; Type = $type; Value = $value; Status = $status }
}
$results | Format-Table -AutoSize | Out-Host
$results | Group-Object { ($_.Status -split ' ')[0] } | Format-Table Count, Name -AutoSize | Out-Host
