###############################################################
# MODULE: SqlManagedInstance - Main
# Description: Azure SQL Managed Instance (Microsoft.Sql/managedInstances),
#              secure-by-default (private-only, TLS 1.2).
#
# NETWORK PREREQUISITE (not created by this module): SQL MI can only be
# deployed into a DEDICATED subnet that is delegated to
# Microsoft.Sql/managedInstances and carries the mandatory NSG + route
# table (service-aided configuration). The caller supplies var.subnet_id.
# Attach private connectivity via the ../PrivateEndpoint module if needed.
###############################################################

###############################################################
# Naming Convention — house prefix `sqlmi-` + the Naming submodule's
# suffix (Azure/naming v0.4.3 has no managed-instance type, so we build
# manually, mirroring AzureMonitorWorkspace / ApplicationInsights).
# Convention: sqlmi-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    sqlmi-mgm-prod-frc-01
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
  # Single guarded local — module.naming["this"] only exists when var.name == null.
  name = var.name != null ? var.name : "sqlmi-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RESOURCE: SQL Managed Instance
###############################################################
resource "azurerm_mssql_managed_instance" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Dedicated, delegated subnet (see module header).
  subnet_id = var.subnet_id

  # Compute / storage / licensing.
  sku_name           = var.sku_name
  vcores             = var.vcores
  storage_size_in_gb = var.storage_size_in_gb
  license_type       = var.license_type

  storage_account_type = var.storage_account_type

  # SQL admin auth — only meaningful when Entra-only auth is off.
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_login_password

  # Secure-by-default network posture.
  public_data_endpoint_enabled = var.public_data_endpoint_enabled
  minimum_tls_version          = var.minimum_tls_version
  proxy_override               = var.proxy_override
  zone_redundant_enabled       = var.zone_redundant_enabled

  collation                      = var.collation
  timezone_id                    = var.timezone_id
  maintenance_configuration_name = var.maintenance_configuration_name
  dns_zone_partner_id            = var.dns_zone_partner_id

  dynamic "azure_active_directory_administrator" {
    for_each = var.entra_administrator != null ? [var.entra_administrator] : []
    content {
      login_username                      = azure_active_directory_administrator.value.login_username
      object_id                           = azure_active_directory_administrator.value.object_id
      principal_type                      = azure_active_directory_administrator.value.principal_type
      tenant_id                           = azure_active_directory_administrator.value.tenant_id
      azuread_authentication_only_enabled = azure_active_directory_administrator.value.azuread_authentication_only_enabled
    }
  }

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  tags = var.tags

  lifecycle {
    # SQL MI holds data and takes hours to (re)provision — guard against
    # accidental destroy, consistent with the other stateful modules.
    prevent_destroy = true

    # At least one administrator must be configured, otherwise CreateOrUpdate
    # is rejected. SQL admin (login + password) OR an Entra admin satisfies it.
    precondition {
      condition = (
        (var.administrator_login != null && var.administrator_login_password != null)
        || var.entra_administrator != null
      )
      error_message = "Configure an administrator: set administrator_login + administrator_login_password, and/or entra_administrator."
    }
  }
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_mssql_managed_instance.this.id
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

  scope                            = azurerm_mssql_managed_instance.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
