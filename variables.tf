variable "enable_advanced_threat_protection" {
  description = "Boolean flag which controls if advanced threat protection is enabled."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of hub network."
}

variable "resource_group_name" {
  description = "Name of resource group to deploy resources in."
}

variable "location" {
  description = "The Azure Region in which to create resource."
}

variable "address_space" {
  description = "The full address space that is used the virtual network. Requires at least a /24 address space."
}

variable "diagnostics" {
  description = "Diagnostic settings for those resources that support it. See README.md for details on configuration."
  type = object({
    destination   = string
    eventhub_name = optional(string)
    logs          = list(string)
    metrics       = list(string)
  })
  default = null
}

variable "service_endpoints" {
  description = "Service endpoints to add to the firewall subnet."
  type        = list(string)
  default = [
    "Microsoft.AzureActiveDirectory",
    "Microsoft.AzureCosmosDB",
    "Microsoft.EventHub",
    "Microsoft.KeyVault",
    "Microsoft.ServiceBus",
    "Microsoft.Sql",
    "Microsoft.Storage",
  ]
}

variable "management_nsg_rules" {
  description = "Network security rules to add to management subnet. See README for details on how to setup."
  type        = list(any)
  default     = []
}

variable "dmz_nsg_rules" {
  description = "Network security rules to add to dmz subnet. See README for details on how to setup."
  type        = list(any)
  default     = []
}

variable "public_ip_prefix_length" {
  description = "Specifies the number of bits of the prefix. The value can be set between 24 (256 addresses) and 31 (2 addresses)."
  type        = number
  default     = 30
}

variable "public_ip_names" {
  description = "Public ips is a list of ip names that are connected to the firewall. At least one is required."
  type        = list(string)
}

variable "firewall_zones" {
  description = "A collection of availability zones to spread the Firewall over."
  type        = list(string)
  default     = null
}

variable "firewall_application_rules" {
  description = "List of application rules to apply to firewall."
  type = list(object({
    name             = string
    action           = string
    source_addresses = list(string)
    target_fqdns     = list(string)
    protocol = object({
      type = string
      port = string
    })
  }))
  default = []
}

variable "firewall_network_rules" {
  description = "List of network rules to apply to firewall."
  type = list(object({
    name                  = string
    action                = string
    source_addresses      = list(string)
    destination_ports     = list(string)
    destination_addresses = list(string)
    protocols             = list(string)
  }))
  default = []
}

variable "firewall_nat_rules" {
  description = "List of nat rules to apply to firewall."
  type = list(object({
    name                  = string
    action                = string
    source_addresses      = list(string)
    destination_ports     = list(string)
    destination_addresses = list(string)
    protocols             = list(string)
    translated_address    = string
    translated_port       = string
  }))
  default = []
}

variable "netwatcher" {
  description = "Properties for creating network watcher. If set it will create Network Watcher resource using standard naming standard."
  type = object({
    resource_group_location    = string
    log_analytics_workspace_id = string
    log_analytics_resource_id  = string
  })
  default = null
}

variable "peering_assignment" {
  description = "List of principal ids that should have access to peer to this Hub network. All service principals used to deploy spoke networks should have access to peer."
  type        = list(string)
  default     = []
}

variable "create_ddos_plan" {
  description = "Create a DDos protection plan and attach to vnet."
  type        = bool
  default     = false
}

variable "private_dns_zone" {
  description = "Name of private dns zone to create and associate with virtual network. This is the only zone that must be linked with registration enabled."
  default     = null
}

variable "resolvable_private_dns_zones" {
  description = "List of resolvable private dns zones to create and associate with virtual network. None of these zones must be linked with registration enabled and must only be used as resolvable."
  type        = list(string)
  default     = []
}

variable "storage_account_resource_group_create" {
  description = "Property for supporting terraform state created by older version of this module. NEVER set set this to true for new installations!"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources created."
  type        = map(string)
  default     = {}
}

variable "threat_intel_mode" {
  description = "The operation mode for threat intelligence-based filtering. Possible values are: Off, Alert, Deny and \"\"(empty string)."
  type        = string
  default     = "Deny"
}
