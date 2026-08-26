# SecuritySentinel

Dedicated SOC workspace: a private **Log Analytics Workspace** + **Microsoft Sentinel** onboarding, plus opt-in data connectors (Entra ID, Defender for Cloud). Intended to live in a dedicated **Security** subscription, separate from the operational/management workspace.

The workspace itself is composed from the canonical [`../LogAnalyticsWorkspace`](../LogAnalyticsWorkspace/) leaf (state-migrated automatically via a `moved` block — no manual state surgery). The `law-` house prefix is preserved byte-for-byte through that module's `name` override; this module keeps the Sentinel-specific posture (no daily cap, 90-day retention).

## Why a dedicated workspace (CAF / Well-Architected)

Grounded in Microsoft guidance ([Design a Log Analytics workspace architecture](https://learn.microsoft.com/azure/azure-monitor/logs/workspace-design), [WAF – Log Analytics](https://learn.microsoft.com/azure/well-architected/service-guides/azure-log-analytics)):

- **Ownership segregation.** A dedicated Sentinel workspace separates security-team data from operational (Azure Monitor) data. Microsoft explicitly lists this as the driver when a security team requires a dedicated workspace. Pairs with `AlzManagement`'s `enable_sentinel = false` (management LAW stays ops-only).
- **No daily cap by default (`daily_quota_gb = -1`).** Microsoft warns a daily cap must *not* be a primary cost tool: once hit, ingestion stops and the SOC goes blind during exactly the spike you care about. Use ingestion-time transformations for cost control, not a cap.
- **90-day interactive retention default.** A Sentinel-enabled workspace gets 90 days free (vs 31 for plain LAW), so `log_retention_days = 90` matches the free tier.
- **Secure-by-default.** Local (workspace-key) auth disabled → Entra ID only; public ingestion/query off (reach it privately via AMPLS); `allow_resource_only_permissions = true`. Uses the non-deprecated `local_authentication_enabled` argument (the `_disabled` form is removed in azurerm v5).

## Usage

### Standalone

```hcl
module "sentinel" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/SecuritySentinel?ref=v0.2.91"

  subscription_acronym = "sec"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "01"
  location             = "germanywestcentral"
  resource_group_name  = "rg-sec-prod-gwc-sentinel"

  # opt-in connectors (need tenant / subscription permissions)
  connectors = {
    entra_id           = true
    defender_for_cloud = true
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/SecuritySentinel"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "01"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
  tags                 = include.root.inputs.common_tags
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `subscription_acronym` | `string` | — (required) | Subscription acronym (e.g. `sec`). |
| `environment` | `string` | — (required) | Environment (`prod`/`nprd`). |
| `region_code` | `string` | — (required) | Region short code (e.g. `gwc`). |
| `workload` | `string` | `"01"` | Workload/instance suffix. |
| `location` | `string` | — (required) | Azure region. |
| `resource_group_name` | `string` | — (required) | RG hosting the Sentinel LAW. |
| `log_retention_days` | `number` | `90` | Interactive retention (days). |
| `daily_quota_gb` | `number` | `-1` | Daily ingestion cap in GB. `-1` = **no cap** (recommended). |
| `law_internet_ingestion_enabled` | `bool` | `false` | Allow public ingestion (`false` = private via AMPLS). |
| `law_internet_query_enabled` | `bool` | `false` | Allow public query (`false` = private via AMPLS). |
| `law_local_authentication_disabled` | `bool` | `true` | Disable workspace-key auth → Entra ID only. |
| `enable_cmk` | `bool` | `false` | Customer-managed key for Sentinel onboarding. |
| `connectors` | `object({ entra_id, defender_for_cloud })` | `{}` | Toggle built-in data connectors (off by default). |
| `connector_tenant_id` | `string` | `null` | Tenant id for the Entra ID connector (null = current). |
| `connector_subscription_id` | `string` | `null` | Subscription id for the Defender connector (null = current). |
| `tags` | `map(string)` | `{}` | Tags. |

## Outputs

| Name | Description |
|------|-------------|
| `law_id` | Resource id of the Sentinel LAW (for AMPLS scoped service). |
| `law_name` | Name of the Sentinel LAW. |
| `law_workspace_id` | Workspace (customer) id — GUID. |
| `resource_group_name` | RG hosting the Sentinel LAW. |

## Out of scope (handle downstream / ops)

- **Table-level & resource-context RBAC** — grant/deny access to specific Sentinel tables per team ([manage access](https://learn.microsoft.com/azure/azure-monitor/logs/manage-access)). Not managed here.
- **Long-term / archive retention** (up to 12 years) beyond the interactive `log_retention_days` — configure per table if compliance requires.
- **Dedicated Log Analytics cluster + commitment tier** — consider at ≥ 100 GB/day ingestion for cost/perf ([reduce Sentinel costs](https://learn.microsoft.com/azure/sentinel/billing-reduce-costs)).
- **Private connectivity (AMPLS)** — this module sets the workspace private (public off); wire the workspace into an Azure Monitor Private Link Scope separately (use the `law_id` output).
- **Customer-managed keys (`enable_cmk`)** — the flag only sets `customer_managed_key_enabled` on the onboarding; it provisions nothing. CMK requires a **Log Analytics dedicated cluster (≥ 100 GB/day) with CMK enabled**, this workspace **linked** to it, a **Key Vault** (same region, soft-delete + purge protection) holding the key, the cluster identity granted wrap/unwrap, and the Cosmos DB RP registered ([Set up Sentinel CMK](https://learn.microsoft.com/azure/sentinel/customer-managed-keys)). MS supports CMK onboarding only via REST/az CLI (not ARM), so the flag can fail unless that infra already exists. **Leave `false`** unless you run a dedicated cluster — data is still encrypted at rest with Microsoft-managed keys either way.

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: secure-default posture, connectors off by default, connectors opt-in. Run: `terraform init -backend=false && terraform test`.
