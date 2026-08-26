###############################################################
# MODULE: FlowLogs - Variables
# VNet Flow Logs with optional Traffic Analytics
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. con, mgm, api)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload component for naming convention fl-{acr}-{env}-{region}-{workload}-{vnet_key}."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9_-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }

  # F-4: cross-var validator — workload must be set OR every entry must provide name.
  validation {
    condition = (
      var.workload != null ||
      alltrue([for v in values(var.vnets) : v.name != null])
    )
    error_message = "Either var.workload must be set, OR every entry in var.vnets must provide a name."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region"
  nullable    = false
}

variable "network_watcher_name" {
  type        = string
  description = "Name of the Network Watcher to host the flow log resources"
  nullable    = false
}

variable "network_watcher_resource_group_name" {
  type        = string
  description = "Resource group of the Network Watcher"
  nullable    = false
}

variable "storage_account_id" {
  type        = string
  description = "Storage Account resource ID for flow log data"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Storage/storageAccounts/[^/]+$", var.storage_account_id))
    error_message = "storage_account_id must be a valid Azure Storage Account resource ID."
  }
}

variable "vnets" {
  type = map(object({
    id      = string
    enabled = optional(bool, true)
    # F-3: per-entry name override
    name = optional(string)
    # F-5: per-entry lock
    lock = optional(object({
      kind = string
      name = optional(string)
    }))
    # F-6: per-entry role assignments
    role_assignments = optional(map(object({
      role_definition_id_or_name       = string
      principal_id                     = string
      principal_type                   = optional(string, "ServicePrincipal")
      condition                        = optional(string)
      condition_version                = optional(string)
      description                      = optional(string)
      skip_service_principal_aad_check = optional(bool, false)
    })), {})
  }))
  description = "Map of VNets to enable flow logs on. Key = short name used in the flow log resource name."
  nullable    = false

  # F-10: Reject non-VNet ARM IDs up-front. Passing an NSG ID would silently
  # regress to deprecated NSG flow logs (Azure EOL 2027-09-30).
  validation {
    condition = alltrue([
      for k, v in var.vnets :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", v.id))
    ])
    error_message = "Each var.vnets[*].id must be a valid Azure Virtual Network resource ID. Passing an NSG ID would silently regress to deprecated NSG flow logs (Azure EOL 2027-09-30)."
  }

  validation {
    condition = alltrue([
      for v in values(var.vnets) :
      v.lock == null || contains(["CanNotDelete", "ReadOnly"], v.lock.kind)
    ])
    error_message = "Each vnets[*].lock.kind must be \"CanNotDelete\" or \"ReadOnly\"."
  }

  validation {
    condition = alltrue([
      for v in values(var.vnets) :
      alltrue([
        for ra in values(v.role_assignments) :
        contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)
      ])
    ])
    error_message = "Each vnets[*].role_assignments[*].principal_type must be one of User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "retention_days" {
  type        = number
  default     = 90
  nullable    = false
  description = "Number of days to retain flow logs in the storage account (0 = forever / SA lifecycle policy)"

  validation {
    condition     = var.retention_days >= 0 && var.retention_days <= 365
    error_message = "retention_days must be between 0 and 365."
  }
}

variable "traffic_analytics" {
  type = object({
    enabled               = optional(bool, true)
    workspace_id          = string
    workspace_region      = string
    workspace_resource_id = string
    interval_minutes      = optional(number, 60)
  })
  default     = null
  description = "Traffic Analytics configuration. Set to null to disable."

  validation {
    condition     = var.traffic_analytics == null || contains([10, 60], try(var.traffic_analytics.interval_minutes, 60))
    error_message = "traffic_analytics.interval_minutes must be 10 or 60."
  }
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}
