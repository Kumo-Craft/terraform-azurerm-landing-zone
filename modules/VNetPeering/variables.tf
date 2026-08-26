###############################################################
# MODULE: VNetPeering - Variables
###############################################################

variable "peerings" {
  description = <<-EOT
  Map of VNet peerings to create. The map key is the peering name.

  - `virtual_network_name`                  - (Required) Local VNet name.
  - `resource_group_name`                   - (Required) Local VNet resource group name.
  - `remote_virtual_network_id`             - (Required) Remote VNet resource ID.
  - `name`                                  - (Optional) Azure-side peering name override. Defaults to the map key. Use this when the map key is a fixed/internal identifier (e.g. composition from a Stack module) but the Azure-side resource name needs to differ.
  - `allow_forwarded_traffic`               - (Optional) Allow forwarded traffic. Defaults to true.
  - `allow_gateway_transit`                 - (Optional) Allow gateway transit. Defaults to false.
  - `allow_virtual_network_access`          - (Optional) Allow VNet access. Defaults to true.
  - `use_remote_gateways`                   - (Optional) Use remote gateways. Defaults to false.
  - `triggers`                              - (Optional) Map of arbitrary strings that, when changed, force the peering to be re-created. Use to trigger re-evaluation when the remote VNet address space expands (workaround for the silent Disconnected state Azure produces). Defaults to {}.
  - `peer_complete_virtual_networks_enabled`- (Optional) Controls full-VNet vs subnet-scoped peering. Defaults to true (full-VNet, preserves current behavior). Set to false to enable subnet-scoped peering and supply local_subnet_names / remote_subnet_names.
  - `local_subnet_names`                    - (Optional) List of local subnet names to include in a subnet-scoped peering. Only valid when peer_complete_virtual_networks_enabled = false. Defaults to [].
  - `remote_subnet_names`                   - (Optional) List of remote subnet names to include in a subnet-scoped peering. Only valid when peer_complete_virtual_networks_enabled = false. Defaults to [].
  - `only_ipv6_peering_enabled`             - (Optional) Restrict peering to IPv6 traffic only. Defaults to false.
  EOT
  type = map(object({
    virtual_network_name                   = string
    resource_group_name                    = string
    remote_virtual_network_id              = string
    name                                   = optional(string)
    allow_forwarded_traffic                = optional(bool, true)
    allow_gateway_transit                  = optional(bool, false)
    allow_virtual_network_access           = optional(bool, true)
    use_remote_gateways                    = optional(bool, false)
    triggers                               = optional(map(string), {})
    peer_complete_virtual_networks_enabled = optional(bool, true)
    local_subnet_names                     = optional(list(string), [])
    remote_subnet_names                    = optional(list(string), [])
    only_ipv6_peering_enabled              = optional(bool, false)
  }))
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.peerings :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", v.remote_virtual_network_id))
    ])
    error_message = "remote_virtual_network_id must be a valid Azure Virtual Network resource ID."
  }

  validation {
    condition = alltrue([
      for k, v in var.peerings :
      v.peer_complete_virtual_networks_enabled ? (length(v.local_subnet_names) == 0 && length(v.remote_subnet_names) == 0) : true
    ])
    error_message = "local_subnet_names / remote_subnet_names must be empty when peer_complete_virtual_networks_enabled = true (full-VNet peering). Set peer_complete_virtual_networks_enabled = false to opt into subnet-scoped peering."
  }
}
