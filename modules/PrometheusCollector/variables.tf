###############################################################
# MODULE: PrometheusCollector - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################

# F-2: var.name override (escape hatch) + XOR validator.
variable "name" {
  description = "Explicit DCR name override (escape hatch). If null, derived from naming convention via ../Naming."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null)
    error_message = "Either var.name must be set OR all 3 naming components (subscription_acronym, environment, region_code) must be non-null. workload has a default."
  }
}

# F-7: default = null + null-tolerant validators.
variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. api, mgm)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters (or null when var.name is set)."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters (or null when var.name is set)."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters (or null when var.name is set)."
  }
}

variable "workload" {
  type        = string
  default     = "prometheus"
  nullable    = false
  description = "Workload suffix (e.g. prometheus)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
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

variable "resource_group_name" {
  type        = string
  description = "Resource group for the Data Collection Rule"
  nullable    = false
}

variable "aks_cluster_id" {
  type        = string
  description = "ID of the AKS cluster to collect Prometheus metrics from"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ContainerService/managedClusters/[^/]+$", var.aks_cluster_id))
    error_message = "aks_cluster_id must be a valid Azure AKS cluster resource ID."
  }
}

variable "aks_cluster_name" {
  type        = string
  description = "Name of the AKS cluster (used in recording rule group names)"
  nullable    = false
}

variable "monitor_workspace_id" {
  type        = string
  description = "ID of the Azure Monitor Workspace (Prometheus destination)"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Monitor/accounts/[^/]+$", var.monitor_workspace_id))
    error_message = "monitor_workspace_id must be a valid Azure Monitor Workspace resource ID."
  }
}

variable "data_collection_endpoint_id" {
  type        = string
  description = "ID of the Data Collection Endpoint (from AMW default_data_collection_endpoint_id)"
  nullable    = false
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "enable_recording_rules" {
  type        = bool
  default     = true
  description = "Enable recommended Prometheus recording rules for Kubernetes"
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}

###############################################################
# RESOURCE LOCK
###############################################################

# F-3: ResourceLock composition variable.
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the DCR. Set to null to skip."
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
