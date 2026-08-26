# vwan

Creates an Azure Virtual WAN with virtual hubs, VPN gateways, VPN sites, and site-to-site connections for multi-site hybrid connectivity.

## Usage

### Standalone

```hcl
module "vwan" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/vwan?ref=v0.2.17"
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

| Name | Source | Version |
|------|--------|---------|
| er\_gateway\_lock | ../ResourceLock | n/a |
| hub\_lock | ../ResourceLock | n/a |
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| rbac | ../RoleAssignment | n/a |
| vpn\_gateway\_lock | ../ResourceLock | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_express_route_connection.hub_er_connections](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/express_route_connection) | resource |
| [azurerm_express_route_gateway.hub_er_gateways](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/express_route_gateway) | resource |
| [azurerm_firewall.hub_firewalls](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/firewall) | resource |
| [azurerm_point_to_site_vpn_gateway.p2s_gateways](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/point_to_site_vpn_gateway) | resource |
| [azurerm_virtual_hub.hubs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_hub) | resource |
| [azurerm_virtual_hub_bgp_connection.bgp](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_hub_bgp_connection) | resource |
| [azurerm_virtual_hub_connection.connections](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_hub_connection) | resource |
| [azurerm_virtual_hub_route_table.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_hub_route_table) | resource |
| [azurerm_virtual_wan.vwan](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_wan) | resource |
| [azurerm_vpn_gateway.hub_vpn_gateways](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/vpn_gateway) | resource |
| [azurerm_vpn_gateway_connection.connections](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/vpn_gateway_connection) | resource |
| [azurerm_vpn_server_configuration.configs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/vpn_server_configuration) | resource |
| [azurerm_vpn_site.sites](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/vpn_site) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region where resources will be created | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| allow\_branch\_to\_branch\_traffic | Whether to allow branch-to-branch traffic through the Virtual WAN | `bool` | `true` | no |
| bgp\_connections | Map of Virtual Hub BGP connections (NVA peering) | <pre>map(object({<br>    virtual_hub_key            = string<br>    virtual_hub_connection_key = string<br>    peer_asn                   = number<br>    peer_ip                    = string<br>  }))</pre> | `{}` | no |
| disable\_vpn\_encryption | Whether to disable VPN encryption for the Virtual WAN | `bool` | `false` | no |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| express\_route\_connections | Map of ExpressRoute Connections binding an ExpressRoute circuit AzurePrivatePeering to a hub ER Gateway | <pre>map(object({<br>    virtual_hub_key                  = string<br>    express_route_circuit_peering_id = string<br>    authorization_key                = optional(string)<br>    routing_weight                   = optional(number, 0)<br>    internet_security_enabled        = optional(bool, false)<br>  }))</pre> | `{}` | no |
| lock | Controls the Resource Lock configuration for this resource.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit Virtual WAN name override. If null, computed from subscription\_acronym / environment / region\_code / workload via the Naming submodule. | `string` | `null` | no |
| office365\_local\_breakout\_category | Office 365 local breakout category (None, Optimize, OptimizeAndAllow, All) | `string` | `"None"` | no |
| p2s\_gateways | Map of Point-to-Site VPN Gateways | <pre>map(object({<br>    virtual_hub_key              = string<br>    vpn_server_configuration_key = string<br>    scale_unit                   = optional(number, 1)<br>    dns_servers                  = optional(list(string), [])<br><br>    connection_configuration = object({<br>      name                    = string<br>      client_address_prefixes = list(string)<br>    })<br>  }))</pre> | `{}` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | Map of role assignments at the Virtual WAN scope. Common patterns: 'Network Contributor' for network team granting management over the WAN. Default principal\_type='ServicePrincipal' (network resources rarely user-assigned). | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, con, idn, sec) | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| type | Type of Virtual WAN (Basic or Standard) | `string` | `"Standard"` | no |
| virtual\_hub\_connections | Map of Virtual Hub VNet connections | <pre>map(object({<br>    virtual_hub_key           = string<br>    remote_virtual_network_id = string<br>    internet_security_enabled = optional(bool, false)<br><br>    routing = optional(object({<br>      associated_route_table_id                   = optional(string)<br>      inbound_route_map_id                        = optional(string)<br>      outbound_route_map_id                       = optional(string)<br>      static_vnet_local_route_override_criteria   = optional(string)<br>      static_vnet_propagate_static_routes_enabled = optional(bool, true)<br><br>      propagated_route_table = optional(object({<br>        labels          = optional(set(string))<br>        route_table_ids = optional(list(string))<br>      }))<br><br>      static_vnet_route = optional(list(object({<br>        name                = string<br>        address_prefixes    = set(string)<br>        next_hop_ip_address = optional(string)<br>      })), [])<br>    }))<br>  }))</pre> | `{}` | no |
| virtual\_hubs | Map of Virtual Hubs to create.<br><br>routes[*].next\_hop\_resource\_id must be the full ARM resource ID of an existing<br>hub virtual network connection (e.g. /subscriptions/.../hubVirtualNetworkConnections/...).<br>It is NOT an IP address — the IP semantic belongs to the legacy inline azurerm\_virtual\_hub<br>route block which does NOT apply to azurerm\_virtual\_hub\_route\_table. | <pre>map(object({<br>    address_prefix                   = string<br>    location                         = optional(string)<br>    sku                              = optional(string, "Standard")<br>    hub_routing_preference           = optional(string, "ExpressRoute")<br>    branch_to_branch_traffic_enabled = optional(bool)<br>    routes = optional(list(object({<br>      address_prefixes     = list(string)<br>      next_hop_resource_id = string<br>    })), [])<br><br>    # Management Lock on the hub<br>    lock = optional(object({<br>      kind = string<br>      name = optional(string)<br>    }))<br><br>    # VPN Gateway configuration<br>    vpn_gateway = optional(object({<br>      scale_unit                            = optional(number, 1)<br>      bgp_route_translation_for_nat_enabled = optional(bool, false)<br>      routing_preference                    = optional(string, "Microsoft Network")<br>      lock = optional(object({<br>        kind = string<br>        name = optional(string)<br>      }))<br>    }))<br><br>    # ExpressRoute Gateway configuration<br>    express_route_gateway = optional(object({<br>      scale_units                   = optional(number, 1)<br>      allow_non_virtual_wan_traffic = optional(bool, false)<br>      lock = optional(object({<br>        kind = string<br>        name = optional(string)<br>      }))<br>    }))<br><br>    # Azure Firewall configuration<br>    firewall = optional(object({<br>      sku_name           = optional(string, "AZFW_Hub")<br>      sku_tier           = optional(string, "Standard")<br>      firewall_policy_id = optional(string)<br>      dns_servers        = optional(list(string))<br>      private_ip_ranges  = optional(set(string))<br>      # Secure-by-default: threat intelligence-based filtering in "Alert and deny"<br>      # mode (provider value "Deny"). Microsoft Zero Trust / Well-Architected and<br>      # the Secure-Firewall guidance recommend "Alert and deny" so known-malicious<br>      # IPs/FQDNs/URLs are blocked, not merely alerted (addresses the intent of<br>      # Checkov CKV_AZURE_216). Overridable to "Alert"/"Off".<br>      # NOTE: "Deny" requires sku_tier Standard or Premium — Basic supports alert<br>      # only (guarded by the validation below). Default sku_tier here is Standard.<br>      threat_intel_mode = optional(string, "Deny")<br>      zones             = optional(set(string))<br>      public_ip_count   = optional(number, 1)<br>    }))<br>  }))</pre> | `{}` | no |
| vpn\_connections | Map of VPN Site connections to Virtual Hubs. Marked sensitive because vpn\_links[*].shared\_key (pre-shared key) is a credential — Terraform will suppress this variable's value in plan/apply output. | <pre>map(object({<br>    vpn_site_key    = string<br>    virtual_hub_key = string<br><br>    internet_security_enabled = optional(bool, true)<br><br>    routing = optional(object({<br>      associated_route_table = optional(string)<br>      propagated_route_tables = optional(object({<br>        route_table_ids = optional(list(string), [])<br>        labels          = optional(list(string), ["default"])<br>      }))<br>    }))<br><br>    vpn_links = list(object({<br>      name                                  = string<br>      bandwidth_mbps                        = optional(number, 100)<br>      bgp_enabled                           = optional(bool, false)<br>      connection_mode                       = optional(string, "Default")<br>      protocol                              = optional(string, "IKEv2")<br>      ratelimit_enabled                     = optional(bool, false)<br>      route_weight                          = optional(number, 0)<br>      shared_key                            = optional(string)<br>      local_azure_ip_address_enabled        = optional(bool, false)<br>      policy_based_traffic_selector_enabled = optional(bool, false)<br><br>      custom_bgp_address = optional(list(object({<br>        ip_address          = string<br>        ip_configuration_id = string<br>      })))<br><br>      ipsec_policy = optional(object({<br>        dh_group                 = string<br>        ike_encryption_algorithm = string<br>        ike_integrity_algorithm  = string<br>        encryption_algorithm     = string<br>        integrity_algorithm      = string<br>        pfs_group                = string<br>        sa_data_size_kb          = number<br>        sa_lifetime_sec          = number<br>      }))<br>    }))<br>  }))</pre> | `{}` | no |
| vpn\_server\_configurations | Map of VPN Server Configurations (for Point-to-Site) | <pre>map(object({<br>    vpn_authentication_types = optional(list(string), ["Certificate"])<br>    vpn_protocols            = optional(list(string))<br><br>    client_root_certificates = optional(map(object({<br>      name             = string<br>      public_cert_data = string<br>    })), {})<br><br>    azure_active_directory_authentication = optional(object({<br>      audience = string<br>      issuer   = string<br>      tenant   = string<br>    }))<br>  }))</pre> | `{}` | no |
| vpn\_sites | Map of VPN Sites to create | <pre>map(object({<br>    virtual_hub_key = string<br>    address_cidrs   = optional(set(string))<br>    device_vendor   = optional(string)<br>    device_model    = optional(string)<br><br>    links = list(object({<br>      name          = string<br>      ip_address    = optional(string)<br>      fqdn          = optional(string)<br>      speed_in_mbps = optional(number, 100)<br>      provider_name = optional(string)<br><br>      bgp = optional(object({<br>        asn             = number<br>        peering_address = string<br>      }))<br>    }))<br>  }))</pre> | `{}` | no |
| workload | Workload name for naming convention (e.g. default, network) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| bgp\_connection\_ids | Map of Virtual Hub BGP Connection IDs |
| er\_gateway\_lock\_ids | Map of hub key => Resource Lock ID for the ER Gateway (only entries with lock configured). |
| express\_route\_connection\_ids | Map of ExpressRoute Connection IDs (circuit peering ↔ hub ER GW) |
| express\_route\_gateway\_ids | Map of ExpressRoute Gateway IDs |
| firewall\_ids | Map of Azure Firewall IDs |
| firewall\_private\_ips | Map of Azure Firewall private IP addresses |
| hub\_lock\_ids | Map of hub key => Resource Lock ID for the hub (only entries with lock configured). |
| lock\_ids | Map of WAN-level Resource Lock IDs (passes through module.lock.ids). |
| p2s\_gateway\_ids | Map of Point-to-Site VPN Gateway IDs |
| resource | The complete Virtual WAN resource object |
| role\_assignment\_ids | Map of role assignment logical key => role assignment ID |
| virtual\_hub\_connection\_ids | Map of Virtual Hub Connection IDs |
| virtual\_hub\_default\_route\_table\_ids | Map of Virtual Hub default route table IDs |
| virtual\_hub\_ids | Map of Virtual Hub IDs |
| virtual\_hub\_names | Map of Virtual Hub names |
| virtual\_hub\_router\_asns | Map of hub key => vHub virtual router BGP ASN (computed by Azure, typically 65515). PaloCluster uses this to configure BGP neighbor ASN on the Palo side. |
| virtual\_hub\_router\_ips | Map of hub key => list of vHub virtual router BGP peer IPs (computed by Azure post-provisioning). PaloCluster uses these to configure BGP neighbors on the Palo side. |
| virtual\_wan\_id | ID of the Virtual WAN |
| virtual\_wan\_name | Name of the Virtual WAN |
| vpn\_connection\_ids | Map of VPN Connection IDs |
| vpn\_gateway\_bgp\_settings | Map of VPN Gateway BGP settings |
| vpn\_gateway\_ids | Map of VPN Gateway IDs |
| vpn\_gateway\_lock\_ids | Map of hub key => Resource Lock ID for the VPN Gateway (only entries with lock configured). |
| vpn\_gateway\_public\_ips | Map of VPN Gateway public IP addresses (instance 0 and 1) — needed for on-premises CPE configuration |
| vpn\_server\_configuration\_ids | Map of VPN Server Configuration IDs |
| vpn\_site\_ids | Map of VPN Site IDs |
<!-- END_TF_DOCS -->
