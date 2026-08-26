###############################################################
# MODULE: AzureMonitorWorkspace - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name. If null, computed from naming components."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (legacy resource), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. mgm, con)"

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
  default     = "01"
  nullable    = false
  description = "Workload suffix (e.g. 01)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{0,30}$", var.workload))
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
  description = "Resource group name"
  nullable    = false
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = "Whether public network access is enabled"
}

variable "subnet_id" {
  type        = string
  default     = null
  description = "Subnet ID for the Private Endpoint. If null, no PE is created."

  validation {
    condition     = var.subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a valid Azure Subnet resource ID."
  }
}

variable "private_dns_zone_ids" {
  type        = list(string)
  default     = []
  nullable    = false
  description = "Optional. IDs de zones DNS privées à lier au Private Endpoint via un private_dns_zone_group. Pour Managed Prometheus la zone est régionale : privatelink.<region>.prometheus.monitor.azure.com. Liste vide (défaut) = le zone group est laissé à la policy DINE ALZ (private_dns_zone_group reste ignoré via lifecycle)."

  validation {
    condition     = alltrue([for z in var.private_dns_zone_ids : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", z))])
    error_message = "Chaque private_dns_zone_ids[*] doit être un resource ID de zone DNS privée valide."
  }
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
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the Azure Monitor Workspace. AMW is critical observability infrastructure — CanNotDelete recommended for prod. Set to null to skip."
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

###############################################################
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the AMW scope. Common AMW roles: 'Monitoring Reader' (Grafana managed identity), 'Monitoring Metrics Publisher' (AKS node pool MI), 'Azure Monitor Workspace Contributor' (Prometheus config). Default principal_type='ServicePrincipal'."
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string, "ServicePrincipal")
    condition                        = optional(string, null)
    condition_version                = optional(string, null)
    description                      = optional(string, null)
    skip_service_principal_aad_check = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)])
    error_message = "Each role_assignments[*].principal_type must be one of User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}
