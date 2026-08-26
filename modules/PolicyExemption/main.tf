###############################################################
# MODULE: PolicyExemption - Main
# Creates one policy exemption per entry in var.exemptions,
# dispatched to the correct azurerm resource based on the
# scope (RG / Subscription / Management Group).
###############################################################

locals {
  rg_exemptions  = { for k, v in var.exemptions : k => v if v.resource_group_id != null }
  sub_exemptions = { for k, v in var.exemptions : k => v if v.subscription_id != null }
  mg_exemptions  = { for k, v in var.exemptions : k => v if v.management_group_id != null }
}

resource "azurerm_resource_group_policy_exemption" "this" {
  for_each = local.rg_exemptions

  name                            = each.key
  resource_group_id               = each.value.resource_group_id
  policy_assignment_id            = each.value.policy_assignment_id
  exemption_category              = each.value.exemption_category
  display_name                    = each.value.display_name
  description                     = each.value.description
  expires_on                      = each.value.expires_on
  policy_definition_reference_ids = each.value.policy_definition_reference_ids
  metadata                        = each.value.metadata != null ? jsonencode(each.value.metadata) : null
}

resource "azurerm_subscription_policy_exemption" "this" {
  for_each = local.sub_exemptions

  name                            = each.key
  subscription_id                 = each.value.subscription_id
  policy_assignment_id            = each.value.policy_assignment_id
  exemption_category              = each.value.exemption_category
  display_name                    = each.value.display_name
  description                     = each.value.description
  expires_on                      = each.value.expires_on
  policy_definition_reference_ids = each.value.policy_definition_reference_ids
  metadata                        = each.value.metadata != null ? jsonencode(each.value.metadata) : null
}

resource "azurerm_management_group_policy_exemption" "this" {
  for_each = local.mg_exemptions

  name                            = each.key
  management_group_id             = each.value.management_group_id
  policy_assignment_id            = each.value.policy_assignment_id
  exemption_category              = each.value.exemption_category
  display_name                    = each.value.display_name
  description                     = each.value.description
  expires_on                      = each.value.expires_on
  policy_definition_reference_ids = each.value.policy_definition_reference_ids
  metadata                        = each.value.metadata != null ? jsonencode(each.value.metadata) : null
}
