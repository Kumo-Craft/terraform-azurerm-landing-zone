###############################################################
# MODULE: PolicyAssignment - Main
# Creates one policy assignment per entry in var.assignments,
# dispatched to the correct azurerm resource based on the scope
# (RG / Subscription / Management Group).
###############################################################

locals {
  rg_assignments  = { for k, v in var.assignments : k => v if v.resource_group_id != null }
  sub_assignments = { for k, v in var.assignments : k => v if v.subscription_id != null }
  mg_assignments  = { for k, v in var.assignments : k => v if v.management_group_id != null }

  # Wrap caller-friendly parameters { effect = "audit" } into Azure Policy
  # expected format { effect = { value = "audit" } }.
  wrap_parameters = {
    for k, v in var.assignments : k => (
      v.parameters == null ? null : jsonencode({
        for pk, pv in v.parameters : pk => { value = pv }
      })
    )
  }
}

###############################################################
# RG-scoped assignments
###############################################################
resource "azurerm_resource_group_policy_assignment" "this" {
  for_each = local.rg_assignments

  name                 = each.key
  resource_group_id    = each.value.resource_group_id
  policy_definition_id = each.value.policy_definition_id
  display_name         = each.value.display_name
  description          = each.value.description
  enforce              = each.value.enforce
  parameters           = local.wrap_parameters[each.key]
  location             = each.value.location
  not_scopes           = length(each.value.not_scopes) > 0 ? each.value.not_scopes : null
  metadata             = each.value.metadata

  dynamic "identity" {
    for_each = each.value.identity_type != null ? [1] : []
    content {
      type         = each.value.identity_type
      identity_ids = (each.value.identity_type == "UserAssigned") ? coalesce(each.value.identity_ids, var.default_identity_ids) : null
    }
  }

  dynamic "non_compliance_message" {
    for_each = each.value.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = each.value.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = each.value.resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

###############################################################
# Subscription-scoped assignments
###############################################################
resource "azurerm_subscription_policy_assignment" "this" {
  for_each = local.sub_assignments

  name                 = each.key
  subscription_id      = each.value.subscription_id
  policy_definition_id = each.value.policy_definition_id
  display_name         = each.value.display_name
  description          = each.value.description
  enforce              = each.value.enforce
  parameters           = local.wrap_parameters[each.key]
  location             = each.value.location
  not_scopes           = length(each.value.not_scopes) > 0 ? each.value.not_scopes : null
  metadata             = each.value.metadata

  dynamic "identity" {
    for_each = each.value.identity_type != null ? [1] : []
    content {
      type         = each.value.identity_type
      identity_ids = (each.value.identity_type == "UserAssigned") ? coalesce(each.value.identity_ids, var.default_identity_ids) : null
    }
  }

  dynamic "non_compliance_message" {
    for_each = each.value.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = each.value.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = each.value.resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

###############################################################
# Management Group-scoped assignments
###############################################################
resource "azurerm_management_group_policy_assignment" "this" {
  for_each = local.mg_assignments

  name                 = each.key
  management_group_id  = each.value.management_group_id
  policy_definition_id = each.value.policy_definition_id
  display_name         = each.value.display_name
  description          = each.value.description
  enforce              = each.value.enforce
  parameters           = local.wrap_parameters[each.key]
  location             = each.value.location
  not_scopes           = length(each.value.not_scopes) > 0 ? each.value.not_scopes : null
  metadata             = each.value.metadata

  dynamic "identity" {
    for_each = each.value.identity_type != null ? [1] : []
    content {
      type         = each.value.identity_type
      identity_ids = (each.value.identity_type == "UserAssigned") ? coalesce(each.value.identity_ids, var.default_identity_ids) : null
    }
  }

  dynamic "non_compliance_message" {
    for_each = each.value.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = each.value.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = each.value.resource_selectors
    content {
      name = resource_selectors.value.name
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

###############################################################
# Cat 5 #12 (v0.2.89, opt-in NON-BREAKING) — auto-derive
# role_definition_ids from the policy definition's built-in
# role list.
#
# The azurerm provider exposes `role_definition_ids` as a typed
# list(string) attribute on `data.azurerm_policy_definition` —
# it pre-parses the policy's metadata.roleDefinitionIds key so
# no jsondecode is needed.
#
# This data source is only called for assignments that BOTH:
#   a) opt in via auto_derive_roles_from_definition = true, AND
#   b) use identity_type = "SystemAssigned"
# All other assignments are unaffected (NON-BREAKING).
###############################################################
data "azurerm_policy_definition" "derived" {
  for_each = {
    for k, v in var.assignments : k => v
    if v.auto_derive_roles_from_definition && v.identity_type == "SystemAssigned"
  }

  # Built-in policy IDs have the form:
  # /providers/Microsoft.Authorization/policyDefinitions/<name-or-guid>
  # The last path segment is the value the `name` attribute accepts.
  name = element(
    split("/", each.value.policy_definition_id),
    length(split("/", each.value.policy_definition_id)) - 1
  )
}

###############################################################
# Role assignments for the policy assignments' identities
# ─────────────────────────────────────────────────────────────
# Flatten the per-assignment role_assignments list into a single
# map with stable composite keys (assignment_name + index). Each
# entry grants the corresponding policy assignment's identity the
# specified role at the specified scope.
#
# Required when DINE/Modify policies need to write resources outside
# their own scope (e.g. cross-sub storage, central monitoring LAW).
# Built-in policies declare what roles their identity needs in
# `roleDefinitionIds` — callers must surface them here.
#
# `time_sleep.role_assignment_propagation` gives Entra ID 60 s to
# propagate the new role assignments before the policy engine's
# first evaluation. Without it, the initial deploy can race the
# RBAC propagation and fail with 403 Forbidden.
###############################################################
locals {
  role_assignments_flat = flatten([
    for k, v in var.assignments : concat(
      # 1. Explicit role_assignments[] entries — existing behavior, unchanged.
      [
        for idx, ra in v.role_assignments : {
          key            = "${k}-${idx}"
          assignment_key = k
          scope          = ra.scope
          role_name      = ra.role_definition_name
          role_id        = ra.role_definition_id
        }
      ],
      # 2. Auto-derived role IDs from policy definition metadata
      #    (Cat 5 #12 — only when opted in).
      #    Scope = the assignment's own scope (RG / Sub / MG).
      [
        for idx, rid in try(data.azurerm_policy_definition.derived[k].role_definition_ids, []) : {
          key            = "${k}-derived-${idx}"
          assignment_key = k
          scope = coalesce(
            v.resource_group_id,
            v.subscription_id,
            v.management_group_id,
          )
          role_name = null
          role_id   = rid
        }
      ]
    )
  ])

  role_assignments_map = { for entry in local.role_assignments_flat : entry.key => entry }
}

module "policy_identity" {
  source   = "../RoleAssignment"
  for_each = local.role_assignments_map

  scope = each.value.scope

  # RoleAssignment exposes both `role_definition_name` (a built-in role
  # display name) and `role_definition_id` (a GUID or full path; the
  # canonical module normalises bare GUIDs to the full path internally).
  role_definition_name = each.value.role_name
  role_definition_id   = each.value.role_id

  principal_id = one(compact([
    try(azurerm_subscription_policy_assignment.this[each.value.assignment_key].identity[0].principal_id, null),
    try(azurerm_resource_group_policy_assignment.this[each.value.assignment_key].identity[0].principal_id, null),
    try(azurerm_management_group_policy_assignment.this[each.value.assignment_key].identity[0].principal_id, null),
  ]))

  principal_type = "ServicePrincipal"
}

moved {
  from = azurerm_role_assignment.policy_identity
  to   = module.policy_identity.azurerm_role_assignment.this
}

resource "time_sleep" "role_assignment_propagation" {
  count = length(local.role_assignments_map) > 0 ? 1 : 0

  depends_on      = [module.policy_identity]
  create_duration = "60s"

  triggers = {
    role_ids = jsonencode([for ra in module.policy_identity : ra.id])
  }
}
