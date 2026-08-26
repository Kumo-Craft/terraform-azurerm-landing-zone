###############################################################
# MODULE: DevCenter - Main
# Description: Azure Dev Center (Microsoft.DevCenter/devcenters)
#              with a managed identity, lock and role assignments.
###############################################################

resource "time_static" "time" {}

locals {
  # Convention name: dc-{acr}-{env}-{region}-{workload} (no dev_center
  # type in the Naming submodule, so composed here directly).
  name = var.name != null ? var.name : "dc-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.workload}"
}

###############################################################
# RESOURCE: Dev Center
###############################################################
resource "azurerm_dev_center" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  project_catalog_item_sync_enabled = var.project_catalog_item_sync_enabled

  identity {
    type         = var.identity.type
    identity_ids = length(var.identity.identity_ids) > 0 ? var.identity.identity_ids : null
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    precondition {
      condition     = length(local.name) >= 3 && length(local.name) <= 26
      error_message = "The composed Dev Center name \"${local.name}\" must be 3-26 characters. Shorten `workload` or pass an explicit `name`."
    }
  }
}

###############################################################
# RESOURCE: Dev Center Environment Types
# Prerequisite for project environment types. The name is the only
# configurable property at the Dev Center level.
###############################################################
resource "azurerm_dev_center_environment_type" "this" {
  for_each = toset(var.environment_types)

  name          = each.value
  dev_center_id = azurerm_dev_center.this.id

  tags = var.tags
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_dev_center.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                                  = azurerm_dev_center.this.id
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  principal_type                         = each.value.principal_type
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}
