###############################################################
# MODULE: AvdInsightsCollector - Variables
#
# Purpose-built DCR for Azure Virtual Desktop Insights: collects the
# performance counters + Windows event logs the AVD Insights workbook
# reads, and associates them with the session hosts.
#
# The Log Analytics Workspace is an INPUT (compose ../LogAnalyticsWorkspace) —
# this module never creates one. Same shape as ../ContainerInsightsCollector.
###############################################################

###############################################################
# NAMING CONVENTION
# Convention: dcr-{acr}-{env}-{region}-{workload}-avdinsights
#   e.g. dcr-avd-prod-gwc-01-avdinsights
# (mirrors AlzManagement's dcr-mgm-prod-gwc-01-vminsights)
###############################################################
variable "name" {
  description = "Explicit DCR name override (escape hatch). If null, derived via ../Naming (dcr-{acr}-{env}-{region}-{workload}-avdinsights)."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null)
    error_message = "Either var.name must be set OR all 3 naming components (subscription_acronym, environment, region_code) must be non-null. workload has a default."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. avd, shc, mgm)."

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters (or null when var.name is set)."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)."

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters (or null when var.name is set)."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)."

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters (or null when var.name is set)."
  }
}

variable "workload" {
  type        = string
  default     = "01"
  nullable    = false
  description = "Workload suffix in the DCR/DCRA names (the -avdinsights component is appended after it)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED
###############################################################
variable "location" {
  type        = string
  description = "Azure region for the DCR (must match the session hosts' region)."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group hosting the DCR."
  nullable    = false
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics Workspace the AVD Insights data is shipped to (compose ../LogAnalyticsWorkspace). This module does NOT create a workspace."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/.+/providers/Microsoft\\.OperationalInsights/workspaces/.+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a valid Log Analytics Workspace ARM ID."
  }
}

###############################################################
# SESSION HOSTS
###############################################################
variable "session_host_ids" {
  type        = list(string)
  default     = []
  nullable    = false
  description = <<-EOT
    Resource IDs of the AVD session host VMs to associate with the DCR.

    Defaults to [] on purpose: the DCR must be creatable BEFORE the session
    hosts exist (the host pool build consumes the workspace/DCR), so the usual
    flow is — apply once with [] to create the DCR, then a second apply once
    the hosts are up to create the associations. Passing unknown-at-plan host
    ids here would otherwise force a for_each on unknown keys.
  EOT
}

###############################################################
# DATA SOURCES — AVD Insights defaults
###############################################################
variable "performance_counters" {
  type = list(object({
    name                          = string
    sampling_frequency_in_seconds = number
    counter_specifiers            = list(string)
  }))
  nullable    = false
  description = <<-EOT
    Performance counters shipped to the Perf table (stream Microsoft-Perf).
    Defaults to the 20 counters AVD Insights reads, at Microsoft's documented
    sampling frequencies (two blocks because the frequencies differ):
      - 30s: 15 counters (disk queues, memory, processor, input delay, RemoteFX)
      - 60s: 5 counters (free space, disk sec/transfer, Terminal Services sessions)
    Source: https://learn.microsoft.com/azure/virtual-desktop/insights-costs
    Override to trim cost or add counters.
  EOT

  default = [
    {
      name                          = "avd-perf-30s"
      sampling_frequency_in_seconds = 30
      counter_specifiers = [
        "\\LogicalDisk(C:)\\Avg. Disk Queue Length",
        "\\LogicalDisk(C:)\\Current Disk Queue Length",
        "\\Memory(*)\\Available Mbytes",
        "\\Memory(*)\\Page Faults/sec",
        "\\Memory(*)\\Pages/sec",
        "\\Memory(*)\\% Committed Bytes In Use",
        "\\PhysicalDisk(*)\\Avg. Disk Queue Length",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Read",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Transfer",
        "\\PhysicalDisk(*)\\Avg. Disk sec/Write",
        "\\Processor Information(_Total)\\% Processor Time",
        "\\User Input Delay per Process(*)\\Max Input Delay",
        "\\User Input Delay per Session(*)\\Max Input Delay",
        "\\RemoteFX Network(*)\\Current TCP RTT",
        "\\RemoteFX Network(*)\\Current UDP Bandwidth",
      ]
    },
    {
      name                          = "avd-perf-60s"
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\LogicalDisk(C:)\\% Free Space",
        "\\LogicalDisk(C:)\\Avg. Disk sec/Transfer",
        "\\Terminal Services(*)\\Active Sessions",
        "\\Terminal Services(*)\\Inactive Sessions",
        "\\Terminal Services(*)\\Total Sessions",
      ]
    },
  ]

  validation {
    condition     = length(var.performance_counters) > 0
    error_message = "performance_counters must contain at least one block."
  }

  validation {
    condition = alltrue([
      for p in var.performance_counters :
      p.sampling_frequency_in_seconds >= 1 && p.sampling_frequency_in_seconds <= 1800
    ])
    error_message = "sampling_frequency_in_seconds must be between 1 and 1800."
  }

  validation {
    condition     = alltrue([for p in var.performance_counters : length(p.counter_specifiers) > 0])
    error_message = "Each performance_counters block must declare at least one counter specifier."
  }
}

variable "windows_event_logs" {
  type = list(object({
    name           = string
    x_path_queries = list(string)
  }))
  nullable    = false
  description = <<-EOT
    Windows event logs shipped to the Event table (stream Microsoft-Event).
    Defaults to the 6 logs AVD Insights reads.

    LEVEL CAVEAT: Microsoft documents the log NAMES but not the workbook's exact
    levels — the levels below are a deliberate cost trade-off, hence this override:
      - Application / System        -> Critical+Error+Warning only (Level 1,2,3).
        High volume; Information carries no diagnostic value for AVD here.
      - FSLogix x2 / TerminalServices x2 -> + Information (Level 1,2,3,4,0).
        Low volume, and exactly where profile/session failures are diagnosed.
    Windows levels: 0=LogAlways, 1=Critical, 2=Error, 3=Warning, 4=Information.
  EOT

  default = [
    {
      name = "avd-eventlogs"
      x_path_queries = [
        "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
        "System!*[System[(Level=1 or Level=2 or Level=3)]]",
        "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Admin!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-FSLogix-Apps/Operational!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",
        "Microsoft-FSLogix-Apps/Admin!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=0)]]",
      ]
    },
  ]

  validation {
    condition     = length(var.windows_event_logs) > 0
    error_message = "windows_event_logs must contain at least one block."
  }

  validation {
    condition     = alltrue([for w in var.windows_event_logs : length(w.x_path_queries) > 0])
    error_message = "Each windows_event_logs block must declare at least one XPath query."
  }
}

###############################################################
# LOCK
###############################################################
variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Optional Resource Lock on the DCR.

  Note: this module deliberately carries NO hardcoded lifecycle.prevent_destroy
  — a hardcoded guard has blocked legitimate destroys before (cf. Ampls). Use
  this variable when you want a delete guard.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Generated from kind if not specified.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply to the DCR."
}
