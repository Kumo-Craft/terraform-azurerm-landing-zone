###############################################################
# MODULE: Ampls - Main
# Description: Azure Monitor Private Link Scope with scoped
#              services and Private Endpoint
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
# monitor_private_link_scope is not a key in Azure/naming/azurerm 0.4.3,
# so we use the inline slug pattern: pls-{acr}-{env}-{region}-{workload}
# Example: pls-mgm-prod-gwc-management
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
  name = var.name != null ? var.name : "pls-${join("-", module.naming["this"].suffix)}"

  common_tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# Azure Monitor Private Link Scope
###############################################################
resource "azurerm_monitor_private_link_scope" "this" {
  name                  = local.name
  resource_group_name   = var.resource_group_name
  ingestion_access_mode = var.ingestion_access_mode
  query_access_mode     = var.query_access_mode
  tags                  = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# Scoped Services (LAW, Automation Account, etc.)
###############################################################
resource "azurerm_monitor_private_link_scoped_service" "this" {
  for_each = var.scoped_services

  name                = "ampls-${each.key}"
  resource_group_name = var.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = each.value.resource_id
}

###############################################################
# STATE MIGRATION: inline azurerm_private_endpoint moved to
# the ../PrivateEndpoint composition module in v0.2.63.
# The moved block ensures existing state is migrated
# automatically on the next plan — no manual state mv needed.
###############################################################
moved {
  from = azurerm_private_endpoint.this
  to   = module.private_endpoint.azurerm_private_endpoint.this["ampls"]
}

###############################################################
# Private Endpoint for AMPLS — composed via ../PrivateEndpoint
###############################################################
module "private_endpoint" {
  source = "../PrivateEndpoint"

  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_endpoints = {
    ampls = {
      name              = "pep-${local.name}"
      resource_id       = azurerm_monitor_private_link_scope.this.id
      subresource_names = ["azuremonitor"]
      private_dns_zone_group = {
        name                 = "default"
        private_dns_zone_ids = var.private_dns_zone_ids
      }
    }
  }

  tags = local.common_tags

  depends_on = [azurerm_monitor_private_link_scoped_service.this]
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_monitor_private_link_scope.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_monitor_private_link_scope.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
