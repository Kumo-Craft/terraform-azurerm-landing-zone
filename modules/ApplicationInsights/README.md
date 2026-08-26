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
