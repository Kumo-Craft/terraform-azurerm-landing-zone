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
