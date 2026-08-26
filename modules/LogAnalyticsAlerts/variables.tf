###############################################################
# MODULE: LogAnalyticsAlerts - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################

variable "name" {
  description = "Explicit name override (escape hatch). If null, derived from naming convention via ../Naming (sqr-{acr}-{env}-{region}-{workload})."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    error_message = "Either var.name must be set OR all 4 naming components (subscription_acronym, environment, region_code, workload) must be non-null."
  }
}

variable "subscription_acronym" {
  description = "Subscription acronym (e.g. mgm, con, api)."
  type        = string
  default     = null

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  description = "Environment code (prod / nprd)."
  type        = string
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  description = "Region code (e.g. gwc)."
  type        = string
  default     = null

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "location" {
  description = "Azure region (e.g. germanywestcentral)."
  type        = string
}

variable "workload" {
  description = "Workload name (used for tagging / DCE-DCR naming). Not part of alert naming."
  type        = string
  default     = "custom-alerts"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

variable "resource_group_name" {
  description = "Resource group that will hold the alert rules, DCE and DCR."
  type        = string
}

variable "law_id" {
  description = "Resource ID of the Log Analytics Workspace the KQL queries run against (and where DCR data is routed)."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.law_id))
    error_message = "law_id must be a valid Log Analytics Workspace ARM ID."
  }
}

variable "custom_tables" {
  description = <<-EOT
    Custom Log Analytics tables (`*_CL`) consumed by alert queries.
    Key = table name WITHOUT the `_CL` suffix (Azure appends it automatically).

    Fields:
    - `columns`               - (Required) Map of column name -> LAW column type. Valid types (lowercase):
                                string, int, long, real, boolean, datetime, guid, dynamic.
                                DO NOT declare `TimeGenerated` - the platform adds it automatically as
                                datetime on Analytics tables. If declared it is filtered out by the module.
    - `retention_days`        - (Optional) Interactive retention in days. Default inherits from workspace.
    - `total_retention_days`  - (Optional) Total retention (archive included). Default inherits.
    - `plan`                  - (Optional) Analytics | Basic. Default Analytics.
    - `ingestion`             - (Optional) Enables a DCR stream for this table. When set, the module
                                provisions a DCE + DCR + role assignments so that clients can POST
                                events via the modern Logs Ingestion API (OAuth). Nested fields:
        * `input_columns`   - (Required) Schema (map name -> type) the client sends in each JSON row.
                              May differ from the table columns: the DCR transforms it into the
                              table schema via `transform_kql`.
        * `transform_kql`   - (Optional) KQL transform applied on each row before it is written to
                              the table. Default:
                              `source | extend TimeGenerated = iff(isnull(TimeGenerated), now(), TimeGenerated)`
                              which promotes a string `TimeGenerated` field (or falls back to now()).
  EOT
  type = map(object({
    columns              = map(string)
    retention_days       = optional(number)
    total_retention_days = optional(number)
    plan                 = optional(string, "Analytics")
    ingestion = optional(object({
      input_columns = map(string)
      transform_kql = optional(string)
    }))
  }))
  default  = {}
  nullable = false
}

variable "ingestion_principal_ids" {
  description = <<-EOT
    Object IDs of the principals (typically CI/CD Service Principals or workload identities)
    that must be allowed to POST events to the DCR via the Logs Ingestion API. The module
    grants each one "Monitoring Metrics Publisher" at the DCR scope. Ignored if no
    `ingestion` block is declared on any `custom_tables` entry.
  EOT
  type        = list(string)
  default     = []
  nullable    = false
}

variable "ingestion_public_network_access_enabled" {
  description = <<-EOT
    Whether the DCE accepts traffic from the public internet. Default false (CAF secure-by-default).
    Set to true when the DCE must accept traffic from Microsoft-hosted Azure DevOps agents
    or other clients without Private Endpoint connectivity.

    BREAKING (v0.2.47): Default changed from true to false. Callers relying on public access
    (e.g. Microsoft-hosted ADO agents) MUST set this to true explicitly before upgrading.
  EOT
  type        = bool
  default     = false
}

variable "action_group_ids" {
  description = "List of Action Group IDs fired when any alert triggers. Can be overridden per-alert."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.action_group_ids : can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.Insights/actionGroups/[^/]+$", id))])
    error_message = "Each action_group_ids[*] must be a valid Action Group ARM ID."
  }
}

