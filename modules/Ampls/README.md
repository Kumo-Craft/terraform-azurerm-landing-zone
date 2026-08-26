# Ampls

Creates an Azure Monitor Private Link Scope (AMPLS), links scoped services (Log Analytics Workspace, Automation Account), and deploys a Private Endpoint with DNS zone group for secure Azure Monitor traffic.

## BREAKING CHANGES

### v0.2.68

1. **Output renames** — two outputs have been renamed to match the canonical single-word pattern used across all modules in this repo:

   | Old name | New name |
   |----------|----------|
   | `ampls_id` | `id` |
   | `ampls_resource` | `resource` |

   A new `scoped_service_ids` output has also been added (map of scoped service key → resource ID).

   **Migration recipe for Terragrunt callers** — find and replace in your Terragrunt inputs:

   ```
   dependency.ampls.outputs.ampls_id       →  dependency.ampls.outputs.id
   dependency.ampls.outputs.ampls_resource →  dependency.ampls.outputs.resource
   ```

   No state migration is needed — output renames only affect the variable contract, not the underlying Azure resources.

### v0.2.63

1. **`var.ampls_name` renamed to `var.name`** — callers must rename the variable in their configuration. The AMPLS resource itself is NOT destroyed or recreated (the resource address `azurerm_monitor_private_link_scope.this` is unchanged); only the variable contract changes. If callers were passing a literal name to `ampls_name`, pass the same value to `name`.

2. **Private Endpoint state migration** — the inline `azurerm_private_endpoint.this` resource has been moved to `module.private_endpoint.azurerm_private_endpoint.this["ampls"]`. A `moved {}` block is included in main.tf so Terraform automatically migrates existing state on the next `terraform plan` — **no manual `terraform state mv` is needed**. Callers should run `terraform plan` and verify the plan shows no destroy/recreate for the PE.

3. **Computed naming** — if `var.name` is `null`, the AMPLS name is now computed as `pls-{acr}-{env}-{region}-{workload}`. Callers previously relying on `ampls_name` to pass a computed value should either continue passing an explicit `name`, or switch to the standard naming variables.

## Usage

### Standalone (explicit name)

```hcl
module "ampls" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/Ampls?ref=v0.2.63"

  name                = "pls-mgm-prod-gwc-management"
  resource_group_name = "rg-mgm-prod-gwc-management"
  location            = "germanywestcentral"

  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "PrivateOnly"

  scoped_services = {
    law = { resource_id = "/subscriptions/.../workspaces/law-mgm-prod-gwc-01" }
    aa  = { resource_id = "/subscriptions/.../automationAccounts/aa-mgm-prod-gwc-01" }
  }

  subnet_id            = "/subscriptions/.../subnets/snet-mgm-prod-gwc-pe"
  private_dns_zone_ids = [
    "/subscriptions/.../privateDnsZones/privatelink.monitor.azure.com",
    "/subscriptions/.../privateDnsZones/privatelink.oms.opinsights.azure.com",
    "/subscriptions/.../privateDnsZones/privatelink.ods.opinsights.azure.com",
    "/subscriptions/.../privateDnsZones/privatelink.agentsvc.azure-automation.net",
    # Required for Automation Account diagnostics / storage endpoint (DCE blobs).
    "/subscriptions/.../privateDnsZones/privatelink.blob.core.windows.net",
  ]

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Standalone (computed naming)

```hcl
module "ampls" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/Ampls?ref=v0.2.63"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "management"
  resource_group_name  = "rg-mgm-prod-gwc-management"
  location             = "germanywestcentral"

  scoped_services = {
    law = { resource_id = "/subscriptions/.../workspaces/law-mgm-prod-gwc-01" }
  }

  subnet_id            = "/subscriptions/.../subnets/snet-mgm-prod-gwc-pe"
  private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.monitor.azure.com"]

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/Ampls"
}

