output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "vnet_resource_group_name" {
  value = var.resource_group_name
}

output "vnet_name" {
  value = azurerm_virtual_network.vnet.name
}

output "subnets" {
  value = {
    gateway    = azurerm_subnet.gateway.id
    firewall   = azurerm_subnet.firewall.id
    management = azurerm_subnet.mgmt.id
    dmz        = azurerm_subnet.dmz.id
  }
}

output "firewall_private_ip" {
  value = azurerm_firewall.fw.ip_configuration.0.private_ip_address
}

output "private_dns" {
  value = var.private_dns_zone == null ? null : {
    id = azurerm_private_dns_zone.main[0].id
    name = azurerm_private_dns_zone.main[0].name
  }
}