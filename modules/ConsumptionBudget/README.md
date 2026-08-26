# ConsumptionBudget

A **Cost Management budget** scoped to a **resource group**, with **Actual + Forecasted** threshold notifications to emails / Action Groups / RBAC roles. A soft cost guard-rail: it **never stops consumption** (unlike a hard daily cap) — it only notifies — which is the Microsoft-recommended way to control cost without blinding a workload during a spike.

Wraps [`azurerm_consumption_budget_resource_group`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_resource_group) (`Microsoft.Consumption` 2019-10-01).

## Why (Microsoft guidance)

Grounded in [Create and manage budgets](https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-acm-create-budgets):

- **Notify, don't block.** Budgets trigger notifications when thresholds are exceeded; resources aren't affected and consumption isn't stopped. Use this instead of hard daily caps as a cost guard-rail.
- **Actual + Forecasted.** *Actual* fires on accrued cost; *Forecasted* fires when projected spend is likely to exceed the threshold — advance warning. Both are supported per notification via `threshold_type`.
- **Up to 5 thresholds.** Azure allows 1–5 notification blocks; thresholds are a percentage of the amount in the range 0.01–1000 % (1000 % lets you alert well past 100 %).
- **RBAC-role recipients** (`contact_roles`, e.g. `Owner`) are only assignable via the API/Terraform, not the portal.
- **Reset period.** `time_grain` = calendar (`Monthly`/`Quarterly`/`Annually`) or invoice-aligned (`BillingMonth`/`BillingQuarter`/`BillingAnnual`). The budget resets automatically each period.

## Usage

```hcl
module "budget" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/ConsumptionBudget?ref=v0.3.0"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "platform"

  resource_group_id = azurerm_resource_group.platform.id
  amount             = 2000
  time_grain         = "Monthly"
  start_date         = "2026-07-01T00:00:00Z"

  notifications = [
    { threshold = 80, threshold_type = "Actual", contact_emails = ["finops@example.com"] },
    { threshold = 100, threshold_type = "Actual", contact_groups = [azurerm_monitor_action_group.finops.id] },
    { threshold = 100, threshold_type = "Forecasted", operator = "GreaterThanOrEqualTo", contact_roles = ["Owner"] },
  ]
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/ConsumptionBudget"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "platform"
  resource_group_id    = dependency.rg.outputs.id
  amount               = 2000
  start_date           = "2026-07-01T00:00:00Z"
  notifications = [
    { threshold = 90, threshold_type = "Actual", contact_groups = [dependency.ag.outputs.id] },
  ]
}
```

## Naming

Follows the repo convention via the [`Naming`](../Naming/) submodule: `bdg-{acr}-{env}-{region}-{workload}`. Set `name` to override (escape hatch); when `name` is set, the Naming submodule is not instantiated.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | `null` | Explicit name override. Null = derived `bdg-…`. |
| `subscription_acronym` | `string` | `null` | Naming component (required unless `name` set). |
| `environment` | `string` | `null` | Naming component (`prod`/`nprd`). |
| `region_code` | `string` | `null` | Naming component (e.g. `gwc`). |
| `workload` | `string` | `"budget"` | Naming suffix segment. |
| `resource_group_id` | `string` | — (required) | Full ARM ID of the scoped resource group. |
| `amount` | `number` | — (required) | Budget amount (> 0). |
| `time_grain` | `string` | `"Monthly"` | Reset period (see above). ForceNew. |
| `start_date` | `string` | — (required) | First-of-month UTC ISO-8601 (`YYYY-MM-01T00:00:00Z`). ForceNew. |
| `end_date` | `string` | `null` | Optional end date. Null = ~10y after start. |
| `notifications` | `list(object)` | — (required) | 1–5 threshold blocks (see below). |
| `filter` | `object` | `null` | Optional dimension/tag filter. Null = whole RG. |
| `lock` | `object({ kind, name })` | `null` | Optional CanNotDelete/ReadOnly lock. |
| `tags` | `map(string)` | `{}` | **Unused** — budgets don't persist tags; kept for interface consistency. |

