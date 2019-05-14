terraform {
  required_version = ">= 0.12.0"
  backend "azurerm" {}
}

data "azurerm_client_config" "current" {}

locals {
  ddos_vnet_list = var.create_ddos_plan ? [true] : []
}

#
# Resource group
#

resource "azurerm_resource_group" "vnet" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

#
# DDos protection plan
#

resource "azurerm_network_ddos_protection_plan" "vnet" {
  count               = length(local.ddos_vnet_list)
  name                = "${var.name}-protection-plan"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

#
# Hub network with subnets
#

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name}-vnet"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name
  address_space       = [var.address_space]

  dynamic "ddos_protection_plan" {
    for_each = local.ddos_vnet_list
    iterator = ddos
    content {
      id     = azurerm_ddos_protection_plan.vnet.id
      enable = true
    }
  }

  tags = var.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = cidrsubnet(var.address_space, 2, 0)

  service_endpoints = [
    "Microsoft.AzureActiveDirectory",
    "Microsoft.EventHub",
    "Microsoft.KeyVault",
    "Microsoft.AzureCosmosDB",
    "Microsoft.ServiceBus",
    "Microsoft.Sql",
    "Microsoft.Storage",
  ]

  lifecycle {
    # TODO Remove this when azurerm 2.0 provider is released
    ignore_changes = [
      "route_table_id",
      "network_security_group_id",
    ]
  }
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = cidrsubnet(var.address_space, 2, 1)

  lifecycle {
    # TODO Remove this when azurerm 2.0 provider is released
    ignore_changes = [
      "route_table_id",
      "network_security_group_id",
    ]
  }
}

resource "azurerm_subnet" "mgmt" {
  name                 = "mgmt"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = cidrsubnet(var.address_space, 2, 2)

  service_endpoints = [
    "Microsoft.Storage",
  ]

  lifecycle {
    # TODO Remove this when azurerm 2.0 provider is released
    ignore_changes = [
      "route_table_id",
      "network_security_group_id",
    ]
  }
}

resource "azurerm_subnet" "appgw" {
  name                 = "appgw"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = cidrsubnet(var.address_space, 2, 3)

  service_endpoints = [
    "Microsoft.Storage",
  ]

  lifecycle {
    # TODO Remove this when azurerm 2.0 provider is released
    ignore_changes = [
      "route_table_id",
      "network_security_group_id",
    ]
  }
}

#
# Storage account for flow logs
#

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "network" {
  name                = format("%s%ssa", var.name, random_string.unique.result)
  resource_group_name = azurerm_resource_group.vnet.name

  location                  = azurerm_resource_group.vnet.location
  account_kind              = "StorageV2"
  account_tier              = "Standard"
  account_replication_type  = "ZRS"
  enable_https_traffic_only = true

  # TODO Not yet supported to use service endpoints together with flow logs. Not a trusted Microsoft service
  # See https://github.com/MicrosoftDocs/azure-docs/issues/5989
  # network_rules {
  #   ip_rules                   = ["127.0.0.1"]
  #   virtual_network_subnet_ids = ["${azurerm_subnet.firewall.id}"]
  # }

  tags = var.tags
}

#
# Route table
#

