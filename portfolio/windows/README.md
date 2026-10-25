# windows

PowerShell 7 / Windows PowerShell 5.1 administration and security scripts. `modules/NetTools` is a small
IPv4 subnet-math + input-validation module with Pester tests. All scripts pass `PSScriptAnalyzer`
(settings in `../PSScriptAnalyzerSettings.psd1`); `tools/Invoke-PowerShellLint.ps1` runs the full gate.

| Script | What it does |
|---|---|
| `Set-StaticIPAddress.ps1` | Configure a static IPv4 (address/gateway/DNS/suffix) with validation and an automatic rollback if the gateway stops answering. `-WhatIf` supported. |
| `Get-SystemInventory.ps1` | Hardware/OS/network/disk/patch inventory for one or many hosts over CIM (WS-Man, DCOM fallback); CSV/JSON. |
| `Invoke-ServerHardening.ps1` | Audit or apply a CIS-aligned baseline (SMBv1 off, SMB signing, LLMNR off, legacy TLS off, RDP NLA, LSA protection, WDigest, firewall, script-block logging, audit policy). Audit-only by default. |
| `Get-SecurityEventReport.ps1` | Summarise failed logons, lockouts, privileged-group changes, new accounts/services and cleared logs; top offenders and source IPs. |
| `Get-PatchCompliance.ps1` | Missing updates, last patch date and pending-reboot state across servers (Windows Update Agent API). |

Modules: `NetTools` — `Get-IPv4NetworkInfo`, `Test-IPv4SameSubnet`, `ConvertTo-SubnetMask`, and more.
