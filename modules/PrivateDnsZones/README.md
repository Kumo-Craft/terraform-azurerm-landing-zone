# PrivateDnsZones

Deploys the full set of Azure Private Link Private DNS Zones using the official AVM pattern module (`Azure/avm-ptn-network-private-link-private-dns-zones/azurerm`). Optionally links all zones to one or more virtual networks. The resource group must be caller-provided (v0.2.9+).

## Usage

### Standalone

```hcl
module "dns_rg" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/ResourceGroup?ref=v0.2.9"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  workload             = "plink-dns"
  tags                 = { Environment = "Production" }
}

module "private_dns_zones" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/PrivateDnsZones?ref=v0.2.9"

  location             = "germanywestcentral"
  resource_group_name  = module.dns_rg.name
  resource_group_id    = module.dns_rg.id

  virtual_network_links = {
    hub = {
      virtual_network_resource_id = "/subscriptions/.../virtualNetworks/vnet-con-prod-gwc-hub"
      # Fallback to internet: when an authoritative NXDOMAIN is returned for a
      # private-link zone, retry public recursion. Safe to set globally.
      resolution_policy = "NxDomainRedirect"
    }
    spoke-api = {
      virtual_network_resource_id = "/subscriptions/.../virtualNetworks/vnet-api-prod-gwc-spoke"
    }
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PrivateDnsZones"
}

inputs = {
  location            = include.root.inputs.location
  resource_group_name = dependency.dns_rg.outputs.name
  resource_group_id   = dependency.dns_rg.outputs.id

  virtual_network_links = {
    hub = {
      virtual_network_resource_id = dependency.hub_vnet.outputs.id
    }
  }

  tags = include.root.inputs.common_tags
}
```

## Breaking changes (v0.2.9)

PrivateDnsZones no longer creates its own resource group. Callers must now supply `resource_group_name` AND `resource_group_id` (the latter is wired as `parent_id` to the underlying AVM ptn module).

### Migration recipe for callers upgrading from v0.2.8 or earlier

If your previous deployment had this module create the RG (the default behavior in v0.2.8 and earlier), follow this 3-step recipe to avoid destroying the existing RG and the ~60 DNS zones beneath it:

1. **Move RG ownership to your root config.** Add a `module "dns_rg" { source = "../ResourceGroup" ... }` (or equivalent) to your root. Pass it the SAME name the module previously generated.

2. **Add a `removed` block in your root config** to release the RG from PrivateDnsZones state without destroying it Azure-side:

   ```hcl
   removed {
     from = module.private_dns_zones.azurerm_resource_group.this
     lifecycle {
       destroy = false
     }
   }
   ```

3. **Run `terraform state mv`** to move the RG into the new owner's state path:

   ```bash
   terraform state mv \
     module.private_dns_zones.azurerm_resource_group.this \
     module.dns_rg.azurerm_resource_group.this
   ```

4. **Pass the new RG to PrivateDnsZones**:

   ```hcl
   module "private_dns_zones" {
     source              = "..."
     resource_group_name = module.dns_rg.name
     resource_group_id   = module.dns_rg.id
     # other args...
   }
   ```

The ~60 DNS zones beneath the RG continue to live under the AVM ptn module's address path and are NOT affected by the RG ownership transfer (they reference the RG by `parent_id`, not by Terraform resource address).

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Existing resource group name (caller-provided). PrivateDnsZones v0.2.9 no longer creates the RG. | `string` | -- | Yes |
| resource_group_id | Existing resource group resource ID (caller-provided). Wired as `parent_id` to the AVM ptn module. | `string` | -- | Yes |
| tags | Tags | `map(string)` | `{}` | No |
| virtual_network_links | VNets to link to all DNS zones. Key = logical name; `virtual_network_resource_id` (required); `resolution_policy` (optional) = `Default` \| `NxDomainRedirect`. | `map(object({ virtual_network_resource_id = string, resolution_policy = optional(string) }))` | `{}` | No |
| lock | Optional management lock (CanNotDelete or ReadOnly). | `object({ kind = string, name = optional(string) })` | `null` | No |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_name | The DNS resource group name (passed through from caller) |
| private_dns_zone_resource_ids | Map of private DNS zone names to their resource IDs |

## Fallback to internet (`resolution_policy = "NxDomainRedirect"`)

Set `resolution_policy = "NxDomainRedirect"` on a VNet link to enable Azure's native **fallback to internet** for private-link zones. When a workload forwards on-prem/Azure DNS queries for a public domain (e.g. `database.windows.net`, `vault.azure.net`) into a VNet linked to these zones, and the linked private zone returns an authoritative **NXDOMAIN** (because the queried private endpoint is owned by a different tenant/VNet), the Azure recursive resolver retries **public** recursion instead of failing.

- Values: `Default` (no fallback) or `NxDomainRedirect` (fallback to internet). Per-link, optional; omit to keep the platform default.
- Requires Microsoft.Network API `2024-06-01`+ — the pinned AVM module (`~> 0.23`) already targets a compatible version; no `azapi` pin is needed here.
- The AVM module applies a non-`Default` policy **only to zones that actually support Private Link**; zones that don't support it silently ignore the setting, so a blanket `NxDomainRedirect` across all links is safe.
- Reference: [Fallback to internet for Azure Private DNS zones](https://learn.microsoft.com/azure/dns/private-dns-fallback).

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |
| time | >= 0.9 |

## Providers

| Name | Version |
|------|---------|
| time | >= 0.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| private\_dns\_zones | Azure/avm-ptn-network-private-link-private-dns-zones/azurerm | ~> 0.23 |

## Resources

| Name | Type |
|------|------|
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_id | Existing resource group resource ID (caller-provided). Wired as `parent_id` to the AVM ptn module. Caller usually obtains this from their ../ResourceGroup module call (e.g. `module.dns_rg.id`). | `string` | n/a | yes |
| resource\_group\_name | Existing resource group name (caller-provided). PrivateDnsZones v0.2.9 no longer creates the RG — caller must supply an existing one (typically via ../ResourceGroup in their root module). | `string` | n/a | yes |
| lock | Optional management lock on the hosting resource group (passes through to the AVM ptn module). Standard house shape — kind in {CanNotDelete, ReadOnly}. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| tags | Tags | `map(string)` | `{}` | no |
| virtual\_network\_links | VNets to link to all DNS zones. Key = logical name, value.virtual\_network\_resource\_id = VNet resource ID.<br><br>resolution\_policy (optional): "Default" \| "NxDomainRedirect". NxDomainRedirect = "fallback to<br>internet" on the VNet link — when an authoritative NXDOMAIN is returned for a private-link zone,<br>the Azure recursive resolver retries public recursion. The AVM module only applies a non-Default<br>policy to zones that actually support Private Link; zones that don't support it silently ignore<br>it, so a blanket NxDomainRedirect is safe. Requires Microsoft.Network API 2024-06-01+ (the AVM<br>module already targets a compatible version). | <pre>map(object({<br>    virtual_network_resource_id = string<br>    resolution_policy           = optional(string)<br>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| private\_dns\_zone\_resource\_ids | Map of private DNS zone names to their resource IDs |
| resource\_group\_name | The name of the DNS resource group (passed through from caller) |
<!-- END_TF_DOCS -->
