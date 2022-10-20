output "vnet_id" {
  description = "Virtual network id."
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_resource_group_name" {
  description = "Virtual network resource group name."
  value       = var.resource_group_name
}

output "vnet_name" {
  description = "Virtual network name."
  value       = azurerm_virtual_network.vnet.name
}

output "subnets" {
  description = "Map with subnets created and their id. Used for network rules etc."
  value = {
    gateway    = azurerm_subnet.gateway.id
    firewall   = azurerm_subnet.firewall.id
    management = azurerm_subnet.mgmt.id
    dmz        = azurerm_subnet.dmz.id
  }
}

output "firewall_private_ip" {
  description = "Private ip of firewall."
  value       = azurerm_firewall.fw.ip_configuration.0.private_ip_address
}

output "private_dns" {
  description = "Private dns settings if configured. Id and name of private dns."
  value = var.private_dns_zone == null ? null : {
    id   = azurerm_private_dns_zone.main[0].id
    name = azurerm_private_dns_zone.main[0].name
  }
}

output "resolvable_private_dns_zones" {
  description = "Map of resolvable private dns zones settings if configured. The key is the private zone name where dots (.) is replaced with underscores (_). Value of the maps is id and name of private dns zone."
  value = {
    for k, v in azurerm_private_dns_zone.resolvable : replace(k, ".", "_") => {
      id   = azurerm_private_dns_zone.resolvable[k].id
      name = azurerm_private_dns_zone.resolvable[k].name
    }
  }
}

output "public_ip_prefix" {
  description = "Public ip prefix of firewall."
  value       = azurerm_public_ip_prefix.fw.ip_prefix
}