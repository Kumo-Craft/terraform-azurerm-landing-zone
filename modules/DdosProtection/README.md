# DdosProtection

Creates an Azure DDoS Protection Plan. Names follow the `ddos-{subscription_acronym}-{environment}-{region_code}-{workload}` convention.

## Usage

### Standalone

```hcl
module "ddos_protection" {
  source = "git::https://github.com/Kumo-Craft/terraform-azurerm-landing-zone.git//modules/DdosProtection?ref=v0.2.89"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "network"
  location             = "germanywestcentral"
  resource_group_name  = "rg-con-prod-gwc-network"

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/DdosProtection"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "network"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
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
| subscription_acronym | Subscription acronym (e.g. con, mgm) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name (e.g. network) | `string` | `"network"` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| lock | Controls the Resource Lock configuration. `kind` (Required): "CanNotDelete" or "ReadOnly". `name` (Optional): lock name, generated from kind if omitted. Set null to skip. | `object({kind=string, name=optional(string)})` | `null` | No |
| role_assignments | Map of role assignments scoped to the DDoS Protection Plan resource. | `map(object({...}))` | `{}` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the DDoS Protection Plan |
| name | The name of the DDoS Protection Plan |
| resource | The complete DDoS Protection Plan resource object |
| role_assignment_ids | Map of role assignment IDs keyed by the role_assignments input map key. |

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
| [azurerm_network_ddos_protection_plan.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_ddos_protection_plan) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| lock | Controls the Resource Lock configuration for this resource. Note that<br>the resource also carries an unconditional `lifecycle.prevent_destroy`<br>guard at the Terraform level — this variable adds a second, Azure-side<br>guard that survives state loss/refresh.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit name. If null, computed from naming components. | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | Map of role assignments scoped to the DDoS Protection Plan resource. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string)<br>    condition_version                = optional(string)<br>    description                      = optional(string)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym (e.g. con, mgm) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| workload | Workload name (e.g. network) | `string` | `"network"` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the DDoS Protection Plan |
| name | The name of the DDoS Protection Plan |
| resource | The complete DDoS Protection Plan resource object |
| role\_assignment\_ids | Map of role assignment IDs keyed by the role\_assignments input map key. |
<!-- END_TF_DOCS -->
