module "hub" {
    source = "../../"

    name = "hub"
    resource_group_name = "networking-hub"
    location = "westeurope"
    address_space = "10.0.0.0/23"
    log_analytics_workspace_id = "guid"

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