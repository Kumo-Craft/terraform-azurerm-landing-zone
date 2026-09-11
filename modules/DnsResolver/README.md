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
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/DnsResolver?ref=v0.2.59"

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
