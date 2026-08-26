###############################################################
# MODULE: ActionGroup - Main
# Description: Azure Monitor Action Group with email and push receivers
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — composed from the in-repo Naming submodule's
# suffix output with the house literal prefix `ag-` (Azure/naming
# uses `mag-` — divergent, so we keep the literal to avoid state churn).
#
# The naming submodule is only called when `name` is NOT overridden.
# This lets callers bypass the convention entirely (e.g. for legacy
# resources whose deployed name predates the convention) by passing
# `name = "..."` and leaving the 4 house vars null.
#
# Convention: ag-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    ag-mgm-nprd-gwc-ama
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
  name = var.name != null ? var.name : "ag-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RESOURCE: Action Group
###############################################################
resource "azurerm_monitor_action_group" "this" {
  name                = local.name
  location            = "global"
  resource_group_name = var.resource_group_name
  short_name          = var.short_name

  dynamic "email_receiver" {
    for_each = var.email_addresses
    content {
      name                    = substr(replace(email_receiver.value, "@", "-at-"), 0, 50)
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "azure_app_push_receiver" {
    for_each = var.push_email_addresses
    content {
      name          = substr("${replace(azure_app_push_receiver.value, "@", "-at-")}-app", 0, 50)
      email_address = azure_app_push_receiver.value
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.webhook_receivers
    content {
      name                    = substr(webhook_receiver.key, 0, 50)
      service_uri             = webhook_receiver.value.service_uri
      use_common_alert_schema = webhook_receiver.value.use_common_alert_schema

      dynamic "aad_auth" {
        for_each = webhook_receiver.value.aad_auth != null ? [webhook_receiver.value.aad_auth] : []
        content {
          object_id      = aad_auth.value.object_id
          identifier_uri = aad_auth.value.identifier_uri
          tenant_id      = aad_auth.value.tenant_id
        }
      }
    }
  }

  dynamic "sms_receiver" {
    for_each = var.sms_receivers
    content {
      name         = substr(sms_receiver.key, 0, 50)
      country_code = sms_receiver.value.country_code
      phone_number = sms_receiver.value.phone_number
    }
  }

  dynamic "arm_role_receiver" {
    for_each = var.arm_role_receivers
    content {
      name                    = substr(arm_role_receiver.key, 0, 50)
      role_id                 = arm_role_receiver.value.role_id
      use_common_alert_schema = arm_role_receiver.value.use_common_alert_schema
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
# RESOURCE: Management Lock (optional) — F-6
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_monitor_action_group.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
