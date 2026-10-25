#Requires -Version 5.1
<#
.SYNOPSIS
    Hardware, OS, network, disk and patch inventory for one or many Windows computers (CIM over WinRM).
.DESCRIPTION
    Uses CIM sessions (WS-Man, falling back to DCOM for older hosts) so it works against servers without
    PowerShell remoting enabled for scripts. Outputs objects; export with -Path to CSV or JSON.
.EXAMPLE
    .\Get-SystemInventory.ps1
.EXAMPLE
    .\Get-SystemInventory.ps1 -ComputerName (Get-Content servers.txt) -Credential (Get-Credential) -Path inventory.csv
.EXAMPLE
    Get-ADComputer -Filter 'OperatingSystem -like "*Server*"' | Select-Object -ExpandProperty DNSHostName |
        .\Get-SystemInventory.ps1 -Path servers.json
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline)][string[]]$ComputerName = $env:COMPUTERNAME,
    [pscredential]$Credential,
    [string]$Path
)
begin {
    Set-StrictMode -Version Latest
    $results = [System.Collections.Generic.List[object]]::new()
}
process {
    foreach ($computer in $ComputerName) {
        $session = $null
        try {
            $params = @{ ComputerName = $computer; ErrorAction = 'Stop' }
            if ($Credential) { $params.Credential = $Credential }
            try { $session = New-CimSession @params }
            catch { $session = New-CimSession @params -SessionOption (New-CimSessionOption -Protocol Dcom) }

            $os = Get-CimInstance -CimSession $session Win32_OperatingSystem
            $cs = Get-CimInstance -CimSession $session Win32_ComputerSystem
            $bios = Get-CimInstance -CimSession $session Win32_BIOS
            $cpu = @(Get-CimInstance -CimSession $session Win32_Processor)
            $disks = Get-CimInstance -CimSession $session Win32_LogicalDisk -Filter 'DriveType = 3'
            $nics = Get-CimInstance -CimSession $session Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True'
            $hotfix = Get-CimInstance -CimSession $session Win32_QuickFixEngineering |
                Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1
            $results.Add([pscustomobject]@{
                ComputerName   = $cs.DNSHostName
                Domain         = $cs.Domain
                Manufacturer   = $cs.Manufacturer
                Model          = $cs.Model
                SerialNumber   = $bios.SerialNumber
                OS             = $os.Caption
                OSVersion      = $os.Version
                InstallDate    = $os.InstallDate
                LastBoot       = $os.LastBootUpTime
                UptimeDays     = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
                CPU            = ($cpu | Select-Object -First 1).Name.Trim()
                Sockets        = $cpu.Count
                Cores          = ($cpu | Measure-Object NumberOfCores -Sum).Sum
                MemoryGB       = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
                FreeMemoryGB   = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 1)
                Disks          = ($disks | ForEach-Object { '{0} {1:N0}/{2:N0} GB free' -f $_.DeviceID, ($_.FreeSpace / 1GB), ($_.Size / 1GB) }) -join '; '
                IPAddresses    = ($nics | ForEach-Object { $_.IPAddress | Where-Object { $_ -match '^\d+\.' } }) -join ', '
                Gateways       = ($nics | ForEach-Object { $_.DefaultIPGateway }) -join ', '
                DnsServers     = ($nics | ForEach-Object { $_.DNSServerSearchOrder } | Select-Object -Unique) -join ', '
                LastHotfix     = if ($hotfix) { "$($hotfix.HotFixID) ($($hotfix.InstalledOn.ToString('yyyy-MM-dd')))" } else { 'unknown' }
                Status         = 'OK'
            })
        } catch {
            $results.Add([pscustomobject]@{ ComputerName = $computer; Status = "FAILED: $($_.Exception.Message)" })
            Write-Warning "${computer}: $($_.Exception.Message)"
        } finally {
            if ($session) { Remove-CimSession $session }
        }
    }
}
end {
    if ($Path) {
        if ($Path -match '\.json$') { $results | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8 }
        else { $results | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8 }
        Write-Host "Inventory of $($results.Count) computer(s) written to $Path"
    } else {
        $results
    }
}
