# DdosProtection

Creates an Azure DDoS Protection Plan. Names follow the `ddos-{subscription_acronym}-{environment}-{region_code}-{workload}` convention.

## Usage

### Standalone

```hcl
module "ddos_protection" {
  source = "git::https://github.com/Kumo-Craft/Modules.git//modules/DdosProtection?ref=v0.2.89"

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
