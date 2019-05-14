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
  description = "The full address space that is used the virtual network. Requires at least a /22 address space."
}

variable "log_analytics_workspace_id" {
  description = "Specifies the ID of a Log Analytics Workspace where Diagnostics Data should be sent."
}

variable "firewall_application_rules" {
  description = "List of application rules to apply to firewall."
  type        = list(object({ name = string, source_addresses = list(string), target_fqdns = list(string), protocol = object({ type = string, port = string }) }))
  default     = []
}

variable "firewall_network_rules" {
  description = "List of network rules to apply to firewall."
  type        = list(object({ name = string, source_addresses = list(string), destination_ports = list(string), destination_addresses = list(string), protocols = list(string) }))
  default     = []
}

variable "create_ddos_plan" {
  description = "Create a DDos protection plan and attach to vnet."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources created."
  type        = map(string)
  default     = {}
}
