# VNetPeering

Creates Azure VNet peerings. Each entry in the map creates one peering direction. For bidirectional peering, create two entries (A→B and B→A).

## Usage

### Standalone

```hcl
module "vnet_peering" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/VNetPeering?ref=v0.2.5"

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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_virtual_network_peering.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network_peering) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| peerings | Map of VNet peerings to create. The map key is the peering name.<br><br>- `virtual_network_name`                  - (Required) Local VNet name.<br>- `resource_group_name`                   - (Required) Local VNet resource group name.<br>- `remote_virtual_network_id`             - (Required) Remote VNet resource ID.<br>- `name`                                  - (Optional) Azure-side peering name override. Defaults to the map key. Use this when the map key is a fixed/internal identifier (e.g. composition from a Stack module) but the Azure-side resource name needs to differ.<br>- `allow_forwarded_traffic`               - (Optional) Allow forwarded traffic. Defaults to true.<br>- `allow_gateway_transit`                 - (Optional) Allow gateway transit. Defaults to false.<br>- `allow_virtual_network_access`          - (Optional) Allow VNet access. Defaults to true.<br>- `use_remote_gateways`                   - (Optional) Use remote gateways. Defaults to false.<br>- `triggers`                              - (Optional) Map of arbitrary strings that, when changed, force the peering to be re-created. Use to trigger re-evaluation when the remote VNet address space expands (workaround for the silent Disconnected state Azure produces). Defaults to {}.<br>- `peer_complete_virtual_networks_enabled`- (Optional) Controls full-VNet vs subnet-scoped peering. Defaults to true (full-VNet, preserves current behavior). Set to false to enable subnet-scoped peering and supply local\_subnet\_names / remote\_subnet\_names.<br>- `local_subnet_names`                    - (Optional) List of local subnet names to include in a subnet-scoped peering. Only valid when peer\_complete\_virtual\_networks\_enabled = false. Defaults to [].<br>- `remote_subnet_names`                   - (Optional) List of remote subnet names to include in a subnet-scoped peering. Only valid when peer\_complete\_virtual\_networks\_enabled = false. Defaults to [].<br>- `only_ipv6_peering_enabled`             - (Optional) Restrict peering to IPv6 traffic only. Defaults to false. | <pre>map(object({<br>    virtual_network_name                   = string<br>    resource_group_name                    = string<br>    remote_virtual_network_id              = string<br>    name                                   = optional(string)<br>    allow_forwarded_traffic                = optional(bool, true)<br>    allow_gateway_transit                  = optional(bool, false)<br>    allow_virtual_network_access           = optional(bool, true)<br>    use_remote_gateways                    = optional(bool, false)<br>    triggers                               = optional(map(string), {})<br>    peer_complete_virtual_networks_enabled = optional(bool, true)<br>    local_subnet_names                     = optional(list(string), [])<br>    remote_subnet_names                    = optional(list(string), [])<br>    only_ipv6_peering_enabled              = optional(bool, false)<br>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of peering key => peering ID |
| resources | Map of peering key => complete peering resource object |
<!-- END_TF_DOCS -->
