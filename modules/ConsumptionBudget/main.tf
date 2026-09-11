###############################################################
# MODULE: ConsumptionBudget - Main
# Description: Cost Management budget scoped to a resource group,
# with Actual + Forecasted threshold notifications to emails /
# Action Groups / RBAC roles. A soft cost guard-rail — it never
# stops consumption (unlike a hard daily cap), only notifies.
#
# Grounded on azurerm_consumption_budget_resource_group
# (Microsoft.Consumption 2019-10-01).
###############################################################

###############################################################
# Naming — via ../Naming submodule. Convention: bdg-{acr}-{env}-{region}-{workload}.
# Upstream Azure/naming has no "budget" type, so we apply the CAF bdg- slug
# manually and join the suffix from the Naming module. The for_each guard keeps
# the module out of the graph when var.name is set (escape hatch).
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
  name = var.name != null ? var.name : "bdg-${join("-", module.naming["this"].suffix)}"

  # Normalize subscription scope — accept bare GUID or /subscriptions/<guid>
  # (same pattern as SecurityCenterWorkspace). Null when RG-scoped.
  subscription_scope = var.subscription_id == null ? null : (
    startswith(var.subscription_id, "/subscriptions/") ? var.subscription_id : "/subscriptions/${var.subscription_id}"
  )

  # The one budget that exists (exactly one, enforced by the XOR validation).
  budget_id = coalesce(
    one(azurerm_consumption_budget_resource_group.this[*].id),
    one(azurerm_consumption_budget_subscription.this[*].id),
  )
  budget_name = coalesce(
    one(azurerm_consumption_budget_resource_group.this[*].name),
    one(azurerm_consumption_budget_subscription.this[*].name),
  )
}

###############################################################
# Resource Group Consumption Budget (when resource_group_id set)
###############################################################
resource "azurerm_consumption_budget_resource_group" "this" {
  count = var.resource_group_id != null ? 1 : 0

  name              = local.name
  resource_group_id = var.resource_group_id
  amount            = var.amount
  time_grain        = var.time_grain

  time_period {
    start_date = var.start_date
    end_date   = var.end_date
  }

  dynamic "notification" {
    for_each = { for i, n in var.notifications : tostring(i) => n }
    content {
      enabled        = notification.value.enabled
      threshold      = notification.value.threshold
      operator       = notification.value.operator
      threshold_type = notification.value.threshold_type
      contact_emails = notification.value.contact_emails
      contact_groups = notification.value.contact_groups
      contact_roles  = notification.value.contact_roles
    }
  }

  dynamic "filter" {
    for_each = var.filter == null ? [] : [var.filter]
    content {
      dynamic "dimension" {
        for_each = { for d in filter.value.dimensions : d.name => d }
        content {
          name     = dimension.value.name
          operator = dimension.value.operator
          values   = dimension.value.values
        }
      }
      dynamic "tag" {
        for_each = { for t in filter.value.tags : t.name => t }
        content {
          name     = tag.value.name
          operator = tag.value.operator
          values   = tag.value.values
        }
      }
    }
  }
}

###############################################################
# Subscription Consumption Budget (when subscription_id set)
# Same name / notifications / filter / lock as the RG variant — a
# single module, two mutually-exclusive resources (see XOR validation).
###############################################################
resource "azurerm_consumption_budget_subscription" "this" {
  count = var.subscription_id != null ? 1 : 0

  name            = local.name
  subscription_id = local.subscription_scope
  amount          = var.amount
  time_grain      = var.time_grain

  time_period {
    start_date = var.start_date
    end_date   = var.end_date
  }

  dynamic "notification" {
    for_each = { for i, n in var.notifications : tostring(i) => n }
    content {
      enabled        = notification.value.enabled
      threshold      = notification.value.threshold
      operator       = notification.value.operator
      threshold_type = notification.value.threshold_type
      contact_emails = notification.value.contact_emails
      contact_groups = notification.value.contact_groups
      contact_roles  = notification.value.contact_roles
    }
  }

  dynamic "filter" {
    for_each = var.filter == null ? [] : [var.filter]
    content {
      dynamic "dimension" {
        for_each = { for d in filter.value.dimensions : d.name => d }
        content {
          name     = dimension.value.name
          operator = dimension.value.operator
          values   = dimension.value.values
        }
      }
      dynamic "tag" {
        for_each = { for t in filter.value.tags : t.name => t }
        content {
          name     = tag.value.name
          operator = tag.value.operator
          values   = tag.value.values
        }
      }
    }
  }
}

###############################################################
# RESOURCE: Management Lock (optional) — applies to whichever
# budget exists (scope resolved via local.budget_id).
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    budget = {
      scope      = local.budget_id
      lock_level = var.lock.kind
      name       = var.lock.name != null ? "${var.lock.name}-budget" : null
    }
  } : {}
}
