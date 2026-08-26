# VNetPeering

Creates Azure VNet peerings. Each entry in the map creates one peering direction. For bidirectional peering, create two entries (A→B and B→A).

## Usage

### Standalone

```hcl
module "vnet_peering" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/VNetPeering?ref=v0.2.5"

  peerings = {
    "hub-to-spoke" = {
      virtual_network_name      = "vnet-con-prod-gwc-hub"
      resource_group_name       = "rg-con-prod-gwc-network"
      remote_virtual_network_id = "/subscriptions/.../virtualNetworks/vnet-api-prod-gwc-spoke"
      allow_forwarded_traffic   = true
      allow_gateway_transit     = true
    }
    "spoke-to-hub" = {
      virtual_network_name      = "vnet-api-prod-gwc-spoke"
      resource_group_name       = "rg-api-prod-gwc-network"
      remote_virtual_network_id = "/subscriptions/.../virtualNetworks/vnet-con-prod-gwc-hub"
      allow_forwarded_traffic   = true
      use_remote_gateways       = true
    }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/VNetPeering"
}

inputs = {
  peerings = {
    "mgmt-to-nva" = {
      virtual_network_name      = dependency.network_mgmt.outputs.name
      resource_group_name       = dependency.network_mgmt.outputs.resource_group_name
      remote_virtual_network_id = dependency.network_nva.outputs.id
      allow_forwarded_traffic   = true
    }
    "nva-to-mgmt" = {
      virtual_network_name      = dependency.network_nva.outputs.name
      resource_group_name       = dependency.network_nva.outputs.resource_group_name
      remote_virtual_network_id = dependency.network_mgmt.outputs.id
      allow_forwarded_traffic   = true
    }
  }
}
```

## Requirements

| Name      | Version    |
|-----------|------------|
| terraform | >= 1.12.0  |
| azurerm   | ~> 4.0     |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| peerings | Map of VNet peerings. Key = peering name. | `map(object({...}))` | -- | Yes |

### Peering Object

| Field | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| virtual_network_name | `string` | Yes | -- | Local VNet name |
| resource_group_name | `string` | Yes | -- | Local VNet resource group |
| remote_virtual_network_id | `string` | Yes | -- | Remote VNet resource ID |
| name | `string` | No | map key | Azure-side peering name override. Use when the map key is a fixed/internal identifier (e.g. composition from a Stack module) but the Azure-side resource name needs to differ. |
| allow_forwarded_traffic | `bool` | No | `true` | Allow forwarded traffic |
| allow_gateway_transit | `bool` | No | `false` | Allow gateway transit |
| allow_virtual_network_access | `bool` | No | `true` | Allow VNet access |
| use_remote_gateways | `bool` | No | `false` | Use remote gateways |
| triggers | `map(string)` | No | `{}` | Arbitrary key/value pairs that force peering re-creation on change. Use to recover from the silent `Disconnected` state Azure produces after spoke address-space expansion. |
| peer_complete_virtual_networks_enabled | `bool` | No | `true` | Full-VNet peering when `true` (default). Set `false` to enable subnet-scoped peering and supply `local_subnet_names` / `remote_subnet_names`. |
| local_subnet_names | `list(string)` | No | `[]` | Local subnet names for subnet-scoped peering. Requires `peer_complete_virtual_networks_enabled = false`. |
| remote_subnet_names | `list(string)` | No | `[]` | Remote subnet names for subnet-scoped peering. Requires `peer_complete_virtual_networks_enabled = false`. |
| only_ipv6_peering_enabled | `bool` | No | `false` | Restrict peering to IPv6 traffic only. |

> **Cross-validator constraint (plan-time)** — `local_subnet_names` and `remote_subnet_names` MUST be empty (`[]`, the default) when `peer_complete_virtual_networks_enabled = true` (the default — full-VNet peering). To use subnet-scoped peering, set `peer_complete_virtual_networks_enabled = false` AND provide the subnet name lists. Mixing the two modes fails at `terraform plan` via the variable's `validation` block.

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of peering key => peering ID |
| resources | Map of peering key => complete peering resource object |
