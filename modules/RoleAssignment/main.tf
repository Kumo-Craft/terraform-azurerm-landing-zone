###############################################################
# MODULE: RoleAssignment - Main
# Thin wrapper around azurerm_role_assignment for single grants.
###############################################################

locals {
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"

  # Dispatch `role_definition_id_or_name` (a unified caller input) to the
  # provider's `role_definition_id` vs `role_definition_name` based on whether
  # the value looks like a full resource path. Used by wrapper modules that
  # expose a single field per role-assignment entry.
  ron_is_resource_id = var.role_definition_id_or_name != null && strcontains(lower(var.role_definition_id_or_name), lower(local.role_definition_resource_substring))

  effective_role_definition_name = (
    var.role_definition_name != null ? var.role_definition_name :
    var.role_definition_id_or_name != null && !local.ron_is_resource_id ? var.role_definition_id_or_name :
    null
  )

  effective_role_definition_id = (
    var.role_definition_id != null ? (
      can(regex("^/", var.role_definition_id)) ? var.role_definition_id :
      "${local.role_definition_resource_substring}/${var.role_definition_id}"
    ) :
    var.role_definition_id_or_name != null && local.ron_is_resource_id ? var.role_definition_id_or_name :
    null
  )
}

resource "azurerm_role_assignment" "this" {
  scope = var.scope

  role_definition_name = local.effective_role_definition_name
  role_definition_id   = local.effective_role_definition_id

  principal_id                     = var.principal_id
  principal_type                   = var.principal_type
  description                      = var.description
  skip_service_principal_aad_check = var.skip_service_principal_aad_check

  condition         = var.condition
  condition_version = var.condition_version

  delegated_managed_identity_resource_id = var.delegated_managed_identity_resource_id

  lifecycle {
    precondition {
      condition = (
        (var.role_definition_name != null ? 1 : 0) +
        (var.role_definition_id != null ? 1 : 0) +
        (var.role_definition_id_or_name != null ? 1 : 0)
      ) == 1
      error_message = "Exactly one of role_definition_name, role_definition_id, or role_definition_id_or_name must be set."
    }

    precondition {
      condition     = (var.condition == null) == (var.condition_version == null)
      error_message = "condition and condition_version must both be set or both be null."
    }
  }
}
