#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Create a Generation 2 Hyper-V VM with secure defaults: Secure Boot (Windows or Linux template),
    optional vTPM, dynamic memory, VLAN tag, production checkpoints and an install ISO.
.DESCRIPTION
    Prompts for anything not supplied and lists the available virtual switches. Places files in the host's
    default VM and VHD paths. Linux guests get the 'Microsoft UEFI Certificate Authority' Secure Boot template
    so shim-signed distributions (Ubuntu, RHEL, SUSE, Debian) boot.
.EXAMPLE
    .\New-HyperVVM.ps1
.EXAMPLE
    .\New-HyperVVM.ps1 -Name web01 -SwitchName External -VlanId 30 -ProcessorCount 2 -StartupMemoryGB 4 `
        -DiskSizeGB 80 -IsoPath D:\ISO\ubuntu-24.04.5-live-server-amd64.iso -GuestOS Linux -Start
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidatePattern('^[A-Za-z0-9-]{1,63}$')][string]$Name,
    [string]$SwitchName,
    [ValidateRange(0, 4094)][int]$VlanId = 0,
    [ValidateRange(1, 64)][int]$ProcessorCount = 2,
    [ValidateRange(1, 1024)][int]$StartupMemoryGB = 4,
    [ValidateRange(1, 1024)][int]$MaximumMemoryGB = 8,
    [ValidateRange(20, 65536)][int]$DiskSizeGB = 64,
    [string]$IsoPath,
    [ValidateSet('Windows', 'Linux')][string]$GuestOS = 'Windows',
    [switch]$EnableTpm,
    [switch]$Start
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$hostInfo = Get-VMHost
if (-not $Name) { $Name = Read-Host 'VM name' }
if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "VM $Name already exists" }
if (-not $SwitchName) {
    $switches = @(Get-VMSwitch | Sort-Object Name)
    $switches | Format-Table Name, SwitchType, NetAdapterInterfaceDescription -AutoSize | Out-Host
    $SwitchName = Read-Host "Virtual switch [$($switches[0].Name)]"
    if (-not $SwitchName) { $SwitchName = $switches[0].Name }
}
$null = Get-VMSwitch -Name $SwitchName
if (-not $PSBoundParameters.ContainsKey('IsoPath')) { $IsoPath = Read-Host 'Install ISO path (blank for none)' }
if ($IsoPath -and -not (Test-Path $IsoPath -PathType Leaf)) { throw "ISO not found: $IsoPath" }
if ($MaximumMemoryGB -lt $StartupMemoryGB) { $MaximumMemoryGB = $StartupMemoryGB }
$vhdPath = Join-Path $hostInfo.VirtualHardDiskPath "$Name-os.vhdx"

Write-Host "`n$Name : Gen2, $ProcessorCount vCPU, $StartupMemoryGB-$MaximumMemoryGB GB dynamic, $DiskSizeGB GB disk, switch $SwitchName$(if ($VlanId) { " VLAN $VlanId" }), $GuestOS Secure Boot$(if ($EnableTpm) { ', vTPM' })"
if (-not $PSCmdlet.ShouldProcess($Name, 'Create Hyper-V VM')) { return }

$vm = New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($StartupMemoryGB * 1GB) -NewVHDPath $vhdPath -NewVHDSizeBytes ($DiskSizeGB * 1GB) -SwitchName $SwitchName -Path $hostInfo.VirtualMachinePath
Set-VM -VM $vm -ProcessorCount $ProcessorCount -DynamicMemory -MemoryMinimumBytes 1GB -MemoryMaximumBytes ($MaximumMemoryGB * 1GB) `
    -AutomaticStartAction StartIfRunning -AutomaticStopAction ShutDown -CheckpointType Production -Notes "Created $(Get-Date -Format yyyy-MM-dd) by New-HyperVVM.ps1"
$template = if ($GuestOS -eq 'Linux') { 'MicrosoftUEFICertificateAuthority' } else { 'MicrosoftWindows' }
Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate $template
if ($VlanId) { Set-VMNetworkAdapterVlan -VM $vm -Access -VlanId $VlanId }
Set-VMNetworkAdapter -VM $vm -DhcpGuard On -RouterGuard On -MacAddressSpoofing Off
Enable-VMIntegrationService -VM $vm -Name 'Guest Service Interface'
if ($EnableTpm) {
    Set-VMKeyProtector -VM $vm -NewLocalKeyProtector
    Enable-VMTPM -VM $vm
}
if ($IsoPath) {
    $dvd = Add-VMDvdDrive -VM $vm -Path $IsoPath -Passthru
    Set-VMFirmware -VM $vm -FirstBootDevice $dvd
}
if ($Start) { Start-VM -VM $vm }
Get-VM -Name $Name | Format-List Name, State, Generation, ProcessorCount, MemoryStartup, DynamicMemoryEnabled, Path
