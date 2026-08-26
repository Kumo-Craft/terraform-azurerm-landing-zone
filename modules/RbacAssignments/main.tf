###############################################################
# MODULE: RbacAssignments - Main
# Description: Azure RBAC role assignments for Entra ID groups
#              (resolved by display_name) and managed identities
#              (by direct principal_id)
###############################################################

locals {
  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"
}

###############################################################
# DATA: Resolve Entra ID groups by display_name (deduplicated)
###############################################################
data "azuread_group" "this" {
  for_each     = toset([for a in var.group_assignments : a.group_name])
  display_name = each.value
}

###############################################################
# RESOURCE: Role Assignments — Entra ID Groups
###############################################################
resource "azurerm_role_assignment" "groups" {
  for_each = var.group_assignments

  scope                = each.value.scope
  principal_id         = data.azuread_group.this[each.value.group_name].object_id
  principal_type       = "Group"
  role_definition_id   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  condition            = each.value.condition
  condition_version    = each.value.condition_version
  description          = each.value.description
}

###############################################################
# RESOURCE: Role Assignments — Managed Identities / SPs
###############################################################
resource "azurerm_role_assignment" "identities" {
  for_each = var.identity_assignments

  scope                            = each.value.scope
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id               = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name             = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check

  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}
