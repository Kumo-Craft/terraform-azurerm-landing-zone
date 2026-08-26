###############################################################
# MODULE: DevCenterProject - Main
# Description: Azure Dev Center Project (Microsoft.DevCenter/projects)
#              with a managed identity, lock and role assignments.
###############################################################

resource "time_static" "time" {}

locals {
  # Convention name: dcp-{acr}-{env}-{region}-{workload}.
  name = var.name != null ? var.name : "dcp-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.workload}"
}

###############################################################
# RESOURCE: Dev Center Project
###############################################################
resource "azurerm_dev_center_project" "this" {
  name                = local.name
  dev_center_id       = var.dev_center_id
  location            = var.location
  resource_group_name = var.resource_group_name

  description                = var.description
  maximum_dev_boxes_per_user = var.maximum_dev_boxes_per_user

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
      condition     = length(local.name) >= 3 && length(local.name) <= 63
      error_message = "The composed project name \"${local.name}\" must be 3-63 characters. Shorten `workload` or pass an explicit `name`."
    }
  }
}

###############################################################
# RESOURCE: Project Environment Types (Deployment Environments)
# Makes an environment type deployable for this project: target
# subscription + deployment identity + creator/user role grants.
# The name must match a Dev Center environment type.
###############################################################
resource "azurerm_dev_center_project_environment_type" "this" {
  for_each = var.environment_types

  name                  = each.key
  location              = var.location
  dev_center_project_id = azurerm_dev_center_project.this.id
  deployment_target_id  = each.value.deployment_target_id

  creator_role_assignment_roles = length(each.value.creator_role_assignment_roles) > 0 ? each.value.creator_role_assignment_roles : null

  identity {
    type         = each.value.identity.type
    identity_ids = length(each.value.identity.identity_ids) > 0 ? each.value.identity.identity_ids : null
  }

  dynamic "user_role_assignment" {
    for_each = each.value.user_role_assignments
    content {
      user_id = user_role_assignment.key
      roles   = user_role_assignment.value
    }
  }

  tags = merge(var.tags, each.value.tags)
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_dev_center_project.this.id
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

  scope                                  = azurerm_dev_center_project.this.id
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  principal_type                         = each.value.principal_type
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}
