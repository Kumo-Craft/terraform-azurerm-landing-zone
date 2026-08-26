###############################################################
# MODULE: ContainerAppEnvironment - Main
# Description: Azure Container Apps Environment
#              (Microsoft.App/managedEnvironments) — the shared
#              host boundary for Container Apps.
###############################################################

resource "time_static" "time" {}

locals {
  # Convention name: cae-{acr}-{env}-{region}-{workload}.
  name = var.name != null ? var.name : "cae-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.workload}"
}

###############################################################
# RESOURCE: Container App Environment
###############################################################
resource "azurerm_container_app_environment" "this" {
  name                = local.name
  location            = var.location
  resource_group_name = var.resource_group_name

  logs_destination           = var.logs_destination
  log_analytics_workspace_id = var.log_analytics_workspace_id

  infrastructure_subnet_id = var.infrastructure_subnet_id
  # internal_load_balancer / zone_redundancy are RequiredWith infrastructure_subnet_id
  # at the provider level — only set them when a subnet is present, otherwise leave
  # unset (null) so the provider doesn't demand a subnet for the default false values.
  internal_load_balancer_enabled              = var.infrastructure_subnet_id != null ? var.internal_load_balancer_enabled : null
  zone_redundancy_enabled                     = var.infrastructure_subnet_id != null ? var.zone_redundancy_enabled : null
  infrastructure_resource_group_name          = var.infrastructure_resource_group_name
  public_network_access                       = var.public_network_access
  mutual_tls_enabled                          = var.mutual_tls_enabled
  dapr_application_insights_connection_string = var.dapr_application_insights_connection_string

  dynamic "workload_profile" {
    for_each = var.workload_profiles
    content {
      name                  = workload_profile.value.name
      workload_profile_type = workload_profile.value.workload_profile_type
      minimum_count         = workload_profile.value.minimum_count
      maximum_count         = workload_profile.value.maximum_count
    }
  }

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []
    content {
      type         = identity.value.type
      identity_ids = length(identity.value.identity_ids) > 0 ? identity.value.identity_ids : null
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  lifecycle {
    precondition {
      condition     = length(local.name) >= 2 && length(local.name) <= 32
      error_message = "The composed environment name \"${local.name}\" must be 2-32 characters. Shorten `workload` or pass an explicit `name`."
    }
  }
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_container_app_environment.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
