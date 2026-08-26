###############################################################
# MODULE: AvdWorkspace - Main
###############################################################

resource "time_static" "time" {}

module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  name = var.name != null ? var.name : module.naming["this"].result.virtual_desktop_workspace.name
}

resource "azurerm_virtual_desktop_workspace" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  friendly_name                 = var.friendly_name
  description                   = var.description
  public_network_access_enabled = var.public_network_access_enabled

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Application Group Associations (F-1)
# Closes the F-5 tombstone in AvdApplicationGroup v0.2.33.
# Workspace is the single source of truth for association binding.
###############################################################
resource "azurerm_virtual_desktop_workspace_application_group_association" "this" {
  for_each = var.application_group_associations

  workspace_id         = azurerm_virtual_desktop_workspace.this.id
  application_group_id = each.value
}

###############################################################
# RESOURCE: Management Lock (F-3)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_virtual_desktop_workspace.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments (F-4)
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_virtual_desktop_workspace.this.id
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
