###############################################################
# MODULE: ResourceGroup - Main
# Description: Creates N Azure Resource Groups in one apply,
#              each with its own optional management lock and
#              role assignments. Map-shape input — pass a single
#              entry when you only need one RG.
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming module
# (wrapper around Azure/naming/azurerm).
#
# Convention (unchanged from previous implementation):
#   rg-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:
#   rg-shc-nprd-gwc-network
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.resource_groups

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  # Per-RG region_code override falls back to the set-level value.
  # Allows mixing regions in one set (e.g. GWC RGs alongside WEU RGs for
  # workloads with control planes hosted in a different region).
  region_code = each.value.region_code != null ? each.value.region_code : var.region_code
  workload    = each.value.workload
}

locals {
  effective_locations = {
    for k, rg in var.resource_groups :
    k => rg.location != null ? rg.location : var.location
  }

  computed_names = {
    for k, rg in var.resource_groups :
    k => rg.name != null ? rg.name : module.naming[k].result.resource_group.name
  }

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # Flatten role assignments to a single map keyed by "<rg_key>|<ra_key>"
  # so a single azurerm_role_assignment.this for_each handles everything.
  role_assignments_flat = merge([
    for rg_key, rg in var.resource_groups : {
      for ra_key, ra in rg.role_assignments :
      "${rg_key}|${ra_key}" => merge(ra, { rg_key = rg_key })
    }
  ]...)

  role_definition_resource_substring = "/providers/Microsoft.Authorization/roleDefinitions"
}

###############################################################
# RESOURCE: Resource Groups
###############################################################
resource "azurerm_resource_group" "this" {
  for_each = var.resource_groups

  name     = local.computed_names[each.key]
  location = local.effective_locations[each.key]

  tags = merge(local.common_tags, each.value.tags)

  # Hardcoded prevent_destroy per critical-pivot pattern. ResourceGroup is the
  # BASE module for the entire ALZ — destruction cascades to every resource
  # inside. Disabling requires module fork.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# Management Locks (per-RG, optional — delegated to ResourceLock)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = {
    for k, rg in var.resource_groups : k => {
      scope      = azurerm_resource_group.this[k].id
      lock_level = rg.lock.kind
      name       = rg.lock.name
      notes      = rg.lock.notes
    }
    if rg.lock != null
  }
}

###############################################################
# RESOURCE: Role Assignments (per-RG, optional) — delegated to ../RoleAssignment
# Flat map keyed by "<rg_key>|<ra_key>" preserved end-to-end.
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = local.role_assignments_flat

  scope                                  = azurerm_resource_group.this[each.value.rg_key].id
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  principal_type                         = each.value.principal_type
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}

# NOTE (v0.2.76): The moved block that previously existed here was removed
# because module.role_assignments is for_each-keyed by dynamic
# "<rg_key>|<ra_key>" tuples. Static moved blocks cannot match for_each
# dynamic keys — Terraform would error at plan time for every caller whose
# state still has azurerm_role_assignment.this["<key>"] entries.
#
# Callers with existing state at azurerm_role_assignment.this["<key>"] must
# manually run terraform state mv:
#
#   terraform state mv \
#     'azurerm_role_assignment.this["<key>"]' \
#     'module.role_assignments["<key>"].azurerm_role_assignment.this'
#
# See README.md — "Breaking changes (v0.2.76)" — for the full migration recipe.
