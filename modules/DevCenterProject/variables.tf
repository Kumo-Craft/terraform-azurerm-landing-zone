###############################################################
# MODULE: DevCenterProject - Variables
# Azure Dev Center Project (Microsoft.DevCenter/projects) — a
# team-scoped child of a Dev Center. Leaf companion to DevCenter.
#
# NAMING
# Convention: dcp-{subscription_acronym}-{environment}-{region_code}-{workload}
#
# XOR escape hatch:
#   var.name != null  → explicit name used verbatim
#   var.name == null  → all 4 convention components required
###############################################################

variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit Dev Center Project name (3-63 chars, start with a letter, letters/digits/hyphens). If null, computed as dcp-{acr}-{env}-{region}-{workload}."

  validation {
    condition     = var.name == null || (length(var.name) >= 3 && length(var.name) <= 63 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name)))
    error_message = "Project name must be 3-63 characters, start with a letter, end with a letter or digit, and contain only letters, digits, and hyphens."
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
  description = "Workload / team name for naming convention. Keep short — composed name must be <= 63 chars."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "dev_center_id" {
  type        = string
  description = "Resource ID of the parent Dev Center (e.g. module.dev_center.id). Changing this forces a new project."
  nullable    = false

  validation {
    # Validate case-insensitively (lower()) — the canonical Azure ID uses
    # `devCenters` (camelCase) while ARM also accepts lowercase. The raw,
    # canonical value is still passed to the resource, so no drift.
    condition     = can(regex("^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.devcenter/devcenters/[^/]+$", lower(var.dev_center_id)))
    error_message = "dev_center_id must be a valid Microsoft.DevCenter/devCenters resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the project will be deployed (typically the same region as the Dev Center)."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  nullable    = false
}

###############################################################
# PROJECT CONFIGURATION
###############################################################
variable "description" {
  type        = string
  description = "Optional description of the project. Changing this forces a new project."
  default     = null
}

variable "maximum_dev_boxes_per_user" {
  type        = number
  description = "Optional cap on the number of Dev Boxes a single user can create across all pools in the project. Null = no limit."
  default     = null

  validation {
    condition     = var.maximum_dev_boxes_per_user == null || var.maximum_dev_boxes_per_user >= 0
    error_message = "maximum_dev_boxes_per_user must be a non-negative number."
  }
}

variable "identity" {
  description = <<-EOT
  Managed identity for the project. Recommended: the project identity is what
  deploys environment types and reads project-level catalogs / Key Vault secrets.
  As a security best practice, use a project identity that is MORE restricted than
  the Dev Center identity.

  Default is SystemAssigned. If BOTH a system-assigned and a user-assigned identity
  are attached, the project uses ONLY the user-assigned identity.

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

###############################################################
# ENVIRONMENT TYPES (Azure Deployment Environments)
# Make an environment type deployable for this project. The map key
# MUST match the name of an environment type defined on the parent
# Dev Center (var.environment_types on the DevCenter module).
###############################################################
variable "environment_types" {
  description = <<-EOT
  Project environment types to enable, keyed by name. The key MUST match a
  Dev Center environment type name (created via the DevCenter module's
  `environment_types`). This is what makes an environment deployable.

  Per-entry fields:
  - `deployment_target_id`          - (Required) Subscription ID where this environment type's
                                       resources are deployed (e.g. /subscriptions/<sub>).
  - `creator_role_assignment_roles` - (Optional) Role definition IDs (GUIDs) granted to the
                                       environment CREATOR on the target subscription (e.g. the
                                       Owner role id "8e3af657-a8ff-443c-a75c-2fe8c4bcb635").
  - `user_role_assignments`         - (Optional) Map of user/principal object ID => list of role
                                       definition IDs, granting standing access on the target sub.
  - `identity`                      - (Optional) Deployment identity for this environment type
                                       (default SystemAssigned). This identity needs Contributor +
                                       User Access Administrator on `deployment_target_id`.
  - `tags`                          - (Optional) Per-environment-type tags.
  EOT
  type = map(object({
    deployment_target_id          = string
    creator_role_assignment_roles = optional(list(string), [])
    user_role_assignments         = optional(map(list(string)), {})
    identity = optional(object({
      type         = optional(string, "SystemAssigned")
      identity_ids = optional(list(string), [])
    }), {})
    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for e in values(var.environment_types) : can(regex("^/subscriptions/[^/]+$", e.deployment_target_id))])
    error_message = "Each environment_types[*].deployment_target_id must be a subscription ID of the form /subscriptions/<guid>."
  }

  validation {
    condition     = alltrue([for e in values(var.environment_types) : contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], e.identity.type)])
    error_message = "Each environment_types[*].identity.type must be 'SystemAssigned', 'UserAssigned' or 'SystemAssigned, UserAssigned'."
  }

  validation {
    condition     = alltrue([for e in values(var.environment_types) : !can(regex("UserAssigned", e.identity.type)) || length(e.identity.identity_ids) > 0])
    error_message = "environment_types[*].identity.identity_ids must be set when identity.type includes 'UserAssigned'."
  }
}

###############################################################
# RBAC & LOCK
###############################################################
variable "role_assignments" {
  description = <<-EOT
  A map of role assignments to create on this project. The map key is arbitrary.
  Typical project-scoped roles: "DevCenter Project Admin", "DevCenter Dev Box User",
  "Deployment Environments User".

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
  Optional management lock on the project.

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
  description = "Tags to apply to the project"
  default     = {}
  nullable    = false
}
