###############################################################
# MODULE: PostgreSqlFlexible - Main
# Description: Azure Database for PostgreSQL Flexible Server
#              (Microsoft.DBforPostgreSQL/flexibleServers) with
#              databases, firewall rules, server configurations,
#              optional Private Endpoints, identity/CMK, lock, RBAC.
#              Single Server is retired — this is the GA offering.
#
# NETWORKING (choose ONE):
#  A) VNet integration (private access): delegated_subnet_id +
#     private_dns_zone_id. No public endpoint. Immutable after create.
#  B) Public access + Private Endpoint: leave delegated_subnet_id null,
#     manage public_network_access_enabled + var.private_endpoints
#     (sub-resource "postgresqlServer").
###############################################################

###############################################################
# Naming Convention — house prefix `psql-` + the Naming submodule's
# suffix (mirrors AzureMonitorWorkspace / ServiceBus).
# Convention: psql-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:    psql-mgm-prod-frc-01
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
  name = var.name != null ? var.name : "psql-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RESOURCE: PostgreSQL Flexible Server
###############################################################
resource "azurerm_postgresql_flexible_server" "this" {
  # checkov:skip=CKV_AZURE_136: geo-redundant backups are exposed via
  # var.geo_redundant_backup_enabled (default false). Not forced by default
  # because they are IMMUTABLE after create, add cost, and are unsupported on
  # Burstable SKUs / some regions — forcing true would break those deployments.
  # Enable per workload (prod) by setting geo_redundant_backup_enabled = true.
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  version    = var.postgresql_version
  sku_name   = var.sku_name
  storage_mb = var.storage_mb

  # Only pass storage_tier when explicitly set (otherwise let the provider pick
  # the default tier for the storage size).
  storage_tier = var.storage_tier

  auto_grow_enabled            = var.auto_grow_enabled
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled
  zone                         = var.zone
  create_mode                  = var.create_mode

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  # Networking (VNet integration when set; else public + optional PE).
  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = var.private_dns_zone_id
  public_network_access_enabled = var.public_network_access_enabled

  dynamic "authentication" {
    for_each = var.authentication != null ? [var.authentication] : []
    content {
      password_auth_enabled         = authentication.value.password_auth_enabled
      active_directory_auth_enabled = authentication.value.active_directory_auth_enabled
      tenant_id                     = authentication.value.tenant_id
    }
  }

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  dynamic "customer_managed_key" {
    for_each = var.customer_managed_key != null ? [var.customer_managed_key] : []
    content {
      key_vault_key_id                     = customer_managed_key.value.key_vault_key_id
      primary_user_assigned_identity_id    = customer_managed_key.value.primary_user_assigned_identity_id
      geo_backup_key_vault_key_id          = customer_managed_key.value.geo_backup_key_vault_key_id
      geo_backup_user_assigned_identity_id = customer_managed_key.value.geo_backup_user_assigned_identity_id
    }
  }

  dynamic "high_availability" {
    for_each = var.high_availability != null ? [var.high_availability] : []
    content {
      mode                      = high_availability.value.mode
      standby_availability_zone = high_availability.value.standby_availability_zone
    }
  }

  dynamic "maintenance_window" {
    for_each = var.maintenance_window != null ? [var.maintenance_window] : []
    content {
      day_of_week  = maintenance_window.value.day_of_week
      start_hour   = maintenance_window.value.start_hour
      start_minute = maintenance_window.value.start_minute
    }
  }

  tags = var.tags

  lifecycle {
    # Server holds data; guard against accidental destroy.
    prevent_destroy = true

    # An administrator is required: SQL login+password OR Entra auth enabled.
    precondition {
      condition = (
        (var.administrator_login != null && var.administrator_password != null)
        || (var.authentication != null && var.authentication.active_directory_auth_enabled)
      )
      error_message = "Configure an administrator: administrator_login + administrator_password, and/or authentication.active_directory_auth_enabled = true."
    }

    # VNet integration mandates a private DNS zone (MS Learn requirement).
    precondition {
      condition     = var.delegated_subnet_id == null || var.private_dns_zone_id != null
      error_message = "private_dns_zone_id is mandatory when delegated_subnet_id is set (VNet integration)."
    }

    # PE and VNet integration are mutually exclusive networking models.
    precondition {
      condition     = var.delegated_subnet_id == null || length(var.private_endpoints) == 0
      error_message = "Do not combine delegated_subnet_id (VNet integration) with private_endpoints (public-access PE). Choose one networking model."
    }
  }
}

###############################################################
# RESOURCE: Databases
###############################################################
resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = var.databases

  name      = coalesce(each.value.name, each.key)
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = each.value.charset
  collation = each.value.collation

  # Databases hold data — guard against accidental destroy.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Firewall Rules (public-access mode)
###############################################################
resource "azurerm_postgresql_flexible_server_firewall_rule" "this" {
  for_each = var.firewall_rules

  name             = each.key
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

###############################################################
# RESOURCE: Server Configurations (server parameters)
###############################################################
resource "azurerm_postgresql_flexible_server_configuration" "this" {
  for_each = var.configurations

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = each.value
}

###############################################################
# RESOURCE: Private Endpoints — delegated to ../PrivateEndpoint
# Target sub-resource "postgresqlServer"; DNS zone
# privatelink.postgres.database.azure.com. Public-access mode only.
###############################################################
module "private_endpoint" {
  source   = "../PrivateEndpoint"
  for_each = var.private_endpoints

  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = each.value.subnet_id
  tags                = var.tags

  private_endpoints = {
    (each.key) = {
      name                          = coalesce(each.value.name, "pe-${local.name}-${each.key}")
      resource_id                   = azurerm_postgresql_flexible_server.this.id
      subresource_names             = ["postgresqlServer"]
      private_ip_address            = each.value.private_ip_address
      member_name                   = each.value.member_name
      custom_network_interface_name = each.value.custom_network_interface_name
      private_dns_zone_group = each.value.private_dns_zone_ids != null ? {
        private_dns_zone_ids = each.value.private_dns_zone_ids
      } : null
      tags = each.value.tags
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
      scope      = azurerm_postgresql_flexible_server.this.id
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

  scope                            = azurerm_postgresql_flexible_server.this.id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
