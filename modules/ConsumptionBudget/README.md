# ConsumptionBudget

A **Cost Management budget** scoped to a **resource group** OR a **subscription** (pick exactly one), with **Actual + Forecasted** threshold notifications to emails / Action Groups / RBAC roles. A soft cost guard-rail: it **never stops consumption** (unlike a hard daily cap) — it only notifies — which is the Microsoft-recommended way to control cost without blinding a workload during a spike.

Wraps [`azurerm_consumption_budget_resource_group`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_resource_group) and [`azurerm_consumption_budget_subscription`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/consumption_budget_subscription) (`Microsoft.Consumption` 2019-10-01) — **one module, two mutually-exclusive resources** so naming / notifications / filter / lock stay identical across scopes.

## Scope — set EXACTLY one

Provide **either** `resource_group_id` **or** `subscription_id`, never both, never neither (enforced by an XOR validation). `subscription_id` accepts a **bare GUID** or a full `/subscriptions/<guid>` path (normalized internally). A subscription-level budget catches spend that no single RG budget would — e.g. a Log Analytics workspace drifting to 485 $/mo unnoticed.

```hcl
# Subscription-scoped budget (bare GUID accepted)
module "sub_budget" {
  source = "../ConsumptionBudget"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "subscription"

  subscription_id = "00000000-0000-0000-0000-000000000000"
  amount          = 5000
  start_date      = "2026-07-01T00:00:00Z"
  notifications   = [{ threshold = 90, threshold_type = "Forecasted", contact_emails = ["finops@example.com"] }]
}
```

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
  source = "git::https://dev.azure.com/azure-forge/Modules/_git/Modules//modules/ConsumptionBudget?ref=v0.3.0"

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
| `resource_group_id` | `string` | `null` | RG-scope: full ARM ID. **XOR** with `subscription_id`. |
| `subscription_id` | `string` | `null` | Subscription-scope: bare GUID or `/subscriptions/<guid>`. **XOR** with `resource_group_id`. |
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
| `id` | Budget resource ID (whichever scope is in use). |
| `name` | Full budget name. |
| `resources` | The **resource-group** budget object (null when subscription-scoped). |
| `subscription_budget` | The **subscription** budget object (null when RG-scoped). |
| `lock_ids` | Map of lock key => lock ID (empty when `lock` is null). |

## Notes

- **No tags server-side.** Neither `azurerm_consumption_budget_*` resource has a `tags` argument — the `tags` variable is accepted for interface parity but applied to nothing.
- **ForceNew fields.** `resource_group_id` / `subscription_id`, `time_grain` and `start_date` are immutable — changing any recreates the budget. In particular, **never derive `start_date` from `timestamp()`** — it would recreate the budget on every plan.
- **⚠️ `start_date` in the past must fall within the current `time_grain` period** (Azure constraint, *not* checkable at plan time — it depends on the apply date). With `Monthly` grain, a `start_date` in an already-elapsed month can be **rejected by the service at apply**. Use the first day of the current (or a future) period.
- **Each notification needs a recipient** — at least one of `contact_emails` / `contact_groups` / `contact_roles` (validated; Azure rejects an all-empty notification). Applies to both scopes.
- **`notification` is a set** — two notification blocks with identical field values collapse into one (Terraform/Azure set dedup); vary the threshold/type to keep them distinct.
- **Lock naming.** When `lock.name` is supplied, the created lock is named `"${lock.name}-budget"` (a `-budget` suffix is appended); leave `lock.name` null to use `../ResourceLock`'s derived default.

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: derived naming, name override, multi-notification (Actual+Forecasted), filter block, optional lock (both scopes), subscription scope (bare GUID + full path, normalization asserted), and validators (empty/no-contact notifications, bad start_date/time_grain/rg_id, XOR both-set and neither-set). Run: `terraform init -backend=false && terraform test`.
