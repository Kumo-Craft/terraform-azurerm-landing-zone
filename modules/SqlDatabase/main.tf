###############################################################
# MODULE: SqlDatabase - Main
# Description: Azure SQL logical server (Microsoft.Sql/servers) plus
#              one or more databases, with secure-by-default network,
#              auth, encryption and backup settings.
# Note: Use the separate PrivateEndpoint module to attach a Private
#       Endpoint (target sub-resource "sqlServer").
###############################################################

resource "time_static" "time" {}

data "azurerm_client_config" "current" {}

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule
# (wrapper around Azure/naming/azurerm).
#
# Convention:
#   sql-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example:
#   sql-api-prod-gwc-billing
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
  server_name = var.name != null ? var.name : module.naming["this"].result.mssql_server.name

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # -----------------------------------------------------------------
  # Auditing destination resolution (CKV_AZURE_23 / CKV_AZURE_24).
  # A destination exists when a Log Analytics workspace (Azure Monitor
  # route) OR a storage endpoint is supplied. Without a destination the
  # extended auditing policy would be invalid, so it degrades to count=0.
  # -----------------------------------------------------------------
  audit_to_monitor      = var.auditing.log_analytics_workspace_id != null
  audit_has_destination = var.auditing.log_analytics_workspace_id != null || var.auditing.storage_endpoint != null
  audit_enabled         = var.auditing.enabled && local.audit_has_destination
}

###############################################################
# RESOURCE: SQL Logical Server
###############################################################
resource "azurerm_mssql_server" "this" {
  name                = local.server_name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.server_version

  # SQL local authentication — only honoured when Entra-only auth is off.
  administrator_login          = var.administrator_login
  administrator_login_password = var.administrator_login_password

  minimum_tls_version                      = var.minimum_tls_version
  public_network_access_enabled            = var.public_network_access_enabled
  outbound_network_restriction_enabled     = var.outbound_network_restriction_enabled
  connection_policy                        = var.connection_policy
  express_vulnerability_assessment_enabled = var.express_vulnerability_assessment_enabled

  primary_user_assigned_identity_id            = var.primary_user_assigned_identity_id
  transparent_data_encryption_key_vault_key_id = var.transparent_data_encryption_key_vault_key_id

  dynamic "azuread_administrator" {
    for_each = var.entra_administrator != null ? [var.entra_administrator] : []
    content {
      login_username              = azuread_administrator.value.login_username
      object_id                   = azuread_administrator.value.object_id
      tenant_id                   = azuread_administrator.value.tenant_id
      azuread_authentication_only = azuread_administrator.value.azuread_authentication_only
    }
  }

  dynamic "identity" {
    for_each = var.identity != null ? [var.identity] : []
    content {
      type         = identity.value.type
      identity_ids = identity.value.identity_ids
    }
  }

  tags = local.tags
}

###############################################################
# RESOURCE: SQL Server Extended Auditing Policy
# Secure-by-default server auditing (CKV_AZURE_23 auditing on,
# CKV_AZURE_24 retention >= 90 days).
#
# NOTE (graceful degradation): auditing needs a destination and this
# module will not fabricate one. When neither `auditing.log_analytics_
# workspace_id` nor `auditing.storage_endpoint` is provided, count = 0
# and the policy is not created — CKV_AZURE_23/24 then remain OPEN until
# the landing zone supplies a target. This is intentional: creating the
# policy with no destination is rejected by the provider.
###############################################################
resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  # checkov:skip=CKV_AZURE_23
  # checkov:skip=CKV_AZURE_24: server auditing is exposed via var.auditing (Log Analytics / storage endpoint) with retention>=90 default; not forced by default because it requires an LZ-supplied destination — enabled by supplying auditing.log_analytics_workspace_id or storage_endpoint.
  count = local.audit_enabled ? 1 : 0

  server_id         = azurerm_mssql_server.this.id
  enabled           = true
  retention_in_days = var.auditing.retention_in_days

  # Azure Monitor route is forced on when a LAW is supplied; otherwise the
  # caller's preference is honoured (provider default is true).
  log_monitoring_enabled = local.audit_to_monitor ? true : var.auditing.log_monitoring_enabled

  # Storage route (managed-identity auth — no access key persisted in state).
  storage_endpoint                = var.auditing.storage_endpoint
  storage_account_subscription_id = var.auditing.storage_account_subscription_id

  audit_actions_and_groups = var.auditing.audit_actions_and_groups
  predicate_expression     = var.auditing.predicate_expression
}

###############################################################
# RESOURCE: Diagnostic Setting for server-level audit events
# Azure requires a Diagnostic Setting with the SQLSecurityAuditEvents
# category on the server's `master` database to actually route
# server-level audit events to a Log Analytics workspace (per MS Learn
# Microsoft.Sql/servers/databases/auditingSettings guidance). Only
# created for the Azure Monitor (LAW) route.
###############################################################
resource "azurerm_monitor_diagnostic_setting" "sql_audit" {
  count = local.audit_enabled && local.audit_to_monitor ? 1 : 0

  name                       = var.auditing.diagnostic_setting_name
  target_resource_id         = "${azurerm_mssql_server.this.id}/databases/master"
  log_analytics_workspace_id = var.auditing.log_analytics_workspace_id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }
}

