# DnsResolver

Deploys an Azure DNS Private Resolver with an inbound endpoint (receives DNS queries from VNets/Palo), an optional outbound endpoint, and optional DNS forwarding rules with VNet links.

## BREAKING — v0.2.55

The module no longer creates its own `azurerm_resource_group`. Callers must supply a pre-existing resource group via the new **required** `var.resource_group_name`.

**New required inputs:**
- `resource_group_name` — ARM name of the pre-existing RG.
- `workload` — required when using convention naming (name=null).

**New optional inputs:**
- `lock` — optional CanNotDelete / ReadOnly management lock on the resolver.
- `role_assignments` — map of RBAC grants at the resolver scope.

### Migration recipe

1. Create the resource group outside this module (e.g. via the `ResourceGroup` module) before upgrading.

2. Move the existing state entries out of the module:

```bash
# Remove the inline RG from state (it stays in Azure — destroy=false tombstone handles it)
terraform state rm 'module.dns_resolver.azurerm_resource_group.this'

# Move the resolver + endpoints + ruleset + rules + links to the new addresses
terraform state mv \
  'module.dns_resolver.azurerm_private_dns_resolver.this' \
  'module.dns_resolver.azurerm_private_dns_resolver.this'

terraform state mv \
  'module.dns_resolver.azurerm_private_dns_resolver_inbound_endpoint.this' \
  'module.dns_resolver.azurerm_private_dns_resolver_inbound_endpoint.this'

# (Addresses are unchanged — the mv is a no-op for the resolver/endpoints.
#  Only the RG needs removing from state.)
```

3. Update your module call:

```hcl
# Before (v0.2.54 and earlier)
module "dns_resolver" {
  source = "..."

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  # ...
}

# After (v0.2.55+)
module "dns_resolver" {
  source = "..."

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "hub"            # NEW — required for convention naming
  location             = "germanywestcentral"
  resource_group_name  = "rg-con-prod-gwc-dns-resolver"  # NEW — caller-managed RG
  # ...
}
```

## Usage

### Standalone

