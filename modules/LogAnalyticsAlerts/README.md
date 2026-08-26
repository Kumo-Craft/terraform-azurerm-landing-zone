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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| dcr\_publisher | ../RoleAssignment | n/a |
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.custom_table](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_monitor_data_collection_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_endpoint) | resource |
| [azurerm_monitor_data_collection_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |
| [azurerm_monitor_scheduled_query_rules_alert_v2.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_scheduled_query_rules_alert_v2) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| alerts | Map of KQL-based Log Analytics alerts (azurerm\_monitor\_scheduled\_query\_rules\_alert\_v2).<br>Key = short alert identifier (used to build the resource name).<br><br>Fields:<br>- `display_name`                     - (Optional) Human-readable name shown in the portal. Defaults to key.<br>- `description`                      - (Optional) Free text.<br>- `kql`                              - (Required) KQL query producing the rows to count.<br>- `severity`                         - (Optional, 0-4) 0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose. Default 2.<br>- `evaluation_frequency`             - (Optional ISO8601) How often the query runs. Default PT5M.<br>- `window_duration`                  - (Optional ISO8601) Lookback window. Default PT15M.<br>- `threshold`                        - (Optional number) Threshold to compare against. Default 0.<br>- `operator`                         - (Optional) GreaterThan, GreaterThanOrEqual, Equal, LessThan, LessThanOrEqual. Default GreaterThan.<br>- `time_aggregation_method`          - (Optional) Count, Average, Minimum, Maximum, Total. Default Count.<br>- `metric_measure_column`            - (Optional) Column to aggregate (required when time\_aggregation\_method != Count).<br>- `failing_periods`                  - (Optional) number\_of\_evaluation\_periods / minimum\_failing\_periods\_to\_trigger\_alert. Default 1/1.<br>- `auto_mitigation_enabled`          - (Optional bool) Default false (alerts stay active until resolved manually).<br>- `enabled`                          - (Optional bool) Default true.<br>- `action_group_ids`                 - (Optional list) Override default Action Groups for this alert.<br>- `custom_properties`                - (Optional map) Passed to alert payload.<br>- `mute_actions_after_alert_duration`- (Optional ISO8601) Mute action notifications after alert fires for this duration.<br>- `skip_query_validation`            - (Optional bool) Skip KQL query validation at deploy time.<br>- `query_time_range_override`        - (Optional ISO8601) Override the query time range.<br>- `workspace_alerts_storage_enabled` - (Optional bool) Store alert state in the LAW instead of Azure Monitor. | <pre>map(object({<br>    display_name            = optional(string)<br>    description             = optional(string, "")<br>    kql                     = string<br>    severity                = optional(number, 2)<br>    evaluation_frequency    = optional(string, "PT5M")<br>    window_duration         = optional(string, "PT15M")<br>    threshold               = optional(number, 0)<br>    operator                = optional(string, "GreaterThan")<br>    time_aggregation_method = optional(string, "Count")<br>    metric_measure_column   = optional(string)<br>    failing_periods = optional(object({<br>      number_of_evaluation_periods             = number<br>      minimum_failing_periods_to_trigger_alert = number<br>    }), { number_of_evaluation_periods = 1, minimum_failing_periods_to_trigger_alert = 1 })<br>    auto_mitigation_enabled           = optional(bool, false)<br>    enabled                           = optional(bool, true)<br>    action_group_ids                  = optional(list(string))<br>    custom_properties                 = optional(map(string), {})<br>    mute_actions_after_alert_duration = optional(string)<br>    skip_query_validation             = optional(bool)<br>    query_time_range_override         = optional(string)<br>    workspace_alerts_storage_enabled  = optional(bool)<br>  }))</pre> | n/a | yes |
| law\_id | Resource ID of the Log Analytics Workspace the KQL queries run against (and where DCR data is routed). | `string` | n/a | yes |
| location | Azure region (e.g. germanywestcentral). | `string` | n/a | yes |
| resource\_group\_name | Resource group that will hold the alert rules, DCE and DCR. | `string` | n/a | yes |
| action\_group\_ids | List of Action Group IDs fired when any alert triggers. Can be overridden per-alert. | `list(string)` | `[]` | no |
| custom\_tables | Custom Log Analytics tables (`*_CL`) consumed by alert queries.<br>Key = table name WITHOUT the `_CL` suffix (Azure appends it automatically).<br><br>Fields:<br>- `columns`               - (Required) Map of column name -> LAW column type. Valid types (lowercase):<br>                            string, int, long, real, boolean, datetime, guid, dynamic.<br>                            DO NOT declare `TimeGenerated` - the platform adds it automatically as<br>                            datetime on Analytics tables. If declared it is filtered out by the module.<br>- `retention_days`        - (Optional) Interactive retention in days. Default inherits from workspace.<br>- `total_retention_days`  - (Optional) Total retention (archive included). Default inherits.<br>- `plan`                  - (Optional) Analytics \| Basic. Default Analytics.<br>- `ingestion`             - (Optional) Enables a DCR stream for this table. When set, the module<br>                            provisions a DCE + DCR + role assignments so that clients can POST<br>                            events via the modern Logs Ingestion API (OAuth). Nested fields:<br>    * `input_columns`   - (Required) Schema (map name -> type) the client sends in each JSON row.<br>                          May differ from the table columns: the DCR transforms it into the<br>                          table schema via `transform_kql`.<br>    * `transform_kql`   - (Optional) KQL transform applied on each row before it is written to<br>                          the table. Default:<br>                          `source | extend TimeGenerated = iff(isnull(TimeGenerated), now(), TimeGenerated)`<br>                          which promotes a string `TimeGenerated` field (or falls back to now()). | <pre>map(object({<br>    columns              = map(string)<br>    retention_days       = optional(number)<br>    total_retention_days = optional(number)<br>    plan                 = optional(string, "Analytics")<br>    ingestion = optional(object({<br>      input_columns = map(string)<br>      transform_kql = optional(string)<br>    }))<br>  }))</pre> | `{}` | no |
| environment | Environment code (prod / nprd). | `string` | `null` | no |
| ingestion\_principal\_ids | Object IDs of the principals (typically CI/CD Service Principals or workload identities)<br>that must be allowed to POST events to the DCR via the Logs Ingestion API. The module<br>grants each one "Monitoring Metrics Publisher" at the DCR scope. Ignored if no<br>`ingestion` block is declared on any `custom_tables` entry. | `list(string)` | `[]` | no |
| ingestion\_public\_network\_access\_enabled | Whether the DCE accepts traffic from the public internet. Default false (CAF secure-by-default).<br>Set to true when the DCE must accept traffic from Microsoft-hosted Azure DevOps agents<br>or other clients without Private Endpoint connectivity.<br><br>BREAKING (v0.2.47): Default changed from true to false. Callers relying on public access<br>(e.g. Microsoft-hosted ADO agents) MUST set this to true explicitly before upgrading. | `bool` | `false` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) applied to each alert rule. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit name override (escape hatch). If null, derived from naming convention via ../Naming (sqr-{acr}-{env}-{region}-{workload}). | `string` | `null` | no |
| region\_code | Region code (e.g. gwc). | `string` | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con, api). | `string` | `null` | no |
| tags | Tags applied to every alert rule, DCE and DCR. | `map(string)` | `{}` | no |
| workload | Workload name (used for tagging / DCE-DCR naming). Not part of alert naming. | `string` | `"custom-alerts"` | no |

## Outputs

| Name | Description |
|------|-------------|
| alert\_ids | Map of alert key -> resource ID. |
| alert\_names | Map of alert key -> full resource name. |
| data\_collection\_endpoint\_id | Resource ID of the Data Collection Endpoint (null if no ingestion configured). |
| data\_collection\_endpoint\_logs\_ingestion\_endpoint | Host used by Logs Ingestion API clients (e.g. https://<dce>.<region>.ingest.monitor.azure.com). |
| data\_collection\_rule\_id | Resource ID of the Data Collection Rule (null if no ingestion configured). |
| data\_collection\_rule\_immutable\_id | Immutable ID of the DCR - required in the Logs Ingestion API URL path. |
| dcr\_stream\_names | Map of custom-table key -> DCR stream name to POST to (Custom-<Table>\_CL). |
| lock\_ids | Map of alert key => management lock ID (empty map when var.lock is null). |
| resources | Full map of alert rule resource objects keyed by var.alerts logical name. |
<!-- END_TF_DOCS -->
