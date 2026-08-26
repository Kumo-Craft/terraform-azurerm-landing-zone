###############################################################
# MODULE: ResourceGroup - Variables
# Description: Map-shape — declare N RGs in one apply, each with
#              its own optional lock + role_assignments + tags.
###############################################################

###############################################################
# NAMING CONVENTION (shared across all RGs in the set)
###############################################################
variable "subscription_acronym" {
  type        = string
  description = "Subscription acronym for naming convention (e.g. mgm, con, idn, sec, shc). Applied to every RG in the set."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  description = "Environment for naming convention (e.g. prod, nprd). Automatically injected by root.hcl."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  description = "Region code for naming convention (e.g. gwc, weu). Automatically injected by root.hcl."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where all resource groups will be deployed."
  nullable    = false
}

variable "resource_groups" {
  description = <<-EOT
  Map of Resource Groups to create. Map key is an arbitrary identifier used for
  output lookup (e.g. dependency.rg.outputs.resource_groups["network"]).

  Per-entry fields:
  - `workload`         - (Required) Workload name. Final RG name = rg-{acr}-{env}-{region}-{workload}
  - `name`             - (Optional) Explicit RG name override. If null, computed from naming.
  - `location`         - (Optional) Override the set-level location for this specific RG. Useful when most
                         RGs sit in one region but a few must be elsewhere (e.g. AVD control plane forced
                         to westeurope while session hosts and storage stay in germanywestcentral).
  - `region_code`      - (Optional) Override the set-level region_code in the computed name. Should be
                         set together with `location` to keep the name aligned with the actual region
                         (e.g. location="westeurope" + region_code="weu").
  - `tags`             - (Optional) Per-RG tags. Merged on top of the set-level `tags`.
  - `lock`             - (Optional) Management lock. { kind = "CanNotDelete"|"ReadOnly", name = optional(string), notes = optional(string) }
  - `role_assignments` - (Optional) Map of role assignments scoped to this RG.
  EOT

  type = map(object({
    workload    = string
    name        = optional(string)
    location    = optional(string)
    region_code = optional(string)
    tags        = optional(map(string), {})
    lock = optional(object({
      kind  = string
      name  = optional(string)
      notes = optional(string) # ForceNew in provider — changing destroys+recreates the lock.
    }))
    role_assignments = optional(map(object({
      role_definition_id_or_name             = string
      principal_id                           = string
      principal_type                         = optional(string)
      condition                              = optional(string)
      condition_version                      = optional(string)
      description                            = optional(string)
      skip_service_principal_aad_check       = optional(bool, false)
      delegated_managed_identity_resource_id = optional(string)
    })), {})
  }))

  nullable = false

  validation {
    condition = alltrue([
      for k, rg in var.resource_groups :
      can(regex("^[a-z][a-z0-9_-]{1,30}$", rg.workload))
    ])
    error_message = "Each resource_groups[*].workload must be 2 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }

  validation {
    condition = alltrue([
      for k, rg in var.resource_groups :
      rg.name == null || can(regex("^[a-zA-Z0-9_().-]{1,89}[a-zA-Z0-9_()-]$|^[a-zA-Z0-9_()-]$", rg.name))
    ])
    error_message = "Each resource_groups[*].name override must match Azure RG naming rules (1-90 chars, alphanumerics/underscores/parentheses/hyphens/periods, not ending in period)."
  }

  validation {
    condition = alltrue([
      for k, rg in var.resource_groups :
      rg.region_code == null || can(regex("^[a-z]{2,5}$", rg.region_code))
    ])
    error_message = "Each resource_groups[*].region_code override must be 2 to 5 lowercase letters (matching the set-level region_code format)."
  }

  validation {
    condition = alltrue([
      for k, rg in var.resource_groups :
      rg.lock == null || contains(["CanNotDelete", "ReadOnly"], try(rg.lock.kind, ""))
    ])
    error_message = "Each resource_groups[*].lock.kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }

  validation {
    condition = alltrue(flatten([
      for k, rg in var.resource_groups : [
        for ra_key, ra in rg.role_assignments :
        can(regex("^(/subscriptions/[0-9a-fA-F-]+)?/providers/Microsoft\\.Authorization/roleDefinitions/[0-9a-fA-F-]+$", ra.role_definition_id_or_name))
        ||
        can(regex("^[[:alpha:]]+", ra.role_definition_id_or_name))
      ]
    ]))
    error_message = "Each role_assignment.role_definition_id_or_name must be a built-in role name or a roleDefinitions/<guid> resource id."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags applied to every RG in the set. Per-RG tags override these on conflict. Merged with auto-generated CreatedOn tag."
  default     = {}
  nullable    = false
}
