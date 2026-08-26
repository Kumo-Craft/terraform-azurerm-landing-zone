# ActionGroup

Creates an Azure Monitor Action Group with email and Azure App push notification receivers. Names follow the `ag-{subscription_acronym}-{environment}-{region_code}-{workload}` convention.

## Usage

### Standalone

```hcl
module "action_group" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/ActionGroup?ref=v0.2.45"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "ama"
  resource_group_name  = "rg-mgm-prod-gwc-monitor"
  short_name           = "ldz-ama"

  email_addresses      = ["ops-team@example.com"]
  push_email_addresses = ["oncall@example.com"]

  tags = {
    Environment = "Production"
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/ActionGroup"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "ama"
  resource_group_name  = dependency.rg.outputs.name
  short_name           = "ldz-ama"
  email_addresses      = ["ops-team@example.com"]
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
| name | Optional explicit name. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name | `string` | `"ama"` | No |
| resource_group_name | Resource group name | `string` | -- | Yes |
| short_name | Short name for the action group (max 12 chars) | `string` | `"ldz-ama"` | No |
| email_addresses | List of email addresses for alert receivers | `list(string)` | `[]` | No |
| push_email_addresses | List of email addresses for Azure App push receivers | `list(string)` | `[]` | No |
| webhook_receivers | Map of webhook receivers (ServiceNow / PagerDuty / Logic App). Key = logical name. | `map(object)` | `{}` | No |
| sms_receivers | Map of SMS receivers for on-call escalation. Key = logical name. | `map(object)` | `{}` | No |
| arm_role_receivers | Map of ARM role receivers (AMBA Azure-native escalation). Key = logical name. | `map(object)` | `{}` | No |
| lock | Optional resource lock (CanNotDelete / ReadOnly). Set null to skip. | `object({kind, name?})` | `null` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Action Group |
| name | The name of the Action Group |
| resource | Complete Action Group resource object |
| lock_id | Management lock ID (null if var.lock is null) |

## Notes

**Note on slug**: This module produces resource names prefixed with `ag-` (e.g. `ag-{acr}-{env}-{region}-{workload}`) rather than the upstream `Azure/naming/azurerm` v0.4.3 default `mag-` (action groups are listed as `monitor_action_group` upstream). This deviation is intentional and preserved for backward compatibility — avoiding state churn on existing deployments.
