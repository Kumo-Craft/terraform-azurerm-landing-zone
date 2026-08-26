###############################################################
# MODULE: ManagedDevOpsPool - Main
# Description: Azure Managed DevOps Pool
#              (Microsoft.DevOpsInfrastructure/pools) — managed
#              Azure DevOps agents under a Dev Center project, with
#              optional VNet injection.
###############################################################

resource "time_static" "time" {}

locals {
  # Convention name: mdp-{acr}-{env}-{region}-{workload}.
  name = var.name != null ? var.name : "mdp-${var.subscription_acronym}-${var.environment}-${var.region_code}-${var.workload}"
}

###############################################################
# RESOURCE: Managed DevOps Pool
###############################################################
resource "azurerm_managed_devops_pool" "this" {
  name                  = local.name
  location              = var.location
  resource_group_name   = var.resource_group_name
  dev_center_project_id = var.dev_center_project_id
  maximum_concurrency   = var.maximum_concurrency
  work_folder           = var.work_folder

  azure_devops_organization {
    dynamic "organization" {
      for_each = var.organizations
      content {
        url         = organization.value.url
        parallelism = coalesce(organization.value.parallelism, var.maximum_concurrency)
        projects    = length(organization.value.projects) > 0 ? organization.value.projects : null
      }
    }

    dynamic "permission" {
      for_each = var.permission != null ? [var.permission] : []
      content {
        kind = permission.value.kind

        dynamic "administrator_account" {
          for_each = permission.value.kind == "SpecificAccounts" ? [1] : []
          content {
            groups = length(permission.value.administrator_groups) > 0 ? permission.value.administrator_groups : null
            users  = length(permission.value.administrator_users) > 0 ? permission.value.administrator_users : null
          }
        }
      }
    }
  }

  dynamic "identity" {
    for_each = length(var.identity_ids) > 0 ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = var.identity_ids
    }
  }

  # Exactly one agent profile — stateless (default) or stateful.
  dynamic "stateless_agent" {
    for_each = var.agent_type == "stateless" ? [1] : []
    content {
      dynamic "automatic_resource_prediction" {
        # manual prime : automatic seulement si pas de standby manuel
        for_each = var.manual_standby_agent_count == null && var.automatic_resource_prediction_enabled ? [1] : []
        content {
          prediction_preference = var.prediction_preference
        }
      }

      # standby manuel (agents chauds 24/7)
      dynamic "manual_resource_prediction" {
        for_each = var.manual_standby_agent_count != null ? [1] : []
        content {
          all_week_schedule = var.manual_standby_agent_count
          time_zone_name    = var.manual_time_zone
        }
      }
    }
  }

  dynamic "stateful_agent" {
    for_each = var.agent_type == "stateful" ? [1] : []
    content {
      grace_period_time_span = var.stateful_grace_period_time_span
      maximum_agent_lifetime = var.stateful_maximum_agent_lifetime

      dynamic "automatic_resource_prediction" {
        # manual prime : automatic seulement si pas de standby manuel
        for_each = var.manual_standby_agent_count == null && var.automatic_resource_prediction_enabled ? [1] : []
        content {
          prediction_preference = var.prediction_preference
        }
      }

      # standby manuel (agents chauds 24/7)
      dynamic "manual_resource_prediction" {
        for_each = var.manual_standby_agent_count != null ? [1] : []
        content {
          all_week_schedule = var.manual_standby_agent_count
          time_zone_name    = var.manual_time_zone
        }
      }
    }
  }

  virtual_machine_scale_set_fabric {
    sku_name                     = var.sku_name
    os_disk_storage_account_type = var.os_disk_storage_account_type
    subnet_id                    = var.subnet_id # VNet injection — null = isolated MS-managed network

    dynamic "image" {
      for_each = var.images
      content {
        well_known_image_name = image.value.well_known_image_name
        id                    = image.value.id
        aliases               = length(image.value.aliases) > 0 ? image.value.aliases : null
        buffer                = image.value.buffer
      }
    }

    dynamic "storage" {
      for_each = var.storage != null ? [var.storage] : []
      content {
        disk_size_in_gb      = storage.value.disk_size_in_gb
        caching              = storage.value.caching
        drive_letter         = storage.value.drive_letter
        storage_account_type = storage.value.storage_account_type
      }
    }

    dynamic "security" {
      for_each = var.interactive_logon_enabled ? [1] : []
      content {
        interactive_logon_enabled = var.interactive_logon_enabled
      }
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
      condition     = length(local.name) >= 3 && length(local.name) <= 44
      error_message = "The composed pool name \"${local.name}\" must be 3-44 characters. Shorten `workload` or pass an explicit `name`."
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
      scope      = azurerm_managed_devops_pool.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