###############################################################
# RESOURCE: SQL Server Firewall Rules
###############################################################
# Special rule: allow Azure services (start/end 0.0.0.0).
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  count = var.allow_azure_services ? 1 : 0

  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "this" {
  for_each = var.firewall_rules

  name             = each.key
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = each.value.start_ip_address
  end_ip_address   = each.value.end_ip_address
}

###############################################################
# RESOURCE: SQL Elastic Pools
###############################################################
resource "azurerm_mssql_elasticpool" "this" {
  for_each = var.elastic_pools

  name                = coalesce(each.value.name, each.key)
  resource_group_name = var.resource_group_name
  location            = var.location
  server_name         = azurerm_mssql_server.this.name

  max_size_gb                     = each.value.max_size_gb
  max_size_bytes                  = each.value.max_size_bytes
  maintenance_configuration_name  = each.value.maintenance_configuration_name
  enclave_type                    = each.value.enclave_type
  zone_redundant                  = each.value.zone_redundant
  license_type                    = each.value.license_type
  high_availability_replica_count = each.value.high_availability_replica_count

  sku {
    name     = each.value.sku.name
    tier     = each.value.sku.tier
    capacity = each.value.sku.capacity
    family   = each.value.sku.family
  }

  per_database_settings {
    min_capacity = each.value.per_database_settings.min_capacity
    max_capacity = each.value.per_database_settings.max_capacity
  }

  tags = merge(local.tags, each.value.tags)
}

###############################################################
# RESOURCE: SQL Databases
###############################################################
resource "azurerm_mssql_database" "this" {
  # checkov:skip=CKV_AZURE_224: ledger exposed via optional var (default false / opt-in) because ledger is IRREVERSIBLE and forces replacement of existing databases (which carry prevent_destroy).
  # checkov:skip=CKV_AZURE_229: zone_redundant exposed via optional var (default false / opt-in) because it fails apply on non-AZ SKUs (Basic/low Standard) and non-AZ regions.
  for_each = var.databases

  name      = coalesce(each.value.name, each.key)
  server_id = azurerm_mssql_server.this.id

  # Pool placement: in-module pool (elastic_pool_key) takes precedence,
  # otherwise an external pool ID, otherwise a standalone database.
  elastic_pool_id = each.value.elastic_pool_key != null ? azurerm_mssql_elasticpool.this[each.value.elastic_pool_key].id : each.value.elastic_pool_id

  sku_name       = each.value.sku_name
  collation      = each.value.collation
  max_size_gb    = each.value.max_size_gb
  license_type   = each.value.license_type
  zone_redundant = each.value.zone_redundant

  read_scale                  = each.value.read_scale
  read_replica_count          = each.value.read_replica_count
  auto_pause_delay_in_minutes = each.value.auto_pause_delay_in_minutes
  min_capacity                = each.value.min_capacity

  storage_account_type           = each.value.storage_account_type
  geo_backup_enabled             = each.value.geo_backup_enabled
  maintenance_configuration_name = each.value.maintenance_configuration_name
  ledger_enabled                 = each.value.ledger_enabled
  enclave_type                   = each.value.enclave_type

  create_mode                 = each.value.create_mode
  creation_source_database_id = each.value.creation_source_database_id

  transparent_data_encryption_enabled                        = each.value.transparent_data_encryption_enabled
  transparent_data_encryption_key_vault_key_id               = each.value.transparent_data_encryption_key_vault_key_id
  transparent_data_encryption_key_automatic_rotation_enabled = each.value.transparent_data_encryption_key_automatic_rotation_enabled

  short_term_retention_policy {
    retention_days           = each.value.short_term_retention_days
    backup_interval_in_hours = each.value.backup_interval_in_hours
  }

  dynamic "long_term_retention_policy" {
    for_each = each.value.long_term_retention_policy != null ? [each.value.long_term_retention_policy] : []
    content {
      weekly_retention          = long_term_retention_policy.value.weekly_retention
      monthly_retention         = long_term_retention_policy.value.monthly_retention
      yearly_retention          = long_term_retention_policy.value.yearly_retention
      week_of_year              = long_term_retention_policy.value.week_of_year
      immutable_backups_enabled = long_term_retention_policy.value.immutable_backups_enabled
    }
  }

  tags = merge(local.tags, each.value.tags)

  # Guard against accidental data loss — strongly recommended by the provider.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_mssql_server.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
###############################################################
module "role_assignments" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                                  = azurerm_mssql_server.this.id
  role_definition_id_or_name             = each.value.role_definition_id_or_name
  principal_id                           = each.value.principal_id
  principal_type                         = each.value.principal_type
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
}

###############################################################
# RESOURCE: Private Endpoints — delegated to ../PrivateEndpoint
# Target sub-resource "sqlServer"; DNS zone
# privatelink.database.windows.net.
###############################################################
module "private_endpoint" {
  source   = "../PrivateEndpoint"
  for_each = var.private_endpoints

  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = each.value.subnet_id
  tags                = local.tags

  private_endpoints = {
    (each.key) = {
      name                          = coalesce(each.value.name, "pe-${local.server_name}-${each.key}")
      resource_id                   = azurerm_mssql_server.this.id
      subresource_names             = ["sqlServer"]
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