### `notifications[*]`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `threshold` | `number` | — (required) | Percentage of amount, `(0, 1000]`. |
| `threshold_type` | `string` | `"Actual"` | `Actual` or `Forecasted`. |
| `operator` | `string` | `"GreaterThan"` | `EqualTo` / `GreaterThan` / `GreaterThanOrEqualTo`. |
| `enabled` | `bool` | `true` | Enable this notification. |
| `contact_emails` | `list(string)` | `[]` | Email recipients. |
| `contact_groups` | `list(string)` | `[]` | Action Group resource IDs. |
| `contact_roles` | `list(string)` | `[]` | RBAC roles (e.g. `Owner`). |

At least one of `contact_emails` / `contact_groups` / `contact_roles` per notification.

## Outputs

| Name | Description |
|------|-------------|
| `id` | Budget resource ID. |
| `name` | Full budget name. |
| `resources` | Full budget resource object (mirrors sibling modules). |
| `lock_ids` | Map of lock key => lock ID (empty when `lock` is null). |

## Notes

- **No tags server-side.** `azurerm_consumption_budget_resource_group` has no `tags` argument — the `tags` variable is accepted for interface parity but applied to nothing.
- **ForceNew fields.** `resource_group_id`, `time_grain` and `start_date` are immutable — changing any recreates the budget.
- **Subscription-scope budgets** are out of scope here (this module is RG-scoped); use `azurerm_consumption_budget_subscription` in a dedicated module if needed.

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: derived naming, name override, multi-notification (Actual+Forecasted), filter block, optional lock, and validators (empty/no-contact notifications, bad start_date/time_grain/rg_id). Run: `terraform init -backend=false && terraform test`.

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
| [azurerm_consumption_budget_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_resource_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| amount | Budget amount in the billing account currency. | `number` | n/a | yes |
| notifications | Threshold notifications. 1 to 5 blocks. threshold is a percentage in (0, 1000]. | <pre>list(object({<br>    enabled        = optional(bool, true)<br>    threshold      = number<br>    operator       = optional(string, "GreaterThan") # GreaterThan | EqualTo | GreaterThanOrEqualTo<br>    threshold_type = optional(string, "Actual")      # Actual | Forecasted<br>    contact_emails = optional(list(string), [])<br>    contact_groups = optional(list(string), []) # Action Group resource IDs<br>    contact_roles  = optional(list(string), []) # RBAC role names: Owner/Contributor/Reader<br>  }))</pre> | n/a | yes |
| resource\_group\_id | Full ARM ID of the resource group the budget is scoped to (/subscriptions/../resourceGroups/..). | `string` | n/a | yes |
| start\_date | Budget start date, ISO-8601, first day of a month, UTC (e.g. 2026-07-01T00:00:00Z). Immutable once set; must be <= 12 months in the past (>= 2017-06-01). | `string` | n/a | yes |
| end\_date | Optional budget end date (ISO-8601). Null = provider default (~10y after start). | `string` | `null` | no |
| environment | Environment code (prod / nprd). | `string` | `null` | no |
| filter | Optional budget filter (restrict to dimensions/tags). Null = whole RG scope. dimension/tag operator must be 'In'. | <pre>object({<br>    dimensions = optional(list(object({<br>      name     = string<br>      operator = optional(string, "In")<br>      values   = list(string)<br>    })), [])<br>    tags = optional(list(object({<br>      name     = string<br>      operator = optional(string, "In")<br>      values   = list(string)<br>    })), [])<br>  })</pre> | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) applied to the budget. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit name override (escape hatch). If null, derived via ../Naming (bdg-{acr}-{env}-{region}-{workload}). | `string` | `null` | no |
| region\_code | Region code (e.g. gwc). | `string` | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con, api). | `string` | `null` | no |
| tags | Tags. NOTE: azurerm\_consumption\_budget\_* has no tags argument (budgets don't persist tags server-side); kept for module-interface consistency, not applied to any resource. | `map(string)` | `{}` | no |
| time\_grain | Reset period. One of: Monthly, Quarterly, Annually, BillingMonth, BillingQuarter, BillingAnnual. Immutable (ForceNew). | `string` | `"Monthly"` | no |
| workload | Workload name (naming suffix segment). | `string` | `"budget"` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | Resource ID of the budget. |
| lock\_ids | Map of lock key => management lock ID (empty map when var.lock is null). |
| name | Full budget name. |
| resources | Full budget resource object. |
<!-- END_TF_DOCS -->
