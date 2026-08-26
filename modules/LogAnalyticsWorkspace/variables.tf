###############################################################
# MODULE: LogAnalyticsWorkspace - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# Delegated to ../Naming (upstream Azure/naming slug: log)
#   log-{acr}-{env}-{region}-{workload}
# Callers keeping a historic prefix (e.g. law-) pass var.name.
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit workspace name. If null, computed via ../Naming (log-{acr}-{env}-{region}-{workload}). Use this to preserve a legacy/house prefix (e.g. law-...)."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }

  validation {
    # Azure: 4-63 chars, letters/digits/hyphen, hyphen not first nor last.
    condition     = var.name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{2,61}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 4 to 63 characters of letters, digits or hyphens, and must not start or end with a hyphen."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. sec, mgm, con)."

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)."

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)."

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name (naming suffix segment)."

  validation {
    condition     = var.workload == null || can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED
###############################################################
variable "location" {
  type        = string
  description = "Azure region."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group hosting the workspace."
  nullable    = false
}

###############################################################
# WORKSPACE
###############################################################
variable "sku" {
  type        = string
  default     = "PerGB2018"
  description = "Workspace SKU. PerGB2018 (default) or CapacityReservation for commitment tiers; legacy: PerNode/Premium/Standalone/Standard/Unlimited; LACluster only when linked to a dedicated cluster."
  nullable    = false

  validation {
    condition     = contains(["PerGB2018", "PerNode", "Premium", "Standalone", "Standard", "CapacityReservation", "LACluster", "Unlimited"], var.sku)
    error_message = "sku must be one of PerGB2018, PerNode, Premium, Standalone, Standard, CapacityReservation, LACluster, Unlimited."
  }
}

variable "retention_in_days" {
  type        = number
  default     = 30
  description = "Interactive retention in days (30-730). Note: a Sentinel-enabled workspace gets 90 days free."
  nullable    = false

  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be between 30 and 730."
  }
}

variable "daily_quota_gb" {
  type        = number
  default     = -1
  description = "Daily ingestion cap in GB. -1 = NO cap (Azure default). Microsoft warns a cap must not be a primary cost tool — once hit, ingestion stops."
  nullable    = false

  validation {
    condition     = var.daily_quota_gb == -1 || var.daily_quota_gb > 0
    error_message = "daily_quota_gb must be -1 (unlimited) or greater than 0."
  }
}

variable "reservation_capacity_in_gb_per_day" {
  type        = number
  default     = null
  description = "Commitment tier capacity in GB/day. Only valid when sku = CapacityReservation. Allowed: 100, 200, 300, 400, 500, 1000, 2000, 5000, 10000, 25000, 50000."
  nullable    = true

  validation {
    condition     = var.reservation_capacity_in_gb_per_day == null || contains([100, 200, 300, 400, 500, 1000, 2000, 5000, 10000, 25000, 50000], var.reservation_capacity_in_gb_per_day)
    error_message = "reservation_capacity_in_gb_per_day must be one of 100, 200, 300, 400, 500, 1000, 2000, 5000, 10000, 25000, 50000."
  }

  validation {
    condition     = var.reservation_capacity_in_gb_per_day == null || var.sku == "CapacityReservation"
    error_message = "reservation_capacity_in_gb_per_day can only be set when sku = \"CapacityReservation\"."
  }
}

###############################################################
# SECURE-BY-DEFAULT POSTURE
# Azure defaults these to true; the house default is the secure option
# (Entra-only auth, private access via AMPLS).
###############################################################
variable "local_authentication_enabled" {
  type        = bool
  default     = false
  description = "Allow workspace-key (local) auth in addition to Microsoft Entra. Default false = Entra ID only."
  nullable    = false
}

variable "internet_ingestion_enabled" {
  type        = bool
  default     = false
  description = "Allow ingestion over the public Internet. Default false = private only (reach it via AMPLS)."
  nullable    = false
}

variable "internet_query_enabled" {
  type        = bool
  default     = false
  description = "Allow querying over the public Internet. Default false = private only (reach it via AMPLS)."
  nullable    = false
}

variable "allow_resource_only_permissions" {
  type        = bool
  default     = true
  description = "Let users read data for resources they can see, without workspace-level permission (resource-context RBAC)."
  nullable    = false
}

###############################################################
# OPTIONAL
###############################################################
variable "cmk_for_query_forced" {
  type        = bool
  default     = null
  description = "Force customer-managed storage for query management. Requires a CMK-enabled dedicated cluster — see the Sentinel/CMK prerequisites."
  nullable    = true
}

variable "identity" {
  type = object({
    type         = string
    identity_ids = optional(list(string), [])
  })
  default     = null
  nullable    = true
  description = "Optional managed identity. type: SystemAssigned or UserAssigned (identity_ids required for UserAssigned)."

  validation {
    condition     = var.identity == null || contains(["SystemAssigned", "UserAssigned"], var.identity.type)
    error_message = "identity.type must be 'SystemAssigned' or 'UserAssigned'."
  }

  validation {
    condition     = var.identity == null || var.identity.type != "UserAssigned" || length(var.identity.identity_ids) > 0
    error_message = "identity.identity_ids is required (non-empty) when identity.type = 'UserAssigned'."
  }
}

variable "data_collection_rule_id" {
  type        = string
  default     = null
  description = "Optional default Data Collection Rule ID for this workspace."
  nullable    = true
}

variable "immediate_data_purge_on_30_days_enabled" {
  type        = bool
  default     = null
  description = "Remove data immediately after 30 days. Leave null unless a data-residency rule requires it."
  nullable    = true
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
  Optional Resource Lock on the workspace.

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
  description = "Tags to apply to the workspace."
}
