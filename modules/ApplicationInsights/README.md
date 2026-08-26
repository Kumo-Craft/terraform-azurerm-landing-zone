# ApplicationInsights

Creates a **workspace-based** Azure Application Insights component, backed by a caller-provided Log Analytics workspace (the telemetry store). Classic (non-workspace) Application Insights is retired, so `workspace_id` is required.

## Usage

### Standalone

```hcl
module "application_insights" {
  source = "../ApplicationInsights"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "frc"
  workload             = "sre-01"
  location             = "francecentral"
  resource_group_name  = "rg-mgm-prod-frc-sre"

  # Backing Log Analytics workspace (dedicated to the SRE Agent).
  workspace_id = dependency.law.outputs.id

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/ApplicationInsights"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "sre-01"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
  workspace_id         = dependency.law.outputs.id
  tags                 = include.root.inputs.common_tags
}
```

## Notes

- **Workspace-based only.** `workspace_id` must be the resource ID of an existing Log Analytics workspace. Ingestion/retention is billed through that workspace.
- **Private networking** is enforced on the backing Log Analytics workspace itself; `internet_ingestion_enabled` / `internet_query_enabled` default to `true` (the AI component does not carry its own private link — the LA workspace does).
- `local_authentication_disabled` maps to the provider's non-deprecated `local_authentication_enabled` (negated). Default `null` keeps the provider default (local auth enabled). Set `true` to enforce Entra-only ingestion.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Optional. Explicit name. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, frc) | `string` | `null` | No |
| workload | Workload suffix | `string` | `"01"` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| workspace_id | Resource ID of the backing Log Analytics workspace (workspace-based AI). | `string` | -- | Yes |
| application_type | Application type (web, other, java, MobileCenter, phone, store, ios, Node.JS). | `string` | `"web"` | No |
| retention_in_days | Data retention in days (30/60/90/120/180/270/365/550/730). | `number` | `90` | No |
| sampling_percentage | Telemetry sampling percentage (0-100). Null = provider default. | `number` | `null` | No |
| local_authentication_disabled | Disable non-Entra (local/API-key) auth. Null = provider default. | `bool` | `null` | No |
| internet_ingestion_enabled | Public-internet telemetry ingestion enabled. | `bool` | `true` | No |
| internet_query_enabled | Public-internet querying enabled. | `bool` | `true` | No |
| lock | Optional resource lock (CanNotDelete / ReadOnly). Null = skip. | `object({ kind = string, name = optional(string) })` | `null` | No |
| role_assignments | Map of role assignments at the AI scope (delegated to ../RoleAssignment). | `map(object(...))` | `{}` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Application Insights component |
| name | The name of the Application Insights component |
| app_id | The Application ID (app_id) |
| connection_string | Connection string (**sensitive**; preferred over the instrumentation key) |
| instrumentation_key | Instrumentation key (**sensitive**; legacy) |
| resource | Complete resource object (**sensitive**) |
| lock_id | Management lock ID (null if no lock) |
| role_assignment_ids | Map of role assignment key => ID |

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
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_application_insights.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| workspace\_id | REQUIRED. Resource ID of the Log Analytics workspace backing this workspace-based Application Insights (the telemetry backing store). Classic (non-workspace) App Insights is retired. | `string` | n/a | yes |
| application\_type | Application type. Defaults to 'web'. | `string` | `"web"` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| internet\_ingestion\_enabled | Whether telemetry ingestion from the public internet is enabled. Default true: private link is enforced on the backing Log Analytics workspace itself. | `bool` | `true` | no |
| internet\_query\_enabled | Whether querying from the public internet is enabled. Default true: private link is enforced on the backing Log Analytics workspace itself. | `bool` | `true` | no |
| local\_authentication\_disabled | Optional. Disable non-Entra (local/API-key) authentication. Null = provider default (false). Set true to enforce Entra-only ingestion. | `bool` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the Application Insights component. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Optional. Explicit name. If null, computed from naming components (appi-{sub}-{env}-{region}-{workload}). | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, frc) | `string` | `null` | no |
| retention\_in\_days | Data retention in days. Note: ingestion/retention is billed through the backing Log Analytics workspace. | `number` | `90` | no |
| role\_assignments | Map of role assignments at the Application Insights scope. Common roles: 'Monitoring Reader', 'Monitoring Contributor'. Default principal\_type='ServicePrincipal'. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| sampling\_percentage | Optional. Percentage of telemetry sampled (0-100). Null = provider default (100). | `number` | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| workload | Workload suffix (e.g. 01, sre-01) | `string` | `"01"` | no |

## Outputs

| Name | Description |
|------|-------------|
| app\_id | The Application ID (app\_id) of the Application Insights component |
| connection\_string | The connection string of the Application Insights component (preferred over the instrumentation key). |
| id | The ID of the Application Insights component |
| instrumentation\_key | The instrumentation key of the Application Insights component (legacy; prefer connection\_string). |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | The name of the Application Insights component |
| resource | The complete Application Insights resource object |
| role\_assignment\_ids | Map of role assignment logical key => role assignment ID |
<!-- END_TF_DOCS -->
