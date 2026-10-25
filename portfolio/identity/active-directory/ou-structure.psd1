@{
    # Tiered administration OU model (Microsoft enterprise access model: Tier 0 = identity, Tier 1 = servers,
    # Tier 2 = workstations and users). Paths are relative to the domain root; parents are created first.
    OrganizationalUnits = @(
        @{ Path = 'Company';                                   Description = 'Root for all managed objects' }
        @{ Path = 'Company/Admin';                             Description = 'Administrative accounts and groups' }
        @{ Path = 'Company/Admin/Tier0';                       Description = 'Domain, forest and identity administrators' }
        @{ Path = 'Company/Admin/Tier0/Accounts' }
        @{ Path = 'Company/Admin/Tier0/Groups' }
        @{ Path = 'Company/Admin/Tier0/Devices';               Description = 'Privileged access workstations for Tier 0' }
        @{ Path = 'Company/Admin/Tier1';                       Description = 'Server administrators' }
        @{ Path = 'Company/Admin/Tier1/Accounts' }
        @{ Path = 'Company/Admin/Tier1/Groups' }
        @{ Path = 'Company/Admin/Tier2';                       Description = 'Help desk and workstation administrators' }
        @{ Path = 'Company/Admin/Tier2/Accounts' }
        @{ Path = 'Company/Admin/Tier2/Groups' }
        @{ Path = 'Company/Servers';                           Description = 'Tier 1 member servers' }
        @{ Path = 'Company/Servers/Infrastructure' }
        @{ Path = 'Company/Servers/Application' }
        @{ Path = 'Company/Servers/Database' }
        @{ Path = 'Company/Workstations';                      Description = 'Tier 2 endpoints' }
        @{ Path = 'Company/Workstations/Desktops' }
        @{ Path = 'Company/Workstations/Laptops' }
        @{ Path = 'Company/Users';                             Description = 'Standard user accounts' }
        @{ Path = 'Company/Users/Employees' }
        @{ Path = 'Company/Users/Contractors' }
        @{ Path = 'Company/Groups';                            Description = 'Role and resource groups' }
        @{ Path = 'Company/Groups/Security' }
        @{ Path = 'Company/Groups/Distribution' }
        @{ Path = 'Company/ServiceAccounts';                   Description = 'gMSAs and service identities' }
        @{ Path = 'Company/Disabled';                          Description = 'Disabled objects awaiting deletion' }
    )
    Groups = @(
        @{ Name = 'T0-Admins';           Path = 'Company/Admin/Tier0/Groups'; Scope = 'Global'; Description = 'Tier 0 administrators' }
        @{ Name = 'T1-Server-Admins';    Path = 'Company/Admin/Tier1/Groups'; Scope = 'Global'; Description = 'Local admin on Tier 1 servers' }
        @{ Name = 'T2-Helpdesk';         Path = 'Company/Admin/Tier2/Groups'; Scope = 'Global'; Description = 'Password resets and workstation support' }
        @{ Name = 'SG-Linux-Admins';     Path = 'Company/Groups/Security';    Scope = 'Global'; Description = 'sudo on AD-joined Linux servers' }
        @{ Name = 'SG-VPN-Users';        Path = 'Company/Groups/Security';    Scope = 'Global'; Description = 'Remote access' }
    )
}
