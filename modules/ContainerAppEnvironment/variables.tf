###############################################################
# MODULE: ContainerAppEnvironment - Variables
# Azure Container Apps Environment (Microsoft.App/managedEnvironments)
# — the shared boundary that hosts Container Apps. Prerequisite for
# the Container App module.
#
# NAMING
# Convention: cae-{subscription_acronym}-{environment}-{region_code}-{workload}
#
# XOR escape hatch:
#   var.name != null  → explicit name used verbatim
#   var.name == null  → all 4 convention components required
###############################################################

variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit Container App Environment name (2-32 chars, start with a letter, lowercase letters/digits/hyphens). If null, computed as cae-{acr}-{env}-{region}-{workload}."

  validation {
    condition     = var.name == null || (length(var.name) >= 2 && length(var.name) <= 32 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.name)))
    error_message = "Name must be 2-32 chars, start with a lowercase letter, end alphanumeric, lowercase letters/digits/hyphens only."
  }

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym for naming convention (e.g. mgm, api)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment for naming convention (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code for naming convention (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name for naming convention. Keep short — composed name must be <= 32 chars."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9-]{0,15}$", var.workload))
    error_message = "workload must be 1 to 16 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the Container App Environment will be deployed"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  nullable    = false
}

###############################################################
# LOGGING
###############################################################
variable "logs_destination" {
  type        = string
  description = "Where application logs go: 'log-analytics' (requires log_analytics_workspace_id), 'azure-monitor' (diagnostic settings), or null (streamed only)."
  default     = "log-analytics"

  validation {
    condition     = var.logs_destination == null || contains(["log-analytics", "azure-monitor"], var.logs_destination)
    error_message = "logs_destination must be 'log-analytics', 'azure-monitor', or null."
  }
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Log Analytics Workspace ID to link. Required when logs_destination = 'log-analytics'; must be null when logs_destination = 'azure-monitor'."
  default     = null

  validation {
    condition     = var.log_analytics_workspace_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a valid Log Analytics Workspace resource ID."
  }

  validation {
    condition     = !(var.logs_destination == "log-analytics") || var.log_analytics_workspace_id != null
    error_message = "log_analytics_workspace_id is required when logs_destination = 'log-analytics'."
  }

  validation {
    condition     = !(var.logs_destination == "azure-monitor") || var.log_analytics_workspace_id == null
    error_message = "log_analytics_workspace_id must be null when logs_destination = 'azure-monitor'."
  }
}

###############################################################
# NETWORKING (VNet integration)
###############################################################
variable "infrastructure_subnet_id" {
  type        = string
  description = <<-EOT
  Optional. Existing subnet for the Container Apps control plane (VNet integration).
  Minimum /23 for Consumption-only, /27 for Workload-profile environments. The subnet
  must be delegated to Microsoft.App/environments. Required for internal LB / zone redundancy.
  EOT
  default     = null

  validation {
    condition     = var.infrastructure_subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.infrastructure_subnet_id))
    error_message = "infrastructure_subnet_id must be a valid subnet resource ID."
  }
}

variable "internal_load_balancer_enabled" {
  type        = bool
  description = "Run the environment in internal-only mode (no public ingress). Requires infrastructure_subnet_id."
  default     = false
  nullable    = false

  validation {
    condition     = !var.internal_load_balancer_enabled || var.infrastructure_subnet_id != null
    error_message = "internal_load_balancer_enabled = true requires infrastructure_subnet_id to be set."
  }
}

variable "zone_redundancy_enabled" {
  type        = bool
  description = "Spread the environment across availability zones. Requires infrastructure_subnet_id. Recommended true for production."
  default     = false
  nullable    = false

  validation {
    condition     = !var.zone_redundancy_enabled || var.infrastructure_subnet_id != null
    error_message = "zone_redundancy_enabled = true requires infrastructure_subnet_id to be set."
  }
}

variable "infrastructure_resource_group_name" {
  type        = string
  description = "Optional. Name of the platform-managed infrastructure resource group. Only valid when a workload_profile is specified."
  default     = null
}

variable "public_network_access" {
  type        = string
  description = "Public network access for the environment. 'Enabled' or 'Disabled' (null = Azure default). Set 'Disabled' with internal LB + private endpoints for a private environment."
  default     = null

  validation {
    condition     = var.public_network_access == null || contains(["Enabled", "Disabled"], var.public_network_access)
    error_message = "public_network_access must be 'Enabled' or 'Disabled'."
  }
}

###############################################################
# WORKLOAD PROFILES
###############################################################
variable "workload_profiles" {
  description = <<-EOT
  Workload profiles for the environment. Empty = a Consumption-only environment.

  - `name`                  - (Required) Profile name. A `Consumption` profile must be named "Consumption".
  - `workload_profile_type` - (Required) e.g. "Consumption", "D4", "D8", "E4", "NC24-A100"…
  - `minimum_count` / `maximum_count` - (Optional) Instance bounds for dedicated profiles.

  Note: an environment created without profiles can NEVER add them later (and vice-versa) —
  switching forces a full recreate.
  EOT
  type = list(object({
    name                  = string
    workload_profile_type = string
    minimum_count         = optional(number)
    maximum_count         = optional(number)
  }))
  default  = []
  nullable = false
}

###############################################################
# IDENTITY & DAPR
###############################################################
variable "identity" {
  description = <<-EOT
  Optional managed identity for the environment (e.g. to pull images from ACR or read
  Key Vault-backed certificates at the environment scope).

  - `type`         - (Required) 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'.
  - `identity_ids` - (Optional) UAMI IDs. Required when type includes 'UserAssigned'.
  EOT
  type = object({
    type         = string
    identity_ids = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.identity == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], try(var.identity.type, ""))
    error_message = "identity.type must be 'SystemAssigned', 'UserAssigned' or 'SystemAssigned, UserAssigned'."
  }

  validation {
    condition     = var.identity == null || !can(regex("UserAssigned", var.identity.type)) || length(var.identity.identity_ids) > 0
    error_message = "identity.identity_ids must be set when identity.type includes 'UserAssigned'."
  }
}

variable "dapr_application_insights_connection_string" {
  type        = string
  description = "Optional Application Insights connection string for Dapr service-to-service telemetry."
  default     = null
  sensitive   = true
}

variable "mutual_tls_enabled" {
  type        = bool
  description = "Enable mutual TLS (mTLS) between apps. Public preview — may add latency."
  default     = false
  nullable    = false
}

###############################################################
# LOCK & TAGS
###############################################################
variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = "Optional management lock (CanNotDelete or ReadOnly)."

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the Container App Environment"
  default     = {}
  nullable    = false
}
