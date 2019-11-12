module "hub" {
    source = "../../"

    name = "hub"
    resource_group_name = "networking-hub-rg"
    location = "westeurope"
    address_space = "10.0.0.0/24"
    
    diagnostics = {
        destination = "/subscription/xxxx-xxxx/.../resource_id"
        eventhub_name = null
        logs = ["all"]
        metrics = ["all"]
    }

    public_ip_names = [
        "fw-public"
    ]

    management_nsg_rules = [
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

    firewall_application_rules = [
        {
            name = "aks"
            action = "Allow"
            source_addresses = ["10.0.0.0/8"]
            target_fqdns = [
                "*.azmk8s.io",
                "aksrepos.azurecr.io",
                "*.blob.core.windows.net",
                "mcr.microsoft.com",
                "*.cdn.mscr.io",
                "management.azure.com",
                "login.microsoftonline.com",
            ]
            protocol = {
                type = "Https"
                port = "443"
            }
        },
        {
            name = "aks-optional-80"
            action = "Allow"
            source_addresses = ["10.0.0.0/8"]
            target_fqdns = [
                "security.ubuntu.com",
                "azure.archive.ubuntu.com",
                "changelogs.ubuntu.com",
            ]
            protocol = {
                type = "Http"
                port = "80"
            }
        },
        {
            name = "aks-optional"
            action = "Allow"
            source_addresses = ["10.0.0.0/8"]
            target_fqdns = [
                "packages.microsoft.com",
                "dc.services.visualstudio.com",
                "*.opinsights.azure.com",
                "*.monitoring.azure.com",
                "gov-prod-policy-data.trafficmanager.net",
                "apt.dockerproject.org	",
                "nvidia.github.io",
            ]
            protocol = {
                type = "Https"
                port = "443"
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
        {
            name = "aks"
            action = "Allow"
            source_addresses = ["10.0.0.0/8"]
            destination_ports = ["22", "443", "9000"]
            destination_addresses = ["AzureCloud"]
            protocols = ["TCP"]
        },
    ]

}