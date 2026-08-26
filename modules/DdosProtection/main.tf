###############################################################
# MODULE: DdosProtection - Main
# Description: Azure DDoS Protection Plan
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — composed from the in-repo Naming submodule's
# suffix output with the house literal prefix `ddos-` (Azure/naming
# uses `ddospp-` — divergent, so we keep the literal to avoid state churn).
# Convention: ddos-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    ddos-con-prod-gwc-network
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  computed_name = var.name != null ? "" : "ddos-${join("-", module.naming["this"].suffix)}"
  name          = var.name != null ? var.name : local.computed_name
}

###############################################################
# RESOURCE: DDoS Protection Plan
###############################################################
resource "azurerm_network_ddos_protection_plan" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RBAC: Role Assignments
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_network_ddos_protection_plan.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_network_ddos_protection_plan.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