resource "azurerm_route_table" "public" {
  name                = "${var.name}-public-rt"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

resource "azurerm_route" "public_all" {
  name                   = "all"
  resource_group_name    = azurerm_resource_group.vnet.name
  route_table_name       = azurerm_route_table.public.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.fw.ip_configuration.0.private_ip_address
}

resource "azurerm_subnet_route_table_association" "appgw" {
  subnet_id      = azurerm_subnet.appgw.id
  route_table_id = azurerm_route_table.public.id
}

resource "azurerm_subnet_route_table_association" "mgmt" {
  subnet_id      = azurerm_subnet.mgmt.id
  route_table_id = azurerm_route_table.public.id
}

#
# Network security groups
#

resource "azurerm_network_security_group" "mgmt" {
  name                = "subnet-mgmt-nsg"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-load-balancer"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-other"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  tags = "${var.tags}"

  # TODO Does not exist as a resource...yet
  provisioner "local-exec" {
    command = "az network watcher flow-log configure -g ${azurerm_resource_group.vnet.name} --enabled true --log-version 2 --nsg subnet-mgmt-nsg --storage-account ${azurerm_storage_account.network.id} --traffic-analytics true --workspace ${var.log_analytics_workspace_id} --subscription ${data.azurerm_client_config.current.subscription_id}"
  }
}

resource "azurerm_monitor_diagnostic_setting" "mgmt" {
  name                       = "mgmt-nsg-log-analytics"
  target_resource_id         = azurerm_network_security_group.mgmt.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "NetworkSecurityGroupEvent"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "NetworkSecurityGroupRuleCounter"

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "mgmt" {
  subnet_id                 = azurerm_subnet.mgmt.id
  network_security_group_id = azurerm_network_security_group.mgmt.id
}

resource "azurerm_network_security_group" "appgw" {
  name                = "subnet-appgw-nsg"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  security_rule {
    name                       = "allow-all-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-all-https"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-load-balancer"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-appgw-v1"
    priority                   = 400
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "65503-65534"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-other"
    priority                   = 500
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  tags = var.tags

  # TODO Use new resource when exists
  provisioner "local-exec" {
    command = "az network watcher flow-log configure -g ${azurerm_resource_group.vnet.name} --enabled true --log-version 2 --nsg subnet-appgw-nsg --storage-account ${azurerm_storage_account.network.id} --traffic-analytics true --workspace ${var.log_analytics_workspace_id} --subscription ${data.azurerm_client_config.current.subscription_id}"
  }
}

resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "appgw-nsg-log-analytics"
  target_resource_id         = azurerm_network_security_group.appgw.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "NetworkSecurityGroupEvent"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "NetworkSecurityGroupRuleCounter"

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

#
# Firewall
#

resource "azurerm_public_ip" "fw" {
  name                = "${var.name}-fw-pip"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  allocation_method = "Static"
  sku               = "Standard"
  domain_name_label = "${var.name}fw"

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "fw_pip" {
  name                       = "fw-pip-log-analytics"
  target_resource_id         = azurerm_public_ip.fw.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "DDoSProtectionNotifications"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "DDoSMitigationFlowLogs"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "DDoSMitigationReports"

    retention_policy {
      enabled = false
    }
  }

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_firewall" "fw" {
  name                = "${var.name}-fw"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.fw.id
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "fw" {
  name                       = "fw-log-analytics"
  target_resource_id         = azurerm_firewall.fw.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "AzureFirewallApplicationRule"

    retention_policy {
      enabled = false
    }
  }

  log {
    category = "AzureFirewallNetworkRule"

    retention_policy {
      enabled = false
    }
  }

  metric {
    category = "AllMetrics"

    retention_policy {
      enabled = false
    }
  }
}

resource "azurerm_firewall_application_rule_collection" "fw" {
  count               = length(var.firewall_application_rules)
  name                = "fwapprule${count.index}"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = azurerm_resource_group.vnet.name
  priority            = 100 + 100 * count.index
  action              = "Allow"

  rule {
    name             = var.firewall_application_rules[count.index].name
    source_addresses = var.firewall_application_rules[count.index].source_addresses
    target_fqdns     = var.firewall_application_rules[count.index].target_fqdns

    protocol {
      type = var.firewall_application_rules[count.index].protocol.type
      port = var.firewall_application_rules[count.index].protocol.port
    }
  }
}

resource "azurerm_firewall_network_rule_collection" "fw" {
  count               = length(var.firewall_network_rules)
  name                = "fwnetrule${count.index}"
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = azurerm_resource_group.vnet.name
  priority            = 100 + 100 * count.index
  action              = "Allow"

  rule {
    name                  = var.firewall_network_rules[count.index].name
    source_addresses      = var.firewall_network_rules[count.index].source_addresses
    destination_ports     = var.firewall_network_rules[count.index].destination_ports
    destination_addresses = var.firewall_network_rules[count.index].destination_addresses
    protocols             = var.firewall_network_rules[count.index].protocols
  }
}