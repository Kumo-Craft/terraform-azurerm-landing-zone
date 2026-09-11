# LogAnalyticsWorkspace

Canonical **Azure Log Analytics Workspace** leaf (`azurerm_log_analytics_workspace`, `Microsoft.OperationalInsights`) + optional Resource Lock. Secure-by-default.

This is the base brick: compose it rather than inlining `azurerm_log_analytics_workspace` (e.g. [`SecuritySentinel`](../SecuritySentinel/) composes it for the SOC workspace).

## Secure by default (house defaults diverge from Azure's)

Azure defaults `local_authentication_enabled`, `internet_ingestion_enabled` and `internet_query_enabled` to **`true`**. This module defaults them to **`false`** ([workspace design](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design), [WAF – Log Analytics](https://learn.microsoft.com/azure/well-architected/service-guides/azure-log-analytics)):

- **`local_authentication_enabled = false`** — workspace-key auth off → **Microsoft Entra ID only**.
- **`internet_ingestion_enabled = false`** / **`internet_query_enabled = false`** — private only; reach it via an **AMPLS** (Azure Monitor Private Link Scope) using the `id` output.
- **`allow_resource_only_permissions = true`** — resource-context RBAC (read data for resources you can see).
- **`daily_quota_gb = -1`** (no cap, Azure default). Microsoft warns a daily cap must **not** be a primary cost tool: once hit, **ingestion stops**. Use ingestion-time transformations for cost control.

## Naming

Delegated to the [`Naming`](../Naming/) submodule — upstream `Azure/naming` slug for this type is **`log`**: `log-{acr}-{env}-{region}-{workload}`. Set `name` to override (escape hatch), e.g. to preserve a historic house `law-` prefix — that's what `SecuritySentinel` does.

## Usage

```hcl
module "law" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/LogAnalyticsWorkspace?ref=v0.3.0"

  subscription_acronym = "sec"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "soc"

  location            = "germanywestcentral"
  resource_group_name = azurerm_resource_group.soc.name

  retention_in_days = 90     # Sentinel-enabled workspaces get 90 days free
  # daily_quota_gb  = -1     # default: no cap

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Commitment tier (≥ 100 GB/day)

```hcl
sku                                = "CapacityReservation"
reservation_capacity_in_gb_per_day = 200
```

> Changing `sku` to `CapacityReservation` (or raising the tier) starts a **31-day commitment** during which you can't drop to a lower tier ([cost-logs](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs#commitment-tiers)).

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | `null` | Explicit name (4-63, letters/digits/hyphen, no leading/trailing hyphen). Null = derived `log-…`. |
| `subscription_acronym` / `environment` / `region_code` / `workload` | `string` | `null` | Naming components (all required unless `name` set). |
| `location` | `string` | — (required) | Azure region. |
| `resource_group_name` | `string` | — (required) | RG hosting the workspace. |
| `sku` | `string` | `"PerGB2018"` | `PerGB2018` / `CapacityReservation` / legacy tiers / `LACluster`. |
| `retention_in_days` | `number` | `30` | Interactive retention, 30-730. |
| `daily_quota_gb` | `number` | `-1` | Daily cap in GB. `-1` = **no cap**. |
| `reservation_capacity_in_gb_per_day` | `number` | `null` | Commitment tier — only with `sku = CapacityReservation`. |
| `local_authentication_enabled` | `bool` | `false` | Workspace-key auth (false = Entra only). |
| `internet_ingestion_enabled` | `bool` | `false` | Public ingestion. |
| `internet_query_enabled` | `bool` | `false` | Public query. |
| `allow_resource_only_permissions` | `bool` | `true` | Resource-context RBAC. |
| `cmk_for_query_forced` | `bool` | `null` | Force customer-managed storage for queries (needs a CMK dedicated cluster). |
| `identity` | `object({ type, identity_ids })` | `null` | Optional SystemAssigned / UserAssigned identity. |
| `data_collection_rule_id` | `string` | `null` | Default DCR for the workspace. |
| `immediate_data_purge_on_30_days_enabled` | `bool` | `null` | Purge data immediately after 30 days. |
| `lock` | `object({ kind, name })` | `null` | Optional CanNotDelete/ReadOnly lock. |
| `tags` | `map(string)` | `{}` | Tags (a `CreatedOn` tag is added). |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Workspace resource ID (AMPLS scoped service, DCR destination, diagnostic settings). |
| `name` | Workspace name. |
| `workspace_id` | Workspace (customer) ID — GUID. |
| `primary_shared_key` / `secondary_shared_key` | Shared keys (sensitive). Unusable when `local_authentication_enabled = false`. |
| `lock_ids` | Map of lock IDs (empty when `lock` is null). |

No raw `resource` output on purpose — exporting the whole object surfaces provider-deprecated attributes as plan warnings (cf. the FlowLogs / KeyVault / StorageAccount curations).

## Out of scope (compose separately)

- **AMPLS / Private Link** — this module sets the workspace private; wire it into a Private Link Scope using the `id` output.
- **Tables** — per-table retention / custom logs (`azurerm_log_analytics_workspace_table*`).
- **Dedicated cluster + CMK** — consider at ≥ 100 GB/day ([cost](https://learn.microsoft.com/azure/azure-monitor/logs/cost-logs)).
- **Solutions, DCR associations, diagnostic settings.**

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: derived naming, name override, secure defaults, commitment tier, identity, lock, and validators (retention bounds, daily quota, sku, reservation tier/sku pairing, name charset, UserAssigned without ids). Run: `terraform init -backend=false && terraform test`.
