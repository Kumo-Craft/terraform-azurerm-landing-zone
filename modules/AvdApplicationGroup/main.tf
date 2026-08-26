###############################################################
# MODULE: AvdApplicationGroup - Main
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
  name = var.name != null ? var.name : module.naming["this"].result.virtual_desktop_application_group.name
}

resource "azurerm_virtual_desktop_application_group" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  type         = var.type
  host_pool_id = var.host_pool_id

  friendly_name                = var.friendly_name
  description                  = var.description
  default_desktop_display_name = var.type == "Desktop" ? var.default_desktop_display_name : null

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: RemoteApp applications (F-3)
# Only deployed when var.type == "RemoteApp".
###############################################################
resource "azurerm_virtual_desktop_application" "this" {
  for_each = var.type == "RemoteApp" ? var.applications : {}

  name                         = each.value.name
  application_group_id         = azurerm_virtual_desktop_application_group.this.id
  command_line_argument_policy = each.value.command_line_argument_policy
  path                         = each.value.path
  friendly_name                = each.value.friendly_name
  description                  = each.value.description
  command_line_arguments       = each.value.command_line_arguments
  icon_path                    = each.value.icon_path
  icon_index                   = each.value.icon_index
  show_in_portal               = each.value.show_in_portal
}

###############################################################
# RESOURCE: Management Lock (F-2)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_virtual_desktop_application_group.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments (F-1)
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_virtual_desktop_application_group.this.id
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}

###############################################################
# TOMBSTONE: workspace association removed in v0.2.33 (F-5)
# The azurerm_virtual_desktop_workspace_application_group_association
# resource has been moved to the AvdWorkspace module.
# This removed block prevents Terraform from destroying the Azure
# resource when callers upgrade — use terraform state mv to migrate.
###############################################################
removed {
  from = azurerm_virtual_desktop_workspace_application_group_association.this

  lifecycle {
    destroy = false
  }
}
