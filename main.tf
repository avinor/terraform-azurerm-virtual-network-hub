terraform {
  required_version = ">= 0.12.0"
  required_providers {
    azurerm = "~> 1.36.0"
  }
}

locals {
  default_nsg_rule = {
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    description                                = null
    source_port_range                          = null
    source_port_ranges                         = null
    destination_port_range                     = null
    destination_port_ranges                    = null
    source_address_prefix                      = null
    source_address_prefixes                    = null
    source_application_security_group_ids      = null
    destination_address_prefix                 = null
    destination_address_prefixes               = null
    destination_application_security_group_ids = null
  }
  default_mgmt_nsg_rules = [
    {
      name                       = "allow-load-balancer"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
    },
    {
      name                       = "deny-other"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
  ]

  merged_mgmt_nsg_rules = flatten([
    for nsg in var.management_nsg_rules : merge(local.default_nsg_rule, nsg)
  ])

  merged_dmz_nsg_rules = flatten([
    for nsg in var.dmz_nsg_rules : merge(local.default_nsg_rule, nsg)
  ])

  dnat_rules = [for rule in var.firewall_nat_rules : rule if rule.action == "Dnat"]
  snat_rules = [for rule in var.firewall_nat_rules : rule if rule.action == "Snat"]

  net_allow_rules = [for rule in var.firewall_network_rules : rule if rule.action == "Allow"]
  net_deny_rules  = [for rule in var.firewall_network_rules : rule if rule.action == "Deny"]

  app_allow_rules = [for rule in var.firewall_application_rules : rule if rule.action == "Allow"]
  app_deny_rules  = [for rule in var.firewall_application_rules : rule if rule.action == "Deny"]
}

data "azurerm_client_config" "current" {}

#
# Network watcher
# Following Azure naming standard to not create twice
#

resource "azurerm_resource_group" "netwatcher" {
  count    = var.netwatcher != null ? 1 : 0
  name     = "NetworkWatcherRG"
  location = var.netwatcher.resource_group_location

  tags = var.tags
}

resource "azurerm_network_watcher" "netwatcher" {
  count               = var.netwatcher != null ? 1 : 0
  name                = "NetworkWatcher_${var.location}"
  location            = var.location
  resource_group_name = azurerm_resource_group.netwatcher.0.name

  tags = var.tags
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
  count               = var.create_ddos_plan ? 1 : 0
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
    for_each = var.create_ddos_plan ? [true] : []
    iterator = ddos
    content {
      id     = azurerm_ddos_protection_plan.vnet.id
      enable = true
    }
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "peering" {
  count                = length(var.peering_assignment)
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = var.peering_assignment[count.index]
}

resource "azurerm_monitor_diagnostic_setting" "vnet" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "vnet-analytics"
  target_resource_id         = azurerm_virtual_network.vnet.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  log {
    category = "VMProtectionAlerts"

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

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefix       = cidrsubnet(var.address_space, 2, 0)

  service_endpoints = [
    "Microsoft.AzureActiveDirectory",
    "Microsoft.AzureCosmosDB",
    "Microsoft.EventHub",
    "Microsoft.KeyVault",
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

resource "azurerm_subnet" "mgmt" {
  name                 = "Management"
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

resource "azurerm_subnet" "dmz" {
  name                 = "DMZ"
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

module "storage" {
  source  = "avinor/storage-account/azurerm"
  version = "1.4.0"

  name                = var.name
  resource_group_name = azurerm_resource_group.vnet.name
  location            = azurerm_resource_group.vnet.location

  enable_advanced_threat_protection = true

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

resource "azurerm_route_table" "out" {
  name                = "${var.name}-outbound-rt"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

resource "azurerm_route" "fw" {
  name                   = "firewall"
  resource_group_name    = azurerm_resource_group.vnet.name
  route_table_name       = azurerm_route_table.out.name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.fw.ip_configuration.0.private_ip_address
}

resource "azurerm_subnet_route_table_association" "mgmt" {
  subnet_id      = azurerm_subnet.mgmt.id
  route_table_id = azurerm_route_table.out.id
}

resource "azurerm_subnet_route_table_association" "dmz" {
  subnet_id      = azurerm_subnet.dmz.id
  route_table_id = azurerm_route_table.out.id
}

#
# Network security groups
#

resource "azurerm_network_security_group" "mgmt" {
  name                = "subnet-mgmt-nsg"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

resource "null_resource" "mgmt_logs" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  # TODO Use new resource when exists
  provisioner "local-exec" {
    command = "az network watcher flow-log configure -g ${azurerm_resource_group.vnet.name} --enabled true --log-version 2 --nsg ${azurerm_network_security_group.mgmt.name} --storage-account ${module.storage.id} --traffic-analytics true --workspace ${var.log_analytics_workspace_id} --subscription ${data.azurerm_client_config.current.subscription_id}"
  }

  depends_on = ["azurerm_network_security_group.mgmt"]
}

resource "azurerm_network_security_rule" "mgmt" {
  count                       = length(local.merged_mgmt_nsg_rules)
  resource_group_name         = azurerm_resource_group.vnet.name
  network_security_group_name = azurerm_network_security_group.mgmt.name
  priority                    = 100 + 100 * count.index

  name                                       = local.merged_mgmt_nsg_rules[count.index].name
  direction                                  = local.merged_mgmt_nsg_rules[count.index].direction
  access                                     = local.merged_mgmt_nsg_rules[count.index].access
  protocol                                   = local.merged_mgmt_nsg_rules[count.index].protocol
  description                                = local.merged_mgmt_nsg_rules[count.index].description
  source_port_range                          = local.merged_mgmt_nsg_rules[count.index].source_port_range
  source_port_ranges                         = local.merged_mgmt_nsg_rules[count.index].source_port_ranges
  destination_port_range                     = local.merged_mgmt_nsg_rules[count.index].destination_port_range
  destination_port_ranges                    = local.merged_mgmt_nsg_rules[count.index].destination_port_ranges
  source_address_prefix                      = local.merged_mgmt_nsg_rules[count.index].source_address_prefix
  source_address_prefixes                    = local.merged_mgmt_nsg_rules[count.index].source_address_prefixes
  source_application_security_group_ids      = local.merged_mgmt_nsg_rules[count.index].source_application_security_group_ids
  destination_address_prefix                 = local.merged_mgmt_nsg_rules[count.index].destination_address_prefix
  destination_address_prefixes               = local.merged_mgmt_nsg_rules[count.index].destination_address_prefixes
  destination_application_security_group_ids = local.merged_mgmt_nsg_rules[count.index].destination_application_security_group_ids
}

resource "azurerm_monitor_diagnostic_setting" "mgmt" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
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

resource "azurerm_network_security_group" "dmz" {
  name                = "subnet-dmz-nsg"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

resource "null_resource" "dmz_logs" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  # TODO Use new resource when exists
  provisioner "local-exec" {
    command = "az network watcher flow-log configure -g ${azurerm_resource_group.vnet.name} --enabled true --log-version 2 --nsg ${azurerm_network_security_group.dmz.name} --storage-account ${module.storage.id} --traffic-analytics true --workspace ${var.log_analytics_workspace_id} --subscription ${data.azurerm_client_config.current.subscription_id}"
  }

  depends_on = ["azurerm_network_security_group.dmz"]
}

resource "azurerm_network_security_rule" "dmz" {
  count                       = length(local.merged_dmz_nsg_rules)
  resource_group_name         = azurerm_resource_group.vnet.name
  network_security_group_name = azurerm_network_security_group.dmz.name
  priority                    = 100 + 100 * count.index

  name                                       = local.merged_dmz_nsg_rules[count.index].name
  direction                                  = local.merged_dmz_nsg_rules[count.index].direction
  access                                     = local.merged_dmz_nsg_rules[count.index].access
  protocol                                   = local.merged_dmz_nsg_rules[count.index].protocol
  description                                = local.merged_dmz_nsg_rules[count.index].description
  source_port_range                          = local.merged_dmz_nsg_rules[count.index].source_port_range
  source_port_ranges                         = local.merged_dmz_nsg_rules[count.index].source_port_ranges
  destination_port_range                     = local.merged_dmz_nsg_rules[count.index].destination_port_range
  destination_port_ranges                    = local.merged_dmz_nsg_rules[count.index].destination_port_ranges
  source_address_prefix                      = local.merged_dmz_nsg_rules[count.index].source_address_prefix
  source_address_prefixes                    = local.merged_dmz_nsg_rules[count.index].source_address_prefixes
  source_application_security_group_ids      = local.merged_dmz_nsg_rules[count.index].source_application_security_group_ids
  destination_address_prefix                 = local.merged_dmz_nsg_rules[count.index].destination_address_prefix
  destination_address_prefixes               = local.merged_dmz_nsg_rules[count.index].destination_address_prefixes
  destination_application_security_group_ids = local.merged_dmz_nsg_rules[count.index].destination_application_security_group_ids
}

resource "azurerm_monitor_diagnostic_setting" "dmz" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "dmz-nsg-log-analytics"
  target_resource_id         = azurerm_network_security_group.dmz.id
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

resource "azurerm_subnet_network_security_group_association" "dmz" {
  subnet_id                 = azurerm_subnet.dmz.id
  network_security_group_id = azurerm_network_security_group.dmz.id
}

#
# Private DNS
#

resource "azurerm_private_dns_zone" "main" {
  count               = var.private_dns_zone != null ? 1 : 0
  name                = var.private_dns_zone
  resource_group_name = azurerm_resource_group.vnet.name

  tags = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "main" {
  count                 = var.private_dns_zone != null ? 1 : 0
  name                  = "${var.name}-link"
  resource_group_name   = azurerm_resource_group.vnet.name
  private_dns_zone_name = azurerm_private_dns_zone.main[0].name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  registration_enabled  = true

  tags = var.tags
}

resource "azurerm_role_assignment" "dns" {
  count                = var.private_dns_zone != null ? length(var.peering_assignment) : 0
  scope                = azurerm_private_dns_zone.main[0].id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = var.peering_assignment[count.index]
}

#
# Firewall
#

resource "azurerm_public_ip_prefix" "fw" {
  name                = "${var.name}-pip-prefix"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  prefix_length = var.public_ip_prefix_length

  tags = var.tags
}

resource "random_string" "dns" {
  count   = length(var.public_ip_names)
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_public_ip" "fw" {
  count               = length(var.public_ip_names)
  name                = "${var.name}-fw-${var.public_ip_names[count.index]}-pip"
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name

  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = format("%s%sfw%s", lower(replace(var.name, "/[[:^alnum:]]/", "")), lower(replace(var.public_ip_names[count.index], "/[[:^alnum:]]/", "")), random_string.dns[count.index].result)
  public_ip_prefix_id = azurerm_public_ip_prefix.fw.id

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "fw_pip" {
  count                      = var.log_analytics_workspace_id != null ? length(var.public_ip_names) : 0
  name                       = "fw-pip-log-analytics"
  target_resource_id         = azurerm_public_ip.fw[count.index].id
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

  zones = var.firewall_zones

  ip_configuration {
    name                 = var.public_ip_names[0]
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.fw[0].id
  }

  # Avoid changes when adding more public ips manually to firewall
  lifecycle {
    ignore_changes = [
      "ip_configuration",
    ]
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "fw" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
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

resource "azurerm_firewall_application_rule_collection" "allow" {
  count               = length(local.app_allow_rules)
  name                = local.app_allow_rules[count.index].name
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = azurerm_resource_group.vnet.name
  priority            = 100 * (count.index + 1)
  action              = "Allow"

  rule {
    name             = local.app_allow_rules[count.index].name
    source_addresses = local.app_allow_rules[count.index].source_addresses
    target_fqdns     = local.app_allow_rules[count.index].target_fqdns

    protocol {
      type = local.app_allow_rules[count.index].protocol.type
      port = local.app_allow_rules[count.index].protocol.port
    }
  }
}

resource "azurerm_firewall_application_rule_collection" "deny" {
  count               = length(local.app_deny_rules)
  name                = local.app_deny_rules[count.index].name
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = azurerm_resource_group.vnet.name
  priority            = 10000 + 100 * count.index
  action              = "Deny"

  rule {
    name             = local.app_deny_rules[count.index].name
    source_addresses = local.app_deny_rules[count.index].source_addresses
    target_fqdns     = local.app_deny_rules[count.index].target_fqdns

    protocol {
      type = local.app_deny_rules[count.index].protocol.type
      port = local.app_deny_rules[count.index].protocol.port
    }
  }
}

resource "azurerm_firewall_network_rule_collection" "allow" {
  count               = length(local.net_allow_rules)
  name                = local.net_allow_rules[count.index].name
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = azurerm_resource_group.vnet.name
  priority            = 100 * (count.index + 1)
  action              = "Allow"

  rule {
    name                  = local.net_allow_rules[count.index].name
    source_addresses      = local.net_allow_rules[count.index].source_addresses
    destination_ports     = local.net_allow_rules[count.index].destination_ports
    destination_addresses = local.net_allow_rules[count.index].destination_addresses
    protocols             = local.net_allow_rules[count.index].protocols
  }
}

resource "azurerm_firewall_network_rule_collection" "deny" {
  count               = length(local.net_deny_rules)
  name                = local.net_deny_rules[count.index].name
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = azurerm_resource_group.vnet.name
  priority            = 10000 + 100 * count.index
  action              = "Deny"

  rule {
    name                  = local.net_deny_rules[count.index].name
    source_addresses      = local.net_deny_rules[count.index].source_addresses
    destination_ports     = local.net_deny_rules[count.index].destination_ports
    destination_addresses = local.net_deny_rules[count.index].destination_addresses
    protocols             = local.net_deny_rules[count.index].protocols
  }
}

resource "azurerm_firewall_nat_rule_collection" "dnat" {
  count               = length(local.dnat_rules)
  name                = local.dnat_rules[count.index].name
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = azurerm_resource_group.vnet.name
  priority            = 100 * (count.index + 1)
  action              = "Dnat"

  rule {
    name                  = local.dnat_rules[count.index].name
    source_addresses      = local.dnat_rules[count.index].source_addresses
    destination_ports     = local.dnat_rules[count.index].destination_ports
    destination_addresses = [for dest in local.dnat_rules[count.index].destination_addresses : contains(var.public_ip_names, dest) ? azurerm_public_ip.fw[index(var.public_ip_names, dest)].ip_address : dest]
    protocols             = local.dnat_rules[count.index].protocols
    translated_address    = local.dnat_rules[count.index].translated_address
    translated_port       = local.dnat_rules[count.index].translated_port
  }
}

resource "azurerm_firewall_nat_rule_collection" "snat" {
  count               = length(local.snat_rules)
  name                = local.snat_rules[count.index].name
  azure_firewall_name = azurerm_firewall.fw.name
  resource_group_name = azurerm_resource_group.vnet.name
  priority            = 10000 + 100 * count.index
  action              = "Snat"

  rule {
    name                  = local.snat_rules[count.index].name
    source_addresses      = local.snat_rules[count.index].source_addresses
    destination_ports     = local.snat_rules[count.index].destination_ports
    destination_addresses = [for dest in local.snat_rules[count.index].destination_addresses : contains(var.public_ip_names, dest) ? azurerm_public_ip.fw[index(var.public_ip_names, dest)].ip_address : dest]
    protocols             = local.snat_rules[count.index].protocols
    translated_address    = local.snat_rules[count.index].translated_address
    translated_port       = local.snat_rules[count.index].translated_port
  }
}