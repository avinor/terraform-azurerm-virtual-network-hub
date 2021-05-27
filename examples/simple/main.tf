module "hub" {
  source = "../../"

  name                = "hub"
  resource_group_name = "networking-hub"
  location            = "westeurope"
  address_space       = "10.0.0.0/24"

  public_ip_names = [
    "fw-public"
  ]
}