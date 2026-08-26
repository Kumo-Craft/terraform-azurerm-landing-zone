# LogAnalyticsAlerts

Deploys KQL-based scheduled query alert rules (`azurerm_monitor_scheduled_query_rules_alert_v2`) against a Log Analytics Workspace, plus an optional **Logs Ingestion API pipeline** (DCE + DCR + custom `*_CL` tables + RBAC) for clients using the modern OAuth-based ingest path.

## Breaking changes (v0.2.47)

### F-14 — `ingestion_public_network_access_enabled` default flipped to `false`

**CAF secure-by-default.** The default is now `false` (Private Endpoint / AMPLS required for DCE ingest traffic).

**Migration recipe**

Callers relying on Microsoft-hosted Azure DevOps agents or other clients without Private Endpoint connectivity MUST set the variable explicitly before upgrading:

```hcl
module "log_analytics_alerts" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/LogAnalyticsAlerts?ref=v0.2.47"

  # REQUIRED after v0.2.47 if using Microsoft-hosted ADO agents:
  ingestion_public_network_access_enabled = true

  # ... other inputs
}
```

If this is not set before the first apply after upgrade, the DCE will be reconfigured to reject public traffic, which will break CI/CD log ingestion from Microsoft-hosted agents. Self-hosted agents on the private network (e.g. an AKS pod in the hub VNet) are unaffected.

## Provider requirements

| Provider | Version |
|---|---|
| `hashicorp/azurerm` | `~> 4.0` |
| `hashicorp/time` | `>= 0.9.0` |
| `Azure/azapi` | `~> 2.4` |

The `azapi` provider is required for custom table creation via the `Microsoft.OperationalInsights/workspaces/tables@2022-10-01` REST API. The `azurerm` provider does not expose an equivalent resource for custom `*_CL` Analytics tables. Pin `azapi ~> 2.4` in your Terragrunt root `generate "providers"` block alongside `azurerm`.

## Usage

### Standalone

```hcl
module "log_analytics_alerts" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/LogAnalyticsAlerts?ref=v0.2.47"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "monitoring"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-monitoring"

  law_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-mgm-prod-gwc-01"

  action_group_ids = [
    "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-gwc-monitoring/providers/Microsoft.Insights/actionGroups/ag-mgm-prod-gwc-ops"
  ]

  alerts = {
    high-cpu = {
      display_name         = "High CPU on AKS nodes"
      kql                  = "Perf | where CounterName == '% Processor Time' and CounterValue > 90 | summarize count() by Computer"
      severity             = 2
      evaluation_frequency = "PT5M"
      window_duration      = "PT15M"
      failing_periods = {
        number_of_evaluation_periods             = 3
        minimum_failing_periods_to_trigger_alert = 2
      }
    }
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt composition

```hcl
dependency "alz_management" {
  config_path = "../alz-management"
}

dependency "action_group" {
  config_path = "../action-group"
}

inputs = {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "monitoring"
  location             = "germanywestcentral"
  resource_group_name  = dependency.alz_management.outputs.resource_group_name

  law_id           = dependency.alz_management.outputs.law_id
  action_group_ids = [dependency.action_group.outputs.id]

  alerts = {
    high-cpu = {
      kql      = "Perf | where CounterName == '% Processor Time' | summarize avg(CounterValue) by Computer | where avg_CounterValue > 90"
      severity = 2
    }
  }
}
```

### With DCR Logs Ingestion pipeline

```hcl
module "log_analytics_alerts" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/LogAnalyticsAlerts?ref=v0.2.47"

  # ... naming / location / law_id / action_group_ids ...

  custom_tables = {
    AppEvents = {
      columns = {
        EventType = "string"
        Severity  = "int"
        Message   = "string"
      }
      plan = "Analytics"
      ingestion = {
        input_columns = {
          EventType = "string"
          Severity  = "int"
          Message   = "string"
        }
      }
    }
  }

  ingestion_principal_ids = [
    "aaaaaaaa-0000-0000-0000-000000000001"  # CI/CD SPN object ID
  ]

  # Default false — set true only for Microsoft-hosted ADO agents.
  ingestion_public_network_access_enabled = false

  alerts = {}
}

# Reference the DCR immutable ID and ingest endpoint in your CI/CD pipeline:
# output.data_collection_rule_immutable_id
# output.data_collection_endpoint_logs_ingestion_endpoint
```

## Inputs

| Name | Type | Default | Required | Description |
|---|---|---|---|---|
| `name` | `string` | `null` | No | Explicit name override. If null, derived as `sqr-{acr}-{env}-{region}-{workload}`. |
| `subscription_acronym` | `string` | `null` | Cond. | Required when `name` is null. |
| `environment` | `string` | `null` | Cond. | Required when `name` is null. |
| `region_code` | `string` | `null` | Cond. | Required when `name` is null. |
| `workload` | `string` | `"custom-alerts"` | No | Workload label for naming. |
| `location` | `string` | — | Yes | Azure region. |
| `resource_group_name` | `string` | — | Yes | Resource group for all resources. |
| `law_id` | `string` | — | Yes | Log Analytics Workspace ARM ID. |
| `alerts` | `map(object)` | — | Yes | Map of KQL alert rules. |
| `action_group_ids` | `list(string)` | `[]` | No | Default Action Group IDs. |
| `custom_tables` | `map(object)` | `{}` | No | Custom `*_CL` table definitions. |
| `ingestion_principal_ids` | `list(string)` | `[]` | No | Principal IDs for Logs Ingestion API access. |
| `ingestion_public_network_access_enabled` | `bool` | `false` | No | Allow public DCE ingest traffic. |
| `lock` | `object` | `null` | No | ResourceLock applied to each alert rule. |
| `tags` | `map(string)` | `{}` | No | Tags applied to all resources. |

## Outputs

| Name | Description |
|---|---|
| `alert_ids` | Map of alert key -> resource ID. |
| `alert_names` | Map of alert key -> full resource name. |
| `resources` | Full map of alert rule resource objects. |
| `data_collection_endpoint_id` | DCE resource ID (null if no ingestion). |
| `data_collection_endpoint_logs_ingestion_endpoint` | DCE logs ingest URL. |
| `data_collection_rule_id` | DCR resource ID (null if no ingestion). |
| `data_collection_rule_immutable_id` | DCR immutable ID for API URL path. |
| `dcr_stream_names` | Map of table key -> DCR stream name. |
| `lock_ids` | Map of alert key -> lock ID (empty when `var.lock` is null). |

## Notes

### azapi provider dependency

The module creates custom `*_CL` Analytics tables via `azapi_resource` targeting `Microsoft.OperationalInsights/workspaces/tables@2022-10-01`. The `azurerm` provider does not expose an equivalent resource. The `azapi ~> 2.4` provider must be declared in your Terragrunt root alongside `azurerm`.

### Sprint 6 validators

- `var.alerts[*].severity` must be `0..4` (0=Critical, 4=Verbose) — validated at plan time.
- `var.alerts[*].failing_periods.minimum_failing_periods_to_trigger_alert` must be `<=` `number_of_evaluation_periods` — Azure rejects inverted M-of-N at apply time; validated at plan time.

### DCR Logs Ingestion endpoint URL

Ingest clients need the DCE logs ingestion endpoint and the DCR immutable ID:

```
POST https://<output.data_collection_endpoint_logs_ingestion_endpoint>/dataCollectionRules/<output.data_collection_rule_immutable_id>/streams/Custom-<TableName>_CL?api-version=2023-01-01
```

Use `output.dcr_stream_names` to look up the correct stream name per table key.
