###############################################################
# MODULE: PolicyDefinition - Main
#
# Map-shape module creating custom Azure Policy Definitions.
# Supports both subscription-scoped (management_group_id = null)
# and Management Group-scoped (management_group_id set) definitions
# via the same resource — azurerm_policy_definition accepts
# management_group_id as an optional field to control scope.
#
# Schema notes (azurerm 4.x):
#   - mode        : REQUIRED field in provider schema; we always pass it
#                   (variables.tf default "All" ensures it is never null).
#   - policy_type : REQUIRED field in provider schema; always passed.
#   - policy_rule : optional in schema but functionally required for a
#                   useful definition; caller must supply it.
#   - metadata    : optional+computed string; we jsonencode map(string).
#   - parameters  : optional string; we jsonencode any object from caller.
###############################################################

resource "azurerm_policy_definition" "this" {
  for_each = var.definitions

  name                = each.key
  display_name        = each.value.display_name
  policy_type         = each.value.policy_type
  mode                = each.value.mode
  description         = each.value.description
  management_group_id = each.value.management_group_id
  policy_rule         = jsonencode(each.value.policy_rule)
  parameters          = each.value.parameters != null ? jsonencode(each.value.parameters) : null
  metadata            = each.value.metadata != null ? jsonencode(each.value.metadata) : null
}
