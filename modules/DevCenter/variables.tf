###############################################################
# MODULE: DevCenter - Variables
# Azure Dev Center (Microsoft.DevCenter/devcenters) — the top-level
# resource for Microsoft Dev Box and Azure Deployment Environments.
#
# NAMING
# Convention: dc-{subscription_acronym}-{environment}-{region_code}-{workload}
# The in-repo Naming submodule has no dev_center type, so the name is
# composed here directly (same approach as KeyVaultStack's PE name).
#
# XOR escape hatch:
#   var.name != null  → explicit name used verbatim
#   var.name == null  → all 4 convention components required
###############################################################

variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit Dev Center name (3-26 chars, start with a letter, letters/digits/hyphens). If null, computed as dc-{acr}-{env}-{region}-{workload}."

  validation {
    condition     = var.name == null || (length(var.name) >= 3 && length(var.name) <= 26 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name)))
    error_message = "Dev Center name must be 3-26 characters, start with a letter, end with a letter or digit, and contain only letters, digits, and hyphens."
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
  description = "Workload name for naming convention. Keep short — the composed name must be <= 26 chars."

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
  description = "Azure region where the Dev Center will be deployed"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  nullable    = false
}

###############################################################
# DEV CENTER CONFIGURATION
###############################################################
variable "identity" {
  description = <<-EOT
  Managed identity for the Dev Center. Microsoft strongly recommends attaching an
  identity: it is required to attach catalogs (GitHub/Azure Repos), to read Key Vault
  secrets (e.g. catalog PATs), and to create environment types in deployment
  subscriptions (the identity needs Contributor + User Access Administrator there).

  Default is SystemAssigned. Note: if BOTH a system-assigned and a user-assigned
  identity are attached, the Dev Center uses ONLY the user-assigned identity.

  - `type`         - (Required) 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'.
  - `identity_ids` - (Optional) User Assigned Managed Identity IDs. Required when type includes 'UserAssigned'.
  EOT
  type = object({
    type         = string
    identity_ids = optional(list(string), [])
  })
  default = {
    type = "SystemAssigned"
  }
  nullable = false

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity.type)
    error_message = "identity.type must be 'SystemAssigned', 'UserAssigned' or 'SystemAssigned, UserAssigned'."
  }

  validation {
    condition     = !can(regex("UserAssigned", var.identity.type)) || length(var.identity.identity_ids) > 0
    error_message = "identity.identity_ids must be set when identity.type includes 'UserAssigned'."
  }
}

variable "project_catalog_item_sync_enabled" {
  type        = bool
  description = "Whether project catalogs associated with projects in this Dev Center may sync catalog items. Azure default is false; enable when project-level catalogs are used."
  default     = false
}

variable "environment_types" {
  type        = list(string)
  description = <<-EOT
  Names of the environment types to create on this Dev Center (e.g.
  ["sandbox", "dev", "test", "prod"]). These are a PREREQUISITE for project
  environment types — a `DevCenterProject` can only enable an environment type
  whose name matches one defined here. The portal also requires at least one
  Dev Center environment type before a project can surface environments.
  EOT
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for n in var.environment_types : can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$", n))])
    error_message = "Each environment type name must be 1-63 chars: letters, digits, and . _ - (start alphanumeric)."
  }

  validation {
    condition     = length(distinct(var.environment_types)) == length(var.environment_types)
    error_message = "environment_types must not contain duplicate names."
  }
}

###############################################################
# RBAC & LOCK
###############################################################
variable "role_assignments" {
  description = <<-EOT
  A map of role assignments to create on this Dev Center. The map key is arbitrary.

  - `role_definition_id_or_name`             - (Required) The ID or name of the role definition.
  - `principal_id`                           - (Required) The ID of the principal.
  - `principal_type`                         - (Optional) User, Group or ServicePrincipal.
  - `condition`                              - (Optional) ABAC condition.
  - `condition_version`                      - (Optional) Condition version ("1.0" or "2.0").
  - `description`                            - (Optional) Description.
  - `skip_service_principal_aad_check`       - (Optional) Skip AAD check.
  - `delegated_managed_identity_resource_id` - (Optional) Cross-tenant delegated MI.
  EOT
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    principal_type                         = optional(string)
    condition                              = optional(string)
    condition_version                      = optional(string)
    description                            = optional(string)
    skip_service_principal_aad_check       = optional(bool, false)
    delegated_managed_identity_resource_id = optional(string)
  }))
  default  = {}
  nullable = false
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Optional management lock on the Dev Center.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Generated from kind if not specified.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags to apply to the Dev Center"
  default     = {}
  nullable    = false
}
