###############################################################
# MODULE: AvdScalingPlan - Main
# Azure Virtual Desktop Autoscale scaling plan
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
  name = var.name != null ? var.name : module.naming["this"].result.virtual_desktop_scaling_plan.name
}

resource "azurerm_virtual_desktop_scaling_plan" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  time_zone     = var.time_zone
  friendly_name = var.friendly_name
  description   = var.description
  exclusion_tag = var.exclusion_tag

  dynamic "schedule" {
    for_each = var.schedules
    content {
      name                                 = schedule.key
      days_of_week                         = schedule.value.days_of_week
      ramp_up_start_time                   = schedule.value.ramp_up_start_time
      ramp_up_load_balancing_algorithm     = schedule.value.ramp_up_load_balancing_algorithm
      ramp_up_minimum_hosts_percent        = schedule.value.ramp_up_minimum_hosts_percent
      ramp_up_capacity_threshold_percent   = schedule.value.ramp_up_capacity_threshold_percent
      peak_start_time                      = schedule.value.peak_start_time
      peak_load_balancing_algorithm        = schedule.value.peak_load_balancing_algorithm
      ramp_down_start_time                 = schedule.value.ramp_down_start_time
      ramp_down_load_balancing_algorithm   = schedule.value.ramp_down_load_balancing_algorithm
      ramp_down_minimum_hosts_percent      = schedule.value.ramp_down_minimum_hosts_percent
      ramp_down_capacity_threshold_percent = schedule.value.ramp_down_capacity_threshold_percent
      ramp_down_force_logoff_users         = schedule.value.ramp_down_force_logoff_users
      ramp_down_wait_time_minutes          = schedule.value.ramp_down_wait_time_minutes
      ramp_down_notification_message       = schedule.value.ramp_down_notification_message
      ramp_down_stop_hosts_when            = schedule.value.ramp_down_stop_hosts_when
      off_peak_start_time                  = schedule.value.off_peak_start_time
      off_peak_load_balancing_algorithm    = schedule.value.off_peak_load_balancing_algorithm
    }
  }

  dynamic "host_pool" {
    for_each = var.host_pool_associations
    content {
      hostpool_id          = host_pool.value.hostpool_id
      scaling_plan_enabled = host_pool.value.scaling_plan_enabled
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RESOURCE: Management Lock (F-2)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_virtual_desktop_scaling_plan.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments (F-3)
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_virtual_desktop_scaling_plan.this.id
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
