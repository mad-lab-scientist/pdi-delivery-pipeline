# identity

Active Directory, DNS/DHCP, and Linux-to-AD integration.

## active-directory (PowerShell, RSAT/`ActiveDirectory` module)

| Script | What it does |
|---|---|
| `New-ADForest.ps1` | Promote a server to the first DC of a new forest, with DNS and prerequisite checks. |
| `New-ADOUStructure.ps1` + `ou-structure.psd1` | Build a tiered administration OU + group model from a data file (idempotent). |
| `Import-ADUsersFromCsv.ps1` | Bulk-create users from CSV with validation; accounts created disabled by default, random passwords, optional ACL-protected handover file. |
| `Get-ADHealthReport.ps1` | Health + security posture: DCs/FSMO, replication, dcdiag, SYSVOL, privileged groups, krbtgt age, AS-REP/Kerberoastable accounts, stale objects → HTML report. |
| `Disable-StaleADAccounts.ps1` | Disable, stamp and quarantine accounts stale beyond N days; `-WhatIf`, exclusions, CSV log. |
| `Join-Domain.ps1` | Join a Windows host to AD with DNS/LDAP/Kerberos/time pre-checks. |

## dns-dhcp (PowerShell)

`New-DhcpScope.ps1` (scope + options + exclusions + failover, fully validated against the subnet),
`Add-DnsRecordsFromCsv.ps1` (bulk A/CNAME with optional PTR, idempotent).

## linux

`join-ad-domain.sh` — join Linux to AD with realmd + SSSD on Debian/RHEL/SUSE, DNS/time pre-checks,
short usernames, login restricted to AD groups, sudo for one AD group.