variable "alerts" {
  description = <<-EOT
    Map of KQL-based Log Analytics alerts (azurerm_monitor_scheduled_query_rules_alert_v2).
    Key = short alert identifier (used to build the resource name).

    Fields:
    - `display_name`                     - (Optional) Human-readable name shown in the portal. Defaults to key.
    - `description`                      - (Optional) Free text.
    - `kql`                              - (Required) KQL query producing the rows to count.
    - `severity`                         - (Optional, 0-4) 0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose. Default 2.
    - `evaluation_frequency`             - (Optional ISO8601) How often the query runs. Default PT5M.
    - `window_duration`                  - (Optional ISO8601) Lookback window. Default PT15M.
    - `threshold`                        - (Optional number) Threshold to compare against. Default 0.
    - `operator`                         - (Optional) GreaterThan, GreaterThanOrEqual, Equal, LessThan, LessThanOrEqual. Default GreaterThan.
    - `time_aggregation_method`          - (Optional) Count, Average, Minimum, Maximum, Total. Default Count.
    - `metric_measure_column`            - (Optional) Column to aggregate (required when time_aggregation_method != Count).
    - `failing_periods`                  - (Optional) number_of_evaluation_periods / minimum_failing_periods_to_trigger_alert. Default 1/1.
    - `auto_mitigation_enabled`          - (Optional bool) Default false (alerts stay active until resolved manually).
    - `enabled`                          - (Optional bool) Default true.
    - `action_group_ids`                 - (Optional list) Override default Action Groups for this alert.
    - `custom_properties`                - (Optional map) Passed to alert payload.
    - `mute_actions_after_alert_duration`- (Optional ISO8601) Mute action notifications after alert fires for this duration.
    - `skip_query_validation`            - (Optional bool) Skip KQL query validation at deploy time.
    - `query_time_range_override`        - (Optional ISO8601) Override the query time range.
    - `workspace_alerts_storage_enabled` - (Optional bool) Store alert state in the LAW instead of Azure Monitor.
  EOT
  type = map(object({
    display_name            = optional(string)
    description             = optional(string, "")
    kql                     = string
    severity                = optional(number, 2)
    evaluation_frequency    = optional(string, "PT5M")
    window_duration         = optional(string, "PT15M")
    threshold               = optional(number, 0)
    operator                = optional(string, "GreaterThan")
    time_aggregation_method = optional(string, "Count")
    metric_measure_column   = optional(string)
    failing_periods = optional(object({
      number_of_evaluation_periods             = number
      minimum_failing_periods_to_trigger_alert = number
    }), { number_of_evaluation_periods = 1, minimum_failing_periods_to_trigger_alert = 1 })
    auto_mitigation_enabled           = optional(bool, false)
    enabled                           = optional(bool, true)
    action_group_ids                  = optional(list(string))
    custom_properties                 = optional(map(string), {})
    mute_actions_after_alert_duration = optional(string)
    skip_query_validation             = optional(bool)
    query_time_range_override         = optional(string)
    workspace_alerts_storage_enabled  = optional(bool)
  }))
  nullable = false

  validation {
    condition = alltrue([
      for a in var.alerts : a.severity >= 0 && a.severity <= 4
    ])
    error_message = "Each alert severity must be in [0..4] (0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose)."
  }

  validation {
    condition = alltrue([
      for a in var.alerts :
      a.failing_periods.minimum_failing_periods_to_trigger_alert <= a.failing_periods.number_of_evaluation_periods
    ])
    error_message = "Each alert's failing_periods.minimum_failing_periods_to_trigger_alert must be <= number_of_evaluation_periods (Azure rejects min > total at apply time)."
  }
}

###############################################################
# RESOURCE LOCK — F-13
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) applied to each alert rule. Set to null to skip."
  type = object({
    kind = string
    name = optional(string, null)
  })
  default  = null
  nullable = true

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], coalesce(var.lock != null ? var.lock.kind : null, "CanNotDelete"))
    error_message = "lock.kind must be 'CanNotDelete' or 'ReadOnly'."
  }
}

variable "tags" {
  description = "Tags applied to every alert rule, DCE and DCR."
  type        = map(string)
  default     = {}
  nullable    = false
}
