###############################################################
# MODULE: PolicySetDefinition - Variables
# Creates Azure Policy Set Definitions (initiatives — bundles of
# policy definitions targeting a common compliance goal).
# Each entry carries its own scope, so one deployment can
# cover both subscription-scoped and MG-scoped set definitions.
###############################################################

variable "set_definitions" {
  type = map(object({
    # Required
    display_name = string

    # Required — at least one member definition (enforced by validator below)
    policy_definition_references = list(object({
      policy_definition_id          = string
      reference_id                  = optional(string)
      parameter_values              = optional(any) # caller passes as object/map; module jsonencodes
      policy_definition_group_names = optional(list(string))
    }))

    # Optional groups for organizing members in the portal
    policy_definition_groups = optional(list(object({
      name                            = string
      display_name                    = optional(string)
      description                     = optional(string)
      category                        = optional(string)
      additional_metadata_resource_id = optional(string)
    })), [])

    # Scope — null = subscription-scoped, else full MG resource ID = MG-scoped
    management_group_id = optional(string)

    # Optional
    description = optional(string)
    metadata    = optional(map(string))
    parameters  = optional(any) # caller passes as object/map; module jsonencodes
    policy_type = optional(string, "Custom")
  }))
  nullable = false

  description = <<-EOT
  Map of policy set definitions (initiatives — bundles of policy definitions). Key = set definition name (Azure-side resource name; max 64 chars).

  Each set must have at least one entry in policy_definition_references.

  - display_name                 : (Required) Human-readable name visible in the portal (max 128 chars).
  - policy_definition_references : (Required) List of member definitions. Each entry:
      - policy_definition_id           : Full ARM ID of the member definition.
                                         Typically module.defs.definition_ids[<key>] when composing with PolicyDefinition.
      - reference_id                   : (Optional but RECOMMENDED) Client-side reference ID — used by
                                         PolicyExemption/PolicyRemediation to target a specific member of an assigned set.
                                         Must be unique within the set.
      - parameter_values               : (Optional) Per-member parameter overrides as Terraform object — module jsonencodes.
      - policy_definition_group_names  : (Optional) Groups this member belongs to (must match a group name in policy_definition_groups).
  - policy_definition_groups     : (Optional) Group definitions for organizing members in the portal.
      - name                           : (Required) Group name — must be unique within the set.
      - display_name                   : (Optional) Portal display name.
      - description                    : (Optional) Group description.
      - category                       : (Optional) Category label.
      - additional_metadata_resource_id: (Optional) ARM ID of a resource providing additional metadata.
  - description                  : (Optional) Description visible in the portal.
  - metadata                     : (Optional) Free-form key-value metadata — module jsonencodes.
  - parameters                   : (Optional) Set-level parameter definitions — module jsonencodes.
  - policy_type                  : (Optional, default "Custom") One of: Custom, BuiltIn, NotSpecified, Static.
  - management_group_id          : (Optional) When set, set definition is MG-scoped using
                                   azurerm_management_group_policy_set_definition. Omit for subscription scope.

  Schema note: azurerm_policy_set_definition.management_group_id is deprecated in azurerm 4.x.
  This module dispatches MG-scoped entries to azurerm_management_group_policy_set_definition instead.
  EOT

  validation {
    condition = alltrue([
      for s in var.set_definitions :
      contains(["Custom", "BuiltIn", "NotSpecified", "Static"], s.policy_type)
    ])
    error_message = "policy_type must be one of: Custom, BuiltIn, NotSpecified, Static."
  }

  validation {
    condition     = alltrue([for k in keys(var.set_definitions) : length(k) <= 64])
    error_message = "Policy set definition names (map keys) must not exceed 64 characters (Azure API limit)."
  }

  validation {
    condition = alltrue([
      for s in var.set_definitions :
      length(s.display_name) <= 128
    ])
    error_message = "display_name must not exceed 128 characters (Azure API limit)."
  }

  validation {
    condition = alltrue([
      for s in var.set_definitions :
      s.management_group_id == null || can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", s.management_group_id))
    ])
    error_message = "management_group_id must be a valid Azure Management Group resource ID (/providers/Microsoft.Management/managementGroups/<name>)."
  }

  validation {
    condition = alltrue([
      for s in var.set_definitions :
      length(s.policy_definition_references) >= 1
    ])
    error_message = "Each policy set definition must have at least one policy_definition_references entry."
  }

  validation {
    condition = alltrue([
      for s in var.set_definitions :
      length([for r in s.policy_definition_references : r.reference_id if r.reference_id != null]) ==
      length(distinct([for r in s.policy_definition_references : r.reference_id if r.reference_id != null]))
    ])
    error_message = "Within a single policy set, reference_id values must be unique."
  }

  validation {
    condition = alltrue([
      for s in var.set_definitions :
      length([for g in s.policy_definition_groups : g.name]) ==
      length(distinct([for g in s.policy_definition_groups : g.name]))
    ])
    error_message = "Within a single policy set, policy_definition_groups[].name values must be unique."
  }
}
