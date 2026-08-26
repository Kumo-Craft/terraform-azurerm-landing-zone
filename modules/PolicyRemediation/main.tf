###############################################################
# MODULE: PolicyRemediation - Main
#
# Map-shape module dispatching policy remediation tasks to one of
# four scopes (Management Group, Subscription, Resource Group, or
# individual Resource) per entry. Mirrors the PolicyExemption v0.2.11
# canonical 3-scope dispatch pattern + adds a 4th resource-level scope.
#
# Schema note: azurerm_management_group_policy_remediation does NOT
# expose resource_discovery_mode (the argument is absent from the
# provider schema for that resource type). MG-scope entries always
# use the Azure API default (ExistingNonCompliant). The variables.tf
# validator already blocks ReEvaluateCompliance for MG entries.
###############################################################

locals {
  mg_items = {
    for k, v in var.remediations : k => v
    if v.management_group_id != null
  }

  sub_items = {
    for k, v in var.remediations : k => v
    if v.subscription_id != null
  }

  rg_items = {
    for k, v in var.remediations : k => v
    if v.resource_group_id != null
  }

  resource_items = {
    for k, v in var.remediations : k => v
    if v.resource_id != null
  }
}

###############################################################
# Management Group scope
# Note: resource_discovery_mode is NOT a valid argument here —
# omitted intentionally per provider schema (azurerm 4.x).
###############################################################
resource "azurerm_management_group_policy_remediation" "this" {
  for_each = local.mg_items

  name                           = each.key
  management_group_id            = each.value.management_group_id
  policy_assignment_id           = each.value.policy_assignment_id
  policy_definition_reference_id = each.value.policy_definition_reference_id
  location_filters               = length(each.value.location_filters) > 0 ? each.value.location_filters : null
  resource_count                 = each.value.resource_count
  parallel_deployments           = each.value.parallel_deployments
  failure_percentage             = each.value.failure_percentage
}

###############################################################
# Subscription scope
###############################################################
resource "azurerm_subscription_policy_remediation" "this" {
  for_each = local.sub_items

  name                           = each.key
  subscription_id                = each.value.subscription_id
  policy_assignment_id           = each.value.policy_assignment_id
  policy_definition_reference_id = each.value.policy_definition_reference_id
  resource_discovery_mode        = each.value.resource_discovery_mode
  location_filters               = length(each.value.location_filters) > 0 ? each.value.location_filters : null
  resource_count                 = each.value.resource_count
  parallel_deployments           = each.value.parallel_deployments
  failure_percentage             = each.value.failure_percentage
}

###############################################################
# Resource Group scope
###############################################################
resource "azurerm_resource_group_policy_remediation" "this" {
  for_each = local.rg_items

  name                           = each.key
  resource_group_id              = each.value.resource_group_id
  policy_assignment_id           = each.value.policy_assignment_id
  policy_definition_reference_id = each.value.policy_definition_reference_id
  resource_discovery_mode        = each.value.resource_discovery_mode
  location_filters               = length(each.value.location_filters) > 0 ? each.value.location_filters : null
  resource_count                 = each.value.resource_count
  parallel_deployments           = each.value.parallel_deployments
  failure_percentage             = each.value.failure_percentage
}

###############################################################
# Resource scope (individual ARM resource)
###############################################################
resource "azurerm_resource_policy_remediation" "this" {
  for_each = local.resource_items

  name                           = each.key
  resource_id                    = each.value.resource_id
  policy_assignment_id           = each.value.policy_assignment_id
  policy_definition_reference_id = each.value.policy_definition_reference_id
  resource_discovery_mode        = each.value.resource_discovery_mode
  location_filters               = length(each.value.location_filters) > 0 ? each.value.location_filters : null
  resource_count                 = each.value.resource_count
  parallel_deployments           = each.value.parallel_deployments
  failure_percentage             = each.value.failure_percentage
}
