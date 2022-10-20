module "hub" {
  source = "../../"

  name                = "hub"
  resource_group_name = "networking-hub"
  location            = "westeurope"
  address_space       = "10.0.0.0/24"

  public_ip_names = [
    "fw-public"
  ]

  private_dns_zone = "cloud.mycorp.com"

  resolvable_private_dns_zones = [
    "example.postgres.database.azure.com",
    "example2.postgres.database.azure.com",
  ]

  peering_assignment = [
    "12345678-1234-1234-123456789012"
  ]

}