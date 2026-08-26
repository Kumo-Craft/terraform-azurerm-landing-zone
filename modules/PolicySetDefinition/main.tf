###############################################################
# MODULE: PolicySetDefinition - Main
#
# Map-shape module creating Azure Policy Set Definitions (initiatives).
# Dispatches to the correct azurerm resource based on scope:
#   - Subscription-scoped : azurerm_policy_set_definition
#   - MG-scoped           : azurerm_management_group_policy_set_definition
#
# Schema notes (azurerm 4.x):
#   - azurerm_policy_set_definition.management_group_id is DEPRECATED.
#     MG-scoped set definitions must use azurerm_management_group_policy_set_definition.
#   - policy_definition_reference block inner arg: policy_group_names (NOT policy_definition_group_names).
#   - parameter_values in policy_definition_reference is a JSON string; we jsonencode the caller object.
#   - policy_type : REQUIRED field in provider schema; always passed (default "Custom").
###############################################################

locals {
  sub_items = {
    for k, v in var.set_definitions : k => v
    if v.management_group_id == null
  }

  mg_items = {
    for k, v in var.set_definitions : k => v
    if v.management_group_id != null
  }
}

###############################################################
# Subscription-scoped set definitions
###############################################################
resource "azurerm_policy_set_definition" "this" {
  for_each = local.sub_items

  name         = each.key
  display_name = each.value.display_name
  policy_type  = each.value.policy_type
  description  = each.value.description
  metadata     = each.value.metadata != null ? jsonencode(each.value.metadata) : null
  parameters   = each.value.parameters != null ? jsonencode(each.value.parameters) : null

  dynamic "policy_definition_reference" {
    for_each = each.value.policy_definition_references
    content {
      policy_definition_id = policy_definition_reference.value.policy_definition_id
      reference_id         = policy_definition_reference.value.reference_id
      parameter_values     = policy_definition_reference.value.parameter_values != null ? jsonencode(policy_definition_reference.value.parameter_values) : null
      policy_group_names   = policy_definition_reference.value.policy_definition_group_names
    }
  }

  dynamic "policy_definition_group" {
    for_each = each.value.policy_definition_groups
    content {
      name                            = policy_definition_group.value.name
      display_name                    = policy_definition_group.value.display_name
      description                     = policy_definition_group.value.description
      category                        = policy_definition_group.value.category
      additional_metadata_resource_id = policy_definition_group.value.additional_metadata_resource_id
    }
  }
}

###############################################################
# Management Group-scoped set definitions
# Uses dedicated resource — azurerm_policy_set_definition
# management_group_id arg is deprecated in azurerm 4.x.
###############################################################
resource "azurerm_management_group_policy_set_definition" "this" {
  for_each = local.mg_items

  name                = each.key
  display_name        = each.value.display_name
  policy_type         = each.value.policy_type
  description         = each.value.description
  management_group_id = each.value.management_group_id
  metadata            = each.value.metadata != null ? jsonencode(each.value.metadata) : null
  parameters          = each.value.parameters != null ? jsonencode(each.value.parameters) : null

  dynamic "policy_definition_reference" {
    for_each = each.value.policy_definition_references
    content {
      policy_definition_id = policy_definition_reference.value.policy_definition_id
      reference_id         = policy_definition_reference.value.reference_id
      parameter_values     = policy_definition_reference.value.parameter_values != null ? jsonencode(policy_definition_reference.value.parameter_values) : null
      policy_group_names   = policy_definition_reference.value.policy_definition_group_names
    }
  }

  dynamic "policy_definition_group" {
    for_each = each.value.policy_definition_groups
    content {
      name                            = policy_definition_group.value.name
      display_name                    = policy_definition_group.value.display_name
      description                     = policy_definition_group.value.description
      category                        = policy_definition_group.value.category
      additional_metadata_resource_id = policy_definition_group.value.additional_metadata_resource_id
    }
  }
}
