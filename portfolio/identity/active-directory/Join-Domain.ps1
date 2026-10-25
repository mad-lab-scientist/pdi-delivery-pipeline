#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Join a Windows computer to an Active Directory domain, with DNS and connectivity pre-checks.
.DESCRIPTION
    Prompts for the domain, target OU and optional new computer name; verifies that DNS resolves the
    domain's _ldap._tcp.dc._msdcs SRV records, that a domain controller answers on LDAP (389) and Kerberos
    (88), and that the clock is within Kerberos tolerance. Then runs Add-Computer with the credential you
    enter. Use -Restart to reboot when done.
.EXAMPLE
    .\Join-Domain.ps1
.EXAMPLE
    .\Join-Domain.ps1 -DomainName corp.example.com -OUPath 'OU=Application,OU=Servers,OU=Company,DC=corp,DC=example,DC=com' -NewName app01 -Restart
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DomainName,
    [string]$OUPath,
    [ValidatePattern('^[A-Za-z0-9-]{1,15}$')][string]$NewName,
    [pscredential]$Credential,
    [switch]$Restart
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $DomainName) { $DomainName = Read-Host 'Domain to join (FQDN, e.g. corp.example.com)' }
if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain -and (Get-CimInstance Win32_ComputerSystem).Domain -eq $DomainName) {
    Write-Host "$env:COMPUTERNAME is already a member of $DomainName."; return
}

Write-Host "Checking $DomainName ..."
try {
    $srv = Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV -ErrorAction Stop | Where-Object Type -EQ 'SRV'
} catch {
    $dns = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses).ServerAddresses -join ', '
    throw "DNS cannot find domain controllers for $DomainName (SRV _ldap._tcp.dc._msdcs). This computer uses DNS $dns; point it at the domain's DNS servers."
}
$dc = ($srv | Sort-Object Priority, Weight | Select-Object -First 1).NameTarget
Write-Host "  domain controllers: $(($srv.NameTarget | Select-Object -Unique) -join ', ')"
foreach ($port in 389, 88) {
    if (-not (Test-NetConnection -ComputerName $dc -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue)) {
        throw "$dc is not reachable on TCP $port (firewall?)"
    }
}
$offset = (w32tm /stripchart /computer:$dc /samples:1 /dataonly 2>$null | Select-String -Pattern '([+-]\d+\.\d+)s' | Select-Object -Last 1)
if ($offset -and [math]::Abs([double]$offset.Matches[0].Groups[1].Value) -gt 240) {
    throw "Clock differs from $dc by $($offset.Matches[0].Groups[1].Value)s; Kerberos allows 5 minutes. Fix time first."
}
Write-Host '  DNS, LDAP, Kerberos and time checks passed.' -ForegroundColor Green

if (-not $PSBoundParameters.ContainsKey('OUPath')) { $OUPath = Read-Host 'Target OU distinguished name (blank for the default Computers container)' }
if (-not $PSBoundParameters.ContainsKey('NewName')) {
    $answer = Read-Host "New computer name (blank to keep $env:COMPUTERNAME)"
    if ($answer) { $NewName = $answer }
}
if (-not $Credential) { $Credential = Get-Credential -Message "Account allowed to join computers to $DomainName (DOMAIN\user)" }

$params = @{ DomainName = $DomainName; Credential = $Credential; Force = $true }
if ($OUPath) { $params.OUPath = $OUPath }
if ($NewName) { $params.NewName = $NewName }
if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Join $DomainName$(if ($NewName) { " as $NewName" })")) {
    Add-Computer @params
    Write-Host "Joined $DomainName. A restart is required." -ForegroundColor Green
    if ($Restart) { Restart-Computer -Force }
}
