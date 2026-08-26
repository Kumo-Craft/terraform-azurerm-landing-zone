# vwan

Creates an Azure Virtual WAN with virtual hubs, VPN gateways, VPN sites, and site-to-site connections for multi-site hybrid connectivity.

## Usage

### Standalone

```hcl
module "vwan" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/vwan?ref=v0.2.17"
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/vwan"
}

inputs = {
  name                = "vwan-con-prod-gwc-01"
  location            = include.root.inputs.location
  resource_group_name = dependency.rg.outputs.name
  tags                = include.root.inputs.common_tags

  virtual_hubs = {
    gwc = {
      address_prefix = "10.238.200.0/23"
      vpn_gateway    = { scale_unit = 1 }
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

### Virtual WAN Core

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name` | `string` | — | yes | Name of the Virtual WAN |
| `location` | `string` | — | yes | Azure region where resources will be created |
| `resource_group_name` | `string` | — | yes | Name of the resource group |
| `type` | `string` | `"Standard"` | no | Type of Virtual WAN (Basic or Standard) |
| `disable_vpn_encryption` | `bool` | `false` | no | Whether to disable VPN encryption for the Virtual WAN |
| `allow_branch_to_branch_traffic` | `bool` | `true` | no | Whether to allow branch-to-branch traffic through the Virtual WAN |
| `office365_local_breakout_category` | `string` | `"None"` | no | Office 365 local breakout category (None, Optimize, OptimizeAndAllow, All) |
| `tags` | `map(string)` | `{}` | no | Tags to apply to all resources |

### Virtual Hubs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `virtual_hubs` | `map(object)` | `{}` | no | Map of Virtual Hubs to create |
| `virtual_hub_connections` | `map(object)` | `{}` | no | Map of Virtual Hub VNet connections |
| `bgp_connections` | `map(object)` | `{}` | no | Map of Virtual Hub BGP connections (NVA peering) |

### VPN

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `vpn_sites` | `map(object)` | `{}` | no | Map of VPN Sites to create |
| `vpn_connections` | `map(object)` | `{}` | no | Map of VPN Site connections to Virtual Hubs |
| `vpn_server_configurations` | `map(object)` | `{}` | no | Map of VPN Server Configurations (for Point-to-Site). Supports Certificate (`client_root_certificates`), Entra ID / AAD (`azure_active_directory_authentication`) and `vpn_protocols` (IkeV2 / OpenVPN). |
| `p2s_gateways` | `map(object)` | `{}` | no | Map of Point-to-Site VPN Gateways |

## Outputs

| Name | Description |
|------|-------------|
| `resource` | The complete Virtual WAN resource object |
| `virtual_wan_id` | ID of the Virtual WAN |
| `virtual_wan_name` | Name of the Virtual WAN |
| `virtual_hub_ids` | Map of Virtual Hub IDs |
| `virtual_hub_names` | Map of Virtual Hub names |
| `virtual_hub_default_route_table_ids` | Map of Virtual Hub default route table IDs |
| `virtual_hub_connection_ids` | Map of Virtual Hub Connection IDs |
| `vpn_gateway_ids` | Map of VPN Gateway IDs |
| `vpn_gateway_bgp_settings` | Map of VPN Gateway BGP settings |
| `vpn_gateway_public_ips` | Map of VPN Gateway public IP addresses (instance 0 and 1) |
| `express_route_gateway_ids` | Map of ExpressRoute Gateway IDs |
| `firewall_ids` | Map of Azure Firewall IDs |
| `firewall_private_ips` | Map of Azure Firewall private IP addresses |
| `vpn_server_configuration_ids` | Map of VPN Server Configuration IDs |
| `p2s_gateway_ids` | Map of Point-to-Site VPN Gateway IDs |
| `bgp_connection_ids` | Map of Virtual Hub BGP Connection IDs |
| `vpn_site_ids` | Map of VPN Site IDs |
| `vpn_connection_ids` | Map of VPN Connection IDs |
