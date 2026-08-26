# ActionGroup

Creates an Azure Monitor Action Group with email and Azure App push notification receivers. Names follow the `ag-{subscription_acronym}-{environment}-{region_code}-{workload}` convention.

## Usage

### Standalone

```hcl
module "action_group" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/ActionGroup?ref=v0.2.45"

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

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_action_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_action_group) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| arm\_role\_receivers | Map of ARM role receivers. Sends alerts to all principals with the specified built-in role at the alert resource's scope. Common AMBA pattern for Azure-native escalation. Common role\_ids: Owner '8e3af657-a8ff-443c-a75c-2fe8c4bcb635', Contributor 'b24988ac-6180-42a0-ab88-20f7382dd24c', Monitoring Contributor '749f88d5-cbae-40b8-bcfc-e573ddc772fa', Monitoring Reader '43d0d8ad-25c7-4714-9337-8ba259a9fe05'. Key is logical name. | <pre>map(object({<br>    role_id                 = string<br>    use_common_alert_schema = optional(bool, true)<br>  }))</pre> | `{}` | no |
| email\_addresses | List of email addresses for alert email receivers | `list(string)` | `[]` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the Action Group. CanNotDelete protects alert delivery from accidental deletion. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Optional. Explicit name that bypasses the convention entirely — use for legacy resources. When null, the 4 house vars below must all be set. | `string` | `null` | no |
| push\_email\_addresses | List of email addresses for Azure App push receivers | `list(string)` | `[]` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| short\_name | Short name for the action group (max 12 chars) | `string` | `"ldz-ama"` | no |
| sms\_receivers | Map of SMS receivers for on-call escalation. Key is a logical name (must be <= 50 chars). | <pre>map(object({<br>    country_code = string<br>    phone_number = string<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| webhook\_receivers | Map of webhook receivers. Useful for ServiceNow / PagerDuty / Logic App integration (AMBA baseline pattern). Key is a logical name (max 50 chars when truncated). | <pre>map(object({<br>    service_uri             = string<br>    use_common_alert_schema = optional(bool, true)<br>    # Optional AAD-backed webhook auth (only set when needed):<br>    aad_auth = optional(object({<br>      object_id      = string<br>      identifier_uri = optional(string, null)<br>      tenant_id      = optional(string, null)<br>    }), null)<br>  }))</pre> | `{}` | no |
| workload | Workload name (e.g. ama) | `string` | `"ama"` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Action Group |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | The name of the Action Group |
| resource | The complete Action Group resource object |
<!-- END_TF_DOCS -->
