# PrivateDnsZonesCorp

Deploys a configurable list of **corporate-internal Azure Private DNS zones** (e.g. `az.epttst.lu`, `corp.example.com`) and links them to a set of VNets for resolution. The resource group must be caller-provided (v0.2.9+). Companion to the `PrivateDnsZones` module which handles the standard `privatelink.*` zones from the ALZ AVM library.

## Usage

### Standalone

```hcl
module "corp_dns_rg" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/ResourceGroup?ref=v0.2.9"

  subscription_acronym = "con"
  environment          = "nprd"
  region_code          = "gwc"
  location             = "germanywestcentral"
  workload             = "dns-zones"
  tags                 = { Environment = "Non Production" }
}

module "corp_dns_zones" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/PrivateDnsZonesCorp?ref=v0.2.88"

  resource_group_name = module.corp_dns_rg.name

  zones = [
    "az.epttst.lu",
    "corp.example.com",
  ]

  virtual_network_links = {
    nva = {
      virtual_network_resource_id = "/subscriptions/.../virtualNetworks/vnet-con-nprd-gwc-nva"
      registration_enabled        = false
    }
    shared = {
      virtual_network_resource_id = "/subscriptions/.../virtualNetworks/vnet-con-nprd-gwc-shared"
      registration_enabled        = false
    }
  }

  tags = { Environment = "Non Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PrivateDnsZonesCorp"
}

dependency "corp_dns_rg" { config_path = "../corp-dns-rg" }
dependency "vnet_nva"    { config_path = "../network-shared" }
dependency "vnet_shared" { config_path = "../network-shared" }

inputs = {
  resource_group_name = dependency.corp_dns_rg.outputs.name

  zones = ["az.epttst.lu"]

  virtual_network_links = {
    nva    = { virtual_network_resource_id = dependency.vnet_nva.outputs.id,    registration_enabled = false }
    shared = { virtual_network_resource_id = dependency.vnet_shared.outputs.id, registration_enabled = false }
  }

  tags = include.root.inputs.common_tags
}
```

## Breaking changes (v0.2.9)

PrivateDnsZonesCorp no longer creates its own resource group. Callers must now supply `resource_group_name`.

### Migration recipe for callers upgrading from v0.2.8 or earlier

If your previous deployment had this module create the RG (the default behavior in v0.2.8 and earlier), follow this recipe to avoid destroying the existing RG and zones beneath it:

1. **Move RG ownership to your root config.** Add a `module "corp_dns_rg" { source = "../ResourceGroup" ... }` (or equivalent) to your root. Pass it the SAME name the module previously generated (`rg-{subscription_acronym}-{environment}-{region_code}-dns-zones`).

2. **Add a `removed` block in your root config** to release the RG from PrivateDnsZonesCorp state without destroying it Azure-side:

   ```hcl
   removed {
     from = module.corp_dns_zones.azurerm_resource_group.this
     lifecycle {
       destroy = false
     }
   }
   ```

3. **Run `terraform state mv`** to move the RG into the new owner's state path:

   ```bash
   terraform state mv \
     module.corp_dns_zones.azurerm_resource_group.this \
     module.corp_dns_rg.azurerm_resource_group.this
   ```

4. **Pass the new RG to PrivateDnsZonesCorp**:

   ```hcl
   module "corp_dns_zones" {
     source              = "..."
     resource_group_name = module.corp_dns_rg.name
     # other args...
   }
   ```

The DNS zones continue to live under their existing Terraform resource addresses and are NOT affected by the RG ownership transfer.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| resource_group_name | Existing resource group name (caller-provided). PrivateDnsZonesCorp v0.2.9 no longer creates the RG. | `string` | -- | Yes |
| zones | Set of corporate private DNS zone FQDNs to create (e.g. `["az.epttst.lu"]`). | `set(string)` | `[]` | No |
| virtual_network_links | Map of logical name => VNet link config. Each VNet is linked to every zone. | `map(object({ virtual_network_resource_id = string, registration_enabled = optional(bool, false) }))` | `{}` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_name | Name of the resource group hosting the zones (passed through from caller) |
| zone_ids | Map of zone FQDN => Private DNS zone resource ID |
| zone_names | List of zone names created |

## Notes

- **Scope distinction**: this module is for **corp-internal** zones (custom-named domains). For the standard Azure Private Link zones (`privatelink.vaultcore.azure.net`, `privatelink.blob.core.windows.net`, …) use the `PrivateDnsZones` module which wraps `Azure/avm-ptn-network-private-link-private-dns-zones/azurerm`.
- **VNet links**: pass each VNet that should resolve these zones. Set `registration_enabled = true` on at most ONE link per zone if you want VMs to auto-register their hostnames (rare for corp zones).
- **Cross-sub linking**: if the consuming VNets live in a different subscription than the zones, the deployer needs `Private DNS Zone Contributor` on the zone RG.
