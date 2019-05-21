module "hub" {
    source = "../../"

    name = "hub"
    resource_group_name = "networking-hub-rg"
    location = "westeurope"
    address_space = "10.0.0.0/22"
    log_analytics_workspace_id = "log_id"

    mgmt_nsg_rules = [
    {
        name = "allow-ssh"
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "VirtualNetwork"
    },
    ]

    appgw_nsg_rules = [
    {
        name                       = "allow-all-http"
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
    },
    {
        name                       = "allow-all-https"
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "*"
    },
    ]

    firewall_application_rules = [
        {
            name = "microsoft"
            action = "Allow"
            source_addresses = ["10.0.0.0/8"]
            target_fqdns = ["*.microsoft.com"]
            protocol = {
                type = "Http"
                port = "80"
            }
        },
    ]

    firewall_network_rules = [
        {
            name = "ntp"
            action = "Allow"
            source_addresses = ["10.0.0.0/8"]
            destination_ports = ["123"]
            destination_addresses = ["*"]
            protocols = ["UDP"]
        },
    ]

}