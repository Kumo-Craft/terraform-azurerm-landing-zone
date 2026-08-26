###############################################################
# MODULE: RbacAssignments - Variables
# Two assignment types:
#   group_assignments    → resolves Entra ID group by display_name
#   identity_assignments → uses principal_id directly (MI, SP)
###############################################################

variable "group_assignments" {
  description = <<-EOT
  A map of role assignments for Entra ID groups (resolved by display_name).
  The map key is deliberately arbitrary to avoid plan-time issues.

  - `group_name`                 - (Required) Entra ID group display name.
  - `scope`                      - (Required) Azure resource ID to assign the role on.
  - `role_definition_id_or_name` - (Required) Role definition ID or name.
  - `condition`                  - (Optional) ABAC condition.
  - `condition_version`          - (Optional) Condition version ("1.0" or "2.0").
  - `description`                - (Optional) Assignment description.
  EOT
  type = map(object({
    group_name                 = string
    scope                      = string
    role_definition_id_or_name = string
    condition                  = optional(string)
    condition_version          = optional(string)
    description                = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for a in var.group_assignments :
      can(regex("^(/subscriptions/|/providers/Microsoft\\.Management/managementGroups/)", a.scope))
    ])
    error_message = "Each scope must start with /subscriptions/<id> or /providers/Microsoft.Management/managementGroups/<id>."
  }

  validation {
    condition = alltrue([
      for a in var.group_assignments :
      (a.condition == null) == (a.condition_version == null)
    ])
    error_message = "condition and condition_version must both be set or both be null."
  }

  validation {
    condition = alltrue([
      for a in var.group_assignments :
      a.condition_version == null || contains(["1.0", "2.0"], a.condition_version)
    ])
    error_message = "condition_version must be \"1.0\" or \"2.0\"."
  }
}

variable "identity_assignments" {
  description = <<-EOT
  A map of role assignments for any Entra principal (MI, SP, Group, User) — addressed by object ID.
  The map key is deliberately arbitrary to avoid plan-time issues.

  - `principal_id`                     - (Required) Object ID of the principal.
  - `scope`                            - (Required) Azure resource ID to assign the role on.
  - `role_definition_id_or_name`       - (Required) Role definition ID or name.
  - `principal_type`                   - (Optional) "User" | "Group" | "ServicePrincipal". Required when
                                         assigning to a group (Azure rejects with UnmatchedPrincipalType).
                                         Accepted values: User, Group, ServicePrincipal.
                                         ForeignGroup and Device appear in Azure REST API + portal docs but are NOT
                                         accepted by the azurerm provider as of v4.x — intentionally excluded from
                                         this enum. Re-verify when next pinning provider (4.76+).
  - `condition`                        - (Optional) ABAC condition.
  - `condition_version`                - (Optional) Condition version ("1.0" or "2.0").
  - `description`                      - (Optional) Assignment description.
  - `skip_service_principal_aad_check` - (Optional) Skip AAD check. Defaults to false.
  - `delegated_managed_identity_resource_id` - (Optional) Resource ID of a delegated managed identity for cross-tenant role assignments.
  EOT
  type = map(object({
    principal_id                           = string
    scope                                  = string
    role_definition_id_or_name             = string
    principal_type                         = optional(string)
    condition                              = optional(string)
    condition_version                      = optional(string)
    description                            = optional(string)
    skip_service_principal_aad_check       = optional(bool, false)
    delegated_managed_identity_resource_id = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for a in var.identity_assignments :
      can(regex("^(/subscriptions/|/providers/Microsoft\\.Management/managementGroups/)", a.scope))
    ])
    error_message = "Each scope must start with /subscriptions/<id> or /providers/Microsoft.Management/managementGroups/<id>."
  }

  validation {
    condition = alltrue([
      for a in var.identity_assignments :
      a.principal_type == null || contains(["User", "Group", "ServicePrincipal"], a.principal_type)
    ])
    error_message = "principal_type must be one of: User, Group, ServicePrincipal."
  }

  validation {
    condition = alltrue([
      for a in var.identity_assignments :
      (a.condition == null) == (a.condition_version == null)
    ])
    error_message = "condition and condition_version must both be set or both be null."
  }

  validation {
    condition = alltrue([
      for a in var.identity_assignments :
      a.condition_version == null || contains(["1.0", "2.0"], a.condition_version)
    ])
    error_message = "condition_version must be \"1.0\" or \"2.0\"."
  }
}
