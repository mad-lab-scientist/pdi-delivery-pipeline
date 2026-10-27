# Azure hub network: resource group, VNet, subnets, a baseline NSG (deny inbound internet, allow
# management only from named sources) associated to non-reserved subnets, and optional NSG flow logs.
terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0, < 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

locals {
  reserved_subnets = ["GatewaySubnet", "AzureBastionSubnet", "AzureFirewallSubnet"]
  common_tags      = merge(var.tags, { module = "azure-network", managed_by = "terraform" })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = var.address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "this" {
  for_each             = var.subnets
  name                 = each.key
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value.address_prefixes
  service_endpoints    = each.value.service_endpoints

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]
    content {
      name = "delegation"
      service_delegation {
        name = delegation.value
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  name                = "nsg-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.common_tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  dynamic "security_rule" {
    for_each = length(var.allowed_ssh_rdp_sources) > 0 ? [1] : []
    content {
      name                       = "AllowMgmtFromTrusted"
      priority                   = 200
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["22", "3389"]
      source_address_prefixes    = var.allowed_ssh_rdp_sources
      destination_address_prefix = "*"
    }
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = { for k, v in var.subnets : k => v if !contains(local.reserved_subnets, k) }
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this.id
}

# ---------------------------------------------------------------- flow logs
resource "random_string" "sa" {
  count   = var.enable_flow_logs ? 1 : 0
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "flow" {
  count                     = var.enable_flow_logs ? 1 : 0
  name                      = "flow${random_string.sa[0].result}"
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  min_tls_version           = "TLS1_2"
  shared_access_key_enabled = true
  tags                      = local.common_tags

  # Deny by default; Network Watcher writes flow logs through the trusted Azure services exception.
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Virtual network flow logs. Azure no longer accepts new NSG flow logs (retired in favour of VNet flow logs).
resource "azurerm_network_watcher_flow_log" "this" {
  count                = var.enable_flow_logs ? 1 : 0
  network_watcher_name = "NetworkWatcher_${var.location}"
  resource_group_name  = "NetworkWatcherRG"
  name                 = "fl-${var.name}"
  target_resource_id   = azurerm_virtual_network.this.id
  storage_account_id   = azurerm_storage_account.flow[0].id
  enabled              = true
  version              = 2

  retention_policy {
    enabled = true
    days    = 90
  }
  tags = local.common_tags
}