inputs = {
  name                = "pls-mgm-prod-gwc-management"
  resource_group_name = dependency.rg.outputs.name
  location            = include.root.inputs.location

  scoped_services = {
    law = { resource_id = dependency.alz_management.outputs.law_id }
    aa  = { resource_id = dependency.alz_management.outputs.automation_account_id }
  }

  subnet_id            = dependency.subnet.outputs.subnet_ids["snet-mgm-prod-gwc-pe"]
  private_dns_zone_ids = values(dependency.dns_zones.outputs.private_dns_zone_resource_ids)

  lock = { kind = "CanNotDelete" }
  tags = include.root.inputs.common_tags
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
| name | Explicit AMPLS name. If null, computed from naming components. | `string` | `null` | One of `name` or all naming vars |
| subscription_acronym | Subscription acronym (e.g. mgm). Used when `name` is null. | `string` | `null` | No |
| environment | Environment (e.g. prod). Used when `name` is null. | `string` | `null` | No |
| region_code | Region code (e.g. gwc). Used when `name` is null. | `string` | `null` | No |
| workload | Workload component. Used when `name` is null. | `string` | `null` | No |
| resource_group_name | Name of the resource group | `string` | -- | Yes |
| location | Azure region | `string` | -- | Yes |
| ingestion_access_mode | AMPLS ingestion access mode: Open or PrivateOnly | `string` | `"PrivateOnly"` | No |
| query_access_mode | AMPLS query access mode: Open or PrivateOnly | `string` | `"PrivateOnly"` | No |
| scoped_services | Map of services to link to the AMPLS (e.g. law, aa) | `map(object({ resource_id = string }))` | -- | Yes |
| subnet_id | Subnet ID for the private endpoint | `string` | -- | Yes |
| private_dns_zone_ids | List of private DNS zone IDs for the PE DNS zone group | `list(string)` | -- | Yes |
| lock | Optional resource lock. `kind` = CanNotDelete or ReadOnly. | `object({ kind = string, name = optional(string) })` | `null` | No |
| role_assignments | Map of role assignments at the AMPLS scope. | `map(object({...}))` | `{}` | No |
| tags | Tags to apply to all resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Azure Monitor Private Link Scope |
| resource | Complete AMPLS resource object |
| scoped_service_ids | Map of scoped service key => scoped service resource ID |
| private_endpoint_id | The ID of the AMPLS private endpoint |
| private_ip_address | The private IP address of the AMPLS private endpoint |
| lock_id | The ID of the management lock, if applied |
| role_assignment_ids | Map of role assignment key => role assignment ID |

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
| private\_endpoint | ../PrivateEndpoint | n/a |
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_private_link_scope.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_private_link_scope) | resource |
| [azurerm_monitor_private_link_scoped_service.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_private_link_scoped_service) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| private\_dns\_zone\_ids | List of private DNS zone IDs for the PE DNS zone group | `list(string)` | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| scoped\_services | Map of services to link to the AMPLS (e.g. law, dce). Key = logical name. | <pre>map(object({<br>    resource_id = string<br>  }))</pre> | n/a | yes |
| subnet\_id | Subnet ID for the private endpoint | `string` | n/a | yes |
| environment | Environment (e.g. prod, nprd). Used for computed naming when var.name is null. | `string` | `null` | no |
| ingestion\_access\_mode | AMPLS ingestion access mode: Open or PrivateOnly | `string` | `"PrivateOnly"` | no |
| lock | Controls the Resource Lock configuration for the AMPLS resource.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit name for the AMPLS. If null, computed from naming components (pls-{acr}-{env}-{region}-{workload}). | `string` | `null` | no |
| query\_access\_mode | AMPLS query access mode: Open or PrivateOnly | `string` | `"PrivateOnly"` | no |
| region\_code | Region code (e.g. gwc, weu). Used for computed naming when var.name is null. | `string` | `null` | no |
| role\_assignments | Map of role assignments at the AMPLS scope. Default principal\_type='ServicePrincipal'. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string)<br>    condition_version                = optional(string)<br>    description                      = optional(string)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm). Used for computed naming when var.name is null. | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| workload | Workload component (e.g. management). Used for computed naming when var.name is null. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Azure Monitor Private Link Scope |
| lock\_id | The ID of the management lock, if applied |
| private\_endpoint\_id | The ID of the AMPLS private endpoint |
| private\_ip\_address | The private IP address of the AMPLS private endpoint |
| resource | The complete AMPLS resource object |
| role\_assignment\_ids | Map of role assignment key => role assignment ID |
| scoped\_service\_ids | Map of scoped service key => scoped service resource ID |
<!-- END_TF_DOCS -->
