###############################################################
# MODULE: AvdHostPool - Main
# Description: Azure Virtual Desktop host pool
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention
# Convention: vdpool-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    vdpool-avd-nprd-gwc-pooled
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
  name = var.name != null ? var.name : module.naming["this"].result.virtual_desktop_host_pool.name
}

###############################################################
# RESOURCE: Host Pool
###############################################################
resource "azurerm_virtual_desktop_host_pool" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  type                             = var.type
  load_balancer_type               = var.load_balancer_type
  maximum_sessions_allowed         = var.type == "Pooled" ? var.maximum_sessions_allowed : null
  preferred_app_group_type         = var.preferred_app_group_type
  start_vm_on_connect              = var.start_vm_on_connect
  validate_environment             = var.validate_environment
  public_network_access            = var.public_network_access
  personal_desktop_assignment_type = var.type == "Personal" ? var.personal_desktop_assignment_type : null

  friendly_name         = var.friendly_name
  description           = var.description
  custom_rdp_properties = var.custom_rdp_properties

  dynamic "scheduled_agent_updates" {
    for_each = var.scheduled_agent_updates == null ? [] : [var.scheduled_agent_updates]
    content {
      enabled                   = scheduled_agent_updates.value.enabled
      timezone                  = scheduled_agent_updates.value.timezone
      use_session_host_timezone = scheduled_agent_updates.value.use_session_host_timezone

      dynamic "schedule" {
        for_each = scheduled_agent_updates.value.schedule
        content {
          day_of_week = schedule.value.day_of_week
          hour_of_day = schedule.value.hour_of_day
        }
      }
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # Scaling plans dynamically swap load_balancer_type per phase
  # (BreadthFirst at peak, DepthFirst during ramp-down/off-peak).
  # Without ignore_changes, every terragrunt apply would fight the
  # scaling plan's runtime mutation and cause permanent drift.
  # The Terraform value here remains the initial baseline at create time.
  lifecycle {
    ignore_changes = [load_balancer_type]
  }
}

###############################################################
# RESOURCE: Registration Info — auto-rotating token
#
# time_rotating advances whenever `terraform apply` runs after the
# rotation_hours window has elapsed. The dependent registration_info
# resource is then replace-triggered, which generates a fresh token
# with a new expiration_date.
#
# Operationally: schedule a CI apply at least once per rotation
# period (e.g. nightly when registration_expiration_hours > 24) so
# new session hosts always find a valid token to register against.
###############################################################
resource "time_rotating" "registration_token" {
  count = var.create_registration_info ? 1 : 0

  rotation_hours = var.registration_expiration_hours
}

resource "azurerm_virtual_desktop_host_pool_registration_info" "this" {
  count = var.create_registration_info ? 1 : 0

  hostpool_id     = azurerm_virtual_desktop_host_pool.this.id
  expiration_date = time_rotating.registration_token[0].rotation_rfc3339

  lifecycle {
    replace_triggered_by = [time_rotating.registration_token[0]]
  }
}

###############################################################
# RESOURCE: Management Lock (F-4)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_virtual_desktop_host_pool.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments (F-5)
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_virtual_desktop_host_pool.this.id
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