```hcl
module "dns_resolver" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/DnsResolver?ref=v0.2.59"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"

  virtual_network_id  = "/subscriptions/.../virtualNetworks/vnet-con-prod-gwc-hub"
  inbound_subnet_id   = "/subscriptions/.../subnets/snet-con-prod-gwc-dns-in"
  inbound_private_ip  = "10.238.200.68"
  outbound_subnet_id  = "/subscriptions/.../subnets/snet-con-prod-gwc-dns-out"

  forwarding_rules = {
    onprem = {
      domain_name = "corp.example.com."
      target_dns_servers = [
        { ip_address = "10.0.0.4" },
        { ip_address = "10.0.0.5" }
      ]
    }
  }

  ruleset_vnet_links = {
    hub   = "/subscriptions/.../virtualNetworks/vnet-con-prod-gwc-hub"
    spoke = "/subscriptions/.../virtualNetworks/vnet-api-prod-gwc-spoke"
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/DnsResolver"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  location             = include.root.inputs.location
  virtual_network_id   = dependency.hub_vnet.outputs.id
  inbound_subnet_id    = dependency.subnet.outputs.subnet_ids["snet-con-prod-gwc-dns-in"]
  inbound_private_ip   = "10.238.200.68"
  tags                 = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Optional. Explicit name. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. con) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc) | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| tags | Tags to apply | `map(string)` | `{}` | No |
| virtual_network_id | VNet ID in which to deploy the resolver | `string` | -- | Yes |
| inbound_subnet_id | Subnet ID for the inbound endpoint (Microsoft.Network/dnsResolvers delegation required) | `string` | -- | Yes |
| inbound_private_ip | Static private IP for the inbound endpoint. If null, dynamic allocation. | `string` | `null` | No |
| outbound_subnet_id | Subnet ID for the outbound endpoint. If null, no outbound endpoint. | `string` | `null` | No |
| forwarding_rules | Map of DNS forwarding rules. Key = rule name. | `map(object({ domain_name = string, target_dns_servers = list(object({ ip_address = string, port = optional(number, 53) })), enabled = optional(bool, true) }))` | `{}` | No |
| ruleset_vnet_links | Map of name => VNet ID to link to the forwarding ruleset | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_name | The name of the resource group |
| id | The ID of the DNS Private Resolver |
| name | The name of the DNS Private Resolver |
| resource | Complete DNS Private Resolver resource object |
| inbound_endpoint_ip | The private IP address of the inbound endpoint (use as DNS forwarder) |
| inbound_endpoint_id | The ID of the inbound endpoint |
| outbound_endpoint_id | The ID of the outbound endpoint (null if not created) |
| forwarding_ruleset_id | The ID of the DNS forwarding ruleset (null if not created) |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_private_dns_resolver.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_resolver) | resource |
| [azurerm_private_dns_resolver_dns_forwarding_ruleset.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_resolver_dns_forwarding_ruleset) | resource |
| [azurerm_private_dns_resolver_forwarding_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_resolver_forwarding_rule) | resource |
| [azurerm_private_dns_resolver_inbound_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_resolver_inbound_endpoint) | resource |
| [azurerm_private_dns_resolver_outbound_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_resolver_outbound_endpoint) | resource |
| [azurerm_private_dns_resolver_virtual_network_link.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_resolver_virtual_network_link) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| inbound\_subnet\_id | Subnet ID for the inbound endpoint (Microsoft.Network/dnsResolvers delegation required) | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Name of the pre-existing resource group in which to deploy the resolver. | `string` | n/a | yes |
| virtual\_network\_id | VNet ID in which to deploy the resolver | `string` | n/a | yes |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| forwarding\_rules | Map of DNS forwarding rules. Key = rule name.<br>Requires outbound\_subnet\_id to be set.<br><br>- `domain_name`        - (Required) FQDN to forward (must end with ".").<br>- `target_dns_servers`  - (Required) List of target DNS servers.<br>- `enabled`             - (Optional) Enable the rule. Defaults to true. | <pre>map(object({<br>    domain_name = string<br>    target_dns_servers = list(object({<br>      ip_address = string<br>      port       = optional(number, 53)<br>    }))<br>    enabled = optional(bool, true)<br>  }))</pre> | `{}` | no |
| inbound\_private\_ip | Static private IP for the inbound endpoint. If null, dynamic allocation. | `string` | `null` | no |
| lock | Controls the Resource Lock configuration for this resource.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit name. If null, computed from naming components. | `string` | `null` | no |
| outbound\_subnet\_id | Subnet ID for the outbound endpoint. If null, no outbound endpoint is created. | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | Map of role assignments at the DNS Private Resolver scope. Default principal\_type='ServicePrincipal'. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| ruleset\_vnet\_links | Map of name => VNet ID to link to the forwarding ruleset. | `map(string)` | `{}` | no |
| subscription\_acronym | Subscription acronym (e.g. con) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| workload | Workload component for naming convention {type}-{acr}-{env}-{region}-{workload}. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| forwarding\_ruleset\_id | The ID of the DNS forwarding ruleset (null if not created) |
| id | The ID of the DNS Private Resolver |
| inbound\_endpoint\_id | The ID of the inbound endpoint |
| inbound\_endpoint\_ip | The private IP address of the inbound endpoint (use as DNS forwarder). Available after apply. For dynamic allocation (default), the IP is computed and known only post-create. |
| lock\_id | The resource ID of the management lock (null if no lock configured) |
| name | The name of the DNS Private Resolver |
| outbound\_endpoint\_id | The ID of the outbound endpoint (null if not created) |
| resource | The complete DNS Private Resolver resource object |
| role\_assignment\_ids | Map of role assignment key => role assignment resource ID |
<!-- END_TF_DOCS -->
