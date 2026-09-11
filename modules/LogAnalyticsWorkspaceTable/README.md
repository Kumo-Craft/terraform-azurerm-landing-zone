# LogAnalyticsWorkspaceTable

Manages the **plan** and **retention** of *existing* tables in a Log Analytics workspace (`azurerm_log_analytics_workspace_table`). Its main use is a **cost lever**: moving high-volume, low-query tables (e.g. the AKS control-plane audit tables) to the **Basic** plan.

`LogAnalyticsWorkspace` deliberately keeps table-level plan/retention *out of scope* — this module fills that gap. Compose the two side by side.

## Usage

```hcl
module "law_tables" {
  source = "../LogAnalyticsWorkspaceTable"

  workspace_id = dependency.law.outputs.id

  tables = {
    AKSAuditAdmin   = { plan = "Basic" }
    AKSControlPlane = { plan = "Basic" }
    # Analytics table with custom interactive + archive retention:
    # AppTraces = { plan = "Analytics", retention_in_days = 30, total_retention_in_days = 365 }
  }
}
```

## ⚠️ Important

- **Basic / Auxiliary plans do NOT support log alerts (scheduled query rules).** Move a table to Basic only if nothing queries it via alerts. (For AKS, keep alerting on Prometheus/metrics, not on the audit tables.) Basic also has query limitations (KQL subset, no cross-table joins, short interactive retention).
- **The table must already exist.** Resource-specific AKS tables (`AKSAudit`, `AKSAuditAdmin`, `AKSControlPlane`) only appear once the AKS diagnostic setting is in **`Dedicated`** mode (`diagnostic_log_analytics_destination_type = "Dedicated"` on the `Aks` module). Enable Dedicated first, then manage the table plan here — mind the apply ordering.
- `retention_in_days` (interactive retention) is **Analytics-only**; use `total_retention_in_days` for archive retention on Basic.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| workspace_id | Log Analytics workspace resource ID. | `string` | -- | Yes |
| tables | Map of table name => `{ plan, retention_in_days, total_retention_in_days }`. plan: Analytics (default) / Basic / Auxiliary. | `map(object)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| table_ids | Map of table name => table resource ID |
| table_plans | Map of table name => effective plan |

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

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_log_analytics_workspace_table.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace_table) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| workspace\_id | Resource ID of the Log Analytics workspace whose tables are managed. | `string` | n/a | yes |
| tables | Map of workspace tables whose plan / retention is managed. The map key is the<br>exact table name (e.g. "AKSAuditAdmin", "AKSControlPlane"). Only tables that<br>already exist in the workspace can be managed — resource-specific AKS* tables<br>appear only once the AKS diagnostic setting is in "Dedicated" mode.<br><br>- `plan`                    - (Optional) "Analytics" (default), "Basic" or "Auxiliary".<br>- `retention_in_days`       - (Optional) Interactive retention. ONLY valid for the<br>                              Analytics plan (Basic/Auxiliary use a fixed interactive<br>                              retention). Null = workspace default.<br>- `total_retention_in_days` - (Optional) Total (incl. archive/long-term) retention.<br>                              Valid for all plans. Null = workspace default. | <pre>map(object({<br>    plan                    = optional(string, "Analytics")<br>    retention_in_days       = optional(number, null)<br>    total_retention_in_days = optional(number, null)<br>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| table\_ids | Map of table name => azurerm\_log\_analytics\_workspace\_table ID. |
| table\_plans | Map of table name => effective plan. |
<!-- END_TF_DOCS -->
