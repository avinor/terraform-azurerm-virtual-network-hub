module "hub" {
  source = "../../"

  name                = "hub"
  resource_group_name = "networking-hub"
  location            = "westeurope"
  address_space       = "10.0.0.0/24"

  diagnostics = {
    destination   = "/subscription/xxxx-xxxx/.../resource_id"
    eventhub_name = null
    logs          = ["all"]
    metrics       = ["all"]
  }

  public_ip_names = [
    "fw-public"
  ]

  firewall_application_rules = [
    {
      name             = "microsoft"
      action           = "Allow"
      source_addresses = ["10.0.0.0/8"]
      target_fqdns     = ["*.microsoft.com"]
      protocol = {
        type = "Http"
        port = "80"
      }
    },
  ]

  firewall_network_rules = [
    {
      name                  = "ntp"
      action                = "Allow"
      source_addresses      = ["10.0.0.0/8"]
      destination_ports     = ["123"]
      destination_addresses = ["*"]
      protocols             = ["UDP"]
    },
  ]
}