###############################################################
# MODULE: RoleDefinition - Main
# Custom (least-privilege) Azure role definition + optional
# assignments. Assignments are delegated to the in-repo
# RoleAssignment module (DRY — same pattern as ResourceGroup
# delegating its lock to ResourceLock).
###############################################################

locals {
  # `scope` is auto-added to assignable_scopes by the provider when the list is
  # empty; we compute it explicitly so the preconditions below can inspect it.
  effective_assignable_scopes = length(var.assignable_scopes) > 0 ? var.assignable_scopes : [var.scope]

  has_data_actions = length(var.data_actions) > 0 || length(var.not_data_actions) > 0

  # Management-group entries among the effective assignable scopes.
  mg_assignable_scopes = [
    for s in local.effective_assignable_scopes : s
    if strcontains(lower(s), "/providers/microsoft.management/managementgroups/")
  ]
}

resource "azurerm_role_definition" "this" {
  name  = var.name
  scope = var.scope
  # The provider rejects an empty-string description; omit it (null) when unset.
  description = var.description != "" ? var.description : null

  permissions {
    actions          = var.actions
    not_actions      = var.not_actions
    data_actions     = var.data_actions
    not_data_actions = var.not_data_actions
  }

  assignable_scopes = local.effective_assignable_scopes

  lifecycle {
    # A role that grants nothing is invalid; not_actions/not_data_actions only
    # SUBTRACT from a wildcard, they never grant.
    precondition {
      condition     = length(var.actions) + length(var.data_actions) > 0
      error_message = "A custom role must grant at least one action or data_action."
    }

    # Azure forbids data-plane custom roles at management-group scope.
    precondition {
      condition     = !local.has_data_actions || length(local.mg_assignable_scopes) == 0
      error_message = "A custom role with data_actions/not_data_actions cannot be assignable at a management-group scope — use subscription/resource-group assignable_scopes."
    }

    # Azure allows at most one management group in assignable_scopes.
    precondition {
      condition     = length(local.mg_assignable_scopes) <= 1
      error_message = "assignable_scopes may contain at most ONE management group."
    }
  }
}

# Optional one-shot assignments, delegated to the RoleAssignment wrapper.
module "assignment" {
  source   = "../RoleAssignment"
  for_each = { for a in var.assignments : "${a.principal_id}|${a.scope}" => a }

  scope              = each.value.scope
  role_definition_id = azurerm_role_definition.this.role_definition_resource_id
  principal_id       = each.value.principal_id
  principal_type     = each.value.principal_type

  # Skip the AAD existence pre-check for ServicePrincipals to avoid a race on
  # freshly-created SPNs (RoleAssignment defaults this to false otherwise).
  skip_service_principal_aad_check = each.value.principal_type == "ServicePrincipal"
}
