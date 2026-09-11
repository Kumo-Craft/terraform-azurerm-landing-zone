# AlertProcessingRule

Routes alerts that fire on a subscription (or resource groups / resources) to one or more **Action Groups**, without touching the alert rules themselves — `azurerm_monitor_alert_processing_rule_action_group`.

**Trigger use case:** AMBA-ALZ deploys its alerts through DINE policies and, by design, **without an action group**. Notifications only happen if an Alert Processing Rule adds one — otherwise the alerts notify nobody.

## Usage

```hcl
module "alert_processing_rule" {
  source = "../AlertProcessingRule"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"
  resource_group_name  = "rg-mgm-prod-gwc-monitoring"

  # Route every alert firing anywhere in the subscription:
  scopes               = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
  add_action_group_ids = [dependency.ag.outputs.id]

  description = "Route AMBA-ALZ alerts to the platform action group"

  # Optional volume lever — only route Sev0/Sev1 (see below):
  # condition = { severity = { operator = "Equals", values = ["Sev0", "Sev1"] } }
}
```

## Important / gotchas

- **`scopes` = where the alerts FIRE, not where the alert rules live.** This is counter-intuitive: you pass the subscription/RG/resource IDs on which alerts are raised (usually the whole subscription ID), *not* the resource group that holds the alert rules or this rule.
- **Single subscription only.** An Alert Processing Rule cannot cross subscription boundaries (Azure Monitor service constraint). All `scopes` must be within one subscription. Deploy one rule per subscription.
- **This is the *add-action-group* variant, not suppression.** For muting alerts during a maintenance window use `azurerm_monitor_alert_processing_rule_suppression` — that will be a **separate** module. Do not conflate them: a suppression rule *removes* notifications.
- **`condition` (optional)** filters which alerts are routed (`severity`, `monitor_service`, `target_resource_group`, `signal_type`, …). Null = route ALL alerts on the scopes. Each filter is `{ operator, values }`. Operator support differs by field (enforced by the module's validators): `monitor_condition` / `monitor_service` / `severity` / `signal_type` accept **only** `Equals` / `NotEquals`; the other 7 fields also accept `Contains` / `DoesNotContain`. When set, `condition` must specify at least one sub-block. Keep it null unless the alert volume becomes a problem.
- **`schedule` is intentionally out of scope.** The provider also exposes a `schedule` block (effective-from/until + recurrence) for time-boxed rules; this module is an always-on AMBA-ALZ router and does not expose it. If time-boxing is ever needed, add it here (or use a dedicated rule) rather than assuming it was omitted by oversight.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Optional explicit name (else apr-{sub}-{env}-{region}-{workload}). | `string` | `null` | No |
| subscription_acronym / environment / region_code / workload | Naming components. | `string` | see vars | Conditional |
| resource_group_name | RG that holds the rule resource. | `string` | -- | Yes |
| scopes | Resource IDs the alerts fire on (subscription / RG / resource). | `list(string)` | -- | Yes |
| add_action_group_ids | Action Group IDs to add to matching alerts. | `list(string)` | -- | Yes |
| description | Rule description. | `string` | `null` | No |
| enabled | Whether the rule is enabled. | `bool` | `true` | No |
| condition | Optional filters `{ <field> = { operator, values } }`. Null = match all. | `object` | `null` | No |
| lock | Optional resource lock (CanNotDelete / ReadOnly). | `object` | `null` | No |
| tags | Tags to apply. | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Alert Processing Rule ID |
| name | Alert Processing Rule name |
| resource | Complete resource object |
| lock_id | Management lock ID (null if no lock) |

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

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_alert_processing_rule_action_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_alert_processing_rule_action_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| add\_action\_group\_ids | Action Group resource IDs to add to matching alerts. This is how AMBA-ALZ (policy-deployed alerts with no action group) get routed to notifications. | `list(string)` | n/a | yes |
| resource\_group\_name | Resource group that HOLDS the Alert Processing Rule resource (not where alerts fire — see var.scopes). | `string` | n/a | yes |
| scopes | Resource IDs the rule applies to — i.e. the resources on which the alerts<br>FIRE (typically the whole subscription ID, but can be resource groups or<br>individual resources). This is NOT where the alert rules live. All scopes<br>must be within a SINGLE subscription: an APR cannot cross subscription<br>boundaries (Azure Monitor service constraint). | `list(string)` | n/a | yes |
| condition | Optional condition filters. Null = match all alerts on the scopes. | <pre>object({<br>    alert_context         = optional(object({ operator = string, values = list(string) }))<br>    alert_rule_id         = optional(object({ operator = string, values = list(string) }))<br>    alert_rule_name       = optional(object({ operator = string, values = list(string) }))<br>    description           = optional(object({ operator = string, values = list(string) }))<br>    monitor_condition     = optional(object({ operator = string, values = list(string) }))<br>    monitor_service       = optional(object({ operator = string, values = list(string) }))<br>    severity              = optional(object({ operator = string, values = list(string) }))<br>    signal_type           = optional(object({ operator = string, values = list(string) }))<br>    target_resource       = optional(object({ operator = string, values = list(string) }))<br>    target_resource_group = optional(object({ operator = string, values = list(string) }))<br>    target_resource_type  = optional(object({ operator = string, values = list(string) }))<br>  })</pre> | `null` | no |
| description | Optional description of the rule. | `string` | `null` | no |
| enabled | Whether the rule is enabled. | `bool` | `true` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the rule. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Optional. Explicit name. If null, computed (apr-{sub}-{env}-{region}-{workload}). | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, frc) | `string` | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| workload | Workload suffix (e.g. 01) | `string` | `"01"` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Alert Processing Rule. |
| lock\_id | Management lock ID (null if var.lock is null). |
| name | The name of the Alert Processing Rule. |
| resource | The complete Alert Processing Rule resource object. |
<!-- END_TF_DOCS -->
