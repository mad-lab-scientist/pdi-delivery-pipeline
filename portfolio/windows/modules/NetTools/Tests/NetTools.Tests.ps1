#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'NetTools.psd1') -Force
}

Describe 'Test-IPv4Address' {
    It 'accepts <_>' -ForEach @('10.20.3.10', '0.0.0.0', '255.255.255.255', '172.16.0.1') {
        Test-IPv4Address $_ | Should -BeTrue
    }
    It 'rejects <_>' -ForEach @('256.1.1.1', '10.20.3', '10.20.3.10.1', '010.1.1.1', 'abc', '') {
        Test-IPv4Address $_ | Should -BeFalse
    }
}

Describe 'Mask and prefix conversion' {
    It 'converts /<Prefix> to <Mask>' -ForEach @(
        @{ Prefix = 0; Mask = '0.0.0.0' }, @{ Prefix = 8; Mask = '255.0.0.0' }, @{ Prefix = 23; Mask = '255.255.254.0' },
        @{ Prefix = 25; Mask = '255.255.255.128' }, @{ Prefix = 31; Mask = '255.255.255.254' }, @{ Prefix = 32; Mask = '255.255.255.255' }
    ) {
        ConvertTo-SubnetMask $Prefix | Should -Be $Mask
        ConvertTo-PrefixLength $Mask | Should -Be $Prefix
    }
    It 'rejects a non-contiguous mask' {
        { ConvertTo-PrefixLength '255.0.255.0' } | Should -Throw
    }
    It 'round-trips integers' {
        ConvertFrom-IPv4UInt32 (ConvertTo-IPv4UInt32 '203.0.113.77') | Should -Be '203.0.113.77'
    }
}

Describe 'Get-IPv4NetworkInfo' {
    It 'computes a /25' {
        $n = Get-IPv4NetworkInfo -Address 10.20.3.10 -PrefixLength 25
        $n.Network | Should -Be '10.20.3.0'
        $n.Broadcast | Should -Be '10.20.3.127'
        $n.FirstUsable | Should -Be '10.20.3.1'
        $n.LastUsable | Should -Be '10.20.3.126'
        $n.UsableHosts | Should -Be 126
        $n.IsHostAddress | Should -BeTrue
    }
    It 'flags the network and broadcast addresses as non-host' {
        (Get-IPv4NetworkInfo -Address 10.20.3.0 -PrefixLength 25).IsHostAddress | Should -BeFalse
        (Get-IPv4NetworkInfo -Address 10.20.3.127 -PrefixLength 25).IsHostAddress | Should -BeFalse
    }
    It 'treats /31 point-to-point links per RFC 3021' {
        $n = Get-IPv4NetworkInfo -Address 10.20.3.160 -PrefixLength 31
        $n.UsableHosts | Should -Be 2
        $n.IsHostAddress | Should -BeTrue
    }
}

Describe 'Test-IPv4SameSubnet' {
    It 'is true inside the subnet' { Test-IPv4SameSubnet 10.20.3.10 10.20.3.1 25 | Should -BeTrue }
    It 'is false across subnets' { Test-IPv4SameSubnet 10.20.3.10 10.20.3.200 25 | Should -BeFalse }
}
