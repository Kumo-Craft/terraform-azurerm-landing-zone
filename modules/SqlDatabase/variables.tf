###############################################################
# MODULE: SqlDatabase - Variables
# Deploys an Azure SQL logical server (Microsoft.Sql/servers) plus
# one or more databases. Secure-by-default: Entra-only auth, public
# network access off, TLS 1.2 floor, TDE on, PITR 7 days. Server auditing
# and DB zone-redundancy/ledger are opt-in (see var.auditing / databases).
###############################################################

###############################################################
# NAMING CONVENTION
# SQL logical server name is GLOBALLY unique (forms the
# <name>.database.windows.net FQDN). 1-63 chars, lowercase letters,
# digits and hyphens, must not start/end with a hyphen.
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit SQL logical server name (1-63 chars, globally unique). If null, computed from naming components (sql-{acr}-{env}-{region}-{workload})."

  validation {
    condition     = var.name == null || (length(var.name) >= 1 && length(var.name) <= 63 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name)))
    error_message = "Server name must be 1-63 chars, lowercase letters/digits/hyphens, and must not start or end with a hyphen."
  }

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (legacy resource), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym for naming convention (e.g. mgm, con, api)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment for naming convention (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code for naming convention (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name for naming convention. Keep short and unique (server name is global)."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9-]{0,29}$", var.workload))
    error_message = "workload must be 1 to 30 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the SQL server will be deployed"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  nullable    = false
}

###############################################################
# SERVER CONFIGURATION
###############################################################
variable "server_version" {
  type        = string
  description = "The version for the SQL logical server. Valid values: '12.0' (v12) or '2.0' (v11)."
  default     = "12.0"

  validation {
    condition     = contains(["12.0", "2.0"], var.server_version)
    error_message = "server_version must be '12.0' or '2.0'."
  }
}

variable "minimum_tls_version" {
  type        = string
  description = "Minimum TLS version for all databases on this server. Valid values: '1.0', '1.1', '1.2', 'Disabled'. Secure default is '1.2'."
  default     = "1.2"

  validation {
    condition     = contains(["1.0", "1.1", "1.2", "Disabled"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be one of '1.0', '1.1', '1.2', 'Disabled'."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Whether public network access is allowed. Secure default is false — connect via the separate PrivateEndpoint module."
  default     = false
}

variable "outbound_network_restriction_enabled" {
  type        = bool
  description = "Whether outbound network traffic is restricted for this server."
  default     = false
}

variable "connection_policy" {
  type        = string
  description = "Connection policy the server will use. Possible values: 'Default', 'Proxy', 'Redirect'."
  default     = "Default"

  validation {
    condition     = contains(["Default", "Proxy", "Redirect"], var.connection_policy)
    error_message = "connection_policy must be 'Default', 'Proxy' or 'Redirect'."
  }
}

variable "express_vulnerability_assessment_enabled" {
  type        = bool
  description = "Enable the Express (storage-less) SQL Vulnerability Assessment configuration. Secure default is true."
  default     = true
}

###############################################################
# AUDITING (server extended auditing policy)
# Secure-by-default: enabled = true, retention_in_days = 90
# (CKV_AZURE_23 auditing on, CKV_AZURE_24 retention >= 90 days).
#
# Server auditing REQUIRES a destination and this module will NOT
# fabricate one. Supply either:
#   - `log_analytics_workspace_id` (Azure Monitor — RECOMMENDED). The
#     module sets `log_monitoring_enabled = true` on the policy AND
#     creates the mandatory Diagnostic Setting (category
#     SQLSecurityAuditEvents) on the server's `master` database, which
#     Azure requires to actually route server-level audit events to the
#     workspace (per MS Learn auditingSettings guidance).
#   - `storage_endpoint` (blob storage). Storage auth uses the server's
#     managed identity (MS-recommended) — no storage access key is taken
#     to avoid persisting a secret in state.
#
# GRACEFUL DEGRADATION: if NO destination is supplied, the extended
# auditing policy is NOT created (count = 0) rather than failing the
# plan. In that case CKV_AZURE_23 / CKV_AZURE_24 remain OPEN until the
# landing zone supplies a Log Analytics workspace or storage endpoint.
###############################################################
variable "auditing" {
  description = <<-EOT
  Server extended auditing policy configuration (CKV_AZURE_23 / CKV_AZURE_24).

  - `enabled`                         - (Optional) Master switch. Defaults to true.
  - `retention_in_days`               - (Optional) Log retention in days. Must be >= 90. Defaults to 90.
  - `log_analytics_workspace_id`      - (Optional) LAW ARM resource ID. When set, audit events are routed to Azure Monitor (log_monitoring_enabled = true) and a Diagnostic Setting is created on the server `master` database (category SQLSecurityAuditEvents). RECOMMENDED destination.
  - `log_monitoring_enabled`          - (Optional) Send audit events to Azure Monitor. Forced to true when `log_analytics_workspace_id` is set. Defaults to true.
  - `storage_endpoint`               - (Optional) Blob storage endpoint (https://<account>.blob.core.windows.net) for storage-based auditing. Storage auth uses the server managed identity.
  - `storage_account_subscription_id` - (Optional) Subscription ID of the auditing storage account when it differs from the server subscription.
  - `audit_actions_and_groups`        - (Optional) Actions/action-groups to audit. Provider default when null.
  - `predicate_expression`            - (Optional) WHERE clause to filter audited events.
  - `diagnostic_setting_name`         - (Optional) Name of the master-database Diagnostic Setting created for the Azure Monitor route. Defaults to "sqlaudit-to-law".
  EOT
  type = object({
    enabled                         = optional(bool, true)
    retention_in_days               = optional(number, 90)
    log_analytics_workspace_id      = optional(string)
    log_monitoring_enabled          = optional(bool, true)
    storage_endpoint                = optional(string)
    storage_account_subscription_id = optional(string)
    audit_actions_and_groups        = optional(list(string))
    predicate_expression            = optional(string)
    diagnostic_setting_name         = optional(string, "sqlaudit-to-law")
  })
  default  = {}
  nullable = false

  # CKV_AZURE_24 / MCSB LT-6: retention must be at least 90 days. 0 (unlimited)
  # is intentionally disallowed because Checkov flags it as non-compliant.
  validation {
    condition     = var.auditing.retention_in_days >= 90
    error_message = "auditing.retention_in_days must be >= 90 (CKV_AZURE_24 / Microsoft cloud security benchmark LT-6)."
  }

  validation {
    condition     = var.auditing.log_analytics_workspace_id == null || can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.auditing.log_analytics_workspace_id))
    error_message = "auditing.log_analytics_workspace_id must be a valid Log Analytics Workspace ARM resource ID."
  }

  validation {
    condition     = var.auditing.storage_endpoint == null || can(regex("^https://[a-z0-9]+\\.blob\\.core\\.windows\\.net/?$", var.auditing.storage_endpoint))
    error_message = "auditing.storage_endpoint must be a blob endpoint like https://<account>.blob.core.windows.net."
  }
}

###############################################################
# AUTHENTICATION
# Secure default: Microsoft Entra-only authentication. Provide an
# `entra_administrator`; SQL local authentication is disabled.
###############################################################
variable "entra_administrator" {
  description = <<-EOT
  Microsoft Entra (Azure AD) administrator for the SQL server. Recommended for all
  deployments — centralises identity and supports `azuread_authentication_only`.

  - `login_username`               - (Required) Display name of the Entra principal (user/group/SP).
  - `object_id`                    - (Required) Object ID of the Entra principal.
  - `tenant_id`                    - (Optional) Tenant ID of the principal (defaults to the server tenant).
  - `azuread_authentication_only`  - (Optional) When true, only Entra principals can log in (SQL auth disabled). Defaults to true.
  EOT
  type = object({
    login_username              = string
    object_id                   = string
    tenant_id                   = optional(string)
    azuread_authentication_only = optional(bool, true)
  })
  default = null

  validation {
    condition     = var.entra_administrator == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", try(var.entra_administrator.object_id, "")))
    error_message = "entra_administrator.object_id must be a valid GUID."
  }

  # At least one administrator must exist. Azure rejects a server with neither an
  # Entra administrator nor a SQL local login + password.
  validation {
    condition = (
      var.entra_administrator != null
      || (var.administrator_login != null && var.administrator_login_password != null)
    )
    error_message = "Provide an `entra_administrator` (recommended) OR both `administrator_login` and `administrator_login_password` for SQL authentication."
  }
}

variable "administrator_login" {
  type        = string
  description = "SQL authentication administrator login. Only used when Entra-only authentication is disabled. Prefer Entra-only auth."
  default     = null
}

variable "administrator_login_password" {
  type        = string
  description = "Password for `administrator_login`. Only used when Entra-only authentication is disabled. Source it from Key Vault — it is stored in plain text in state."
  default     = null
  sensitive   = true
}

###############################################################
# MANAGED IDENTITY
# Default SystemAssigned — backs auditing, Defender, and CMK/TDE.
###############################################################
variable "identity" {
  description = <<-EOT
  Managed identity configuration for the SQL server.

  - `type`         - (Required) 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'.
  - `identity_ids` - (Optional) User Assigned Managed Identity IDs. Required when `type` includes 'UserAssigned'.
  EOT
  type = object({
    type         = string
    identity_ids = optional(list(string), [])
  })
  default = {
    type = "SystemAssigned"
  }

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity.type)
    error_message = "identity.type must be 'SystemAssigned', 'UserAssigned' or 'SystemAssigned, UserAssigned'."
  }

  validation {
    condition     = !can(regex("UserAssigned", var.identity.type)) || length(var.identity.identity_ids) > 0
    error_message = "identity.identity_ids must be set when identity.type includes 'UserAssigned'."
  }
}

variable "primary_user_assigned_identity_id" {
  type        = string
  description = "Primary user-assigned managed identity ID. Required when identity.type includes 'UserAssigned'."
  default     = null
}

variable "transparent_data_encryption_key_vault_key_id" {
  type        = string
  description = "Fully versioned Key Vault Key URL for TDE with a Customer-Managed Key (CMK/BYOK) at the server level. The KV must have soft-delete and purge protection enabled and share the server's tenant."
  default     = null
}

###############################################################
# FIREWALL
###############################################################
variable "allow_azure_services" {
  type        = bool
  description = "Create the special 0.0.0.0 firewall rule that allows Azure services and resources to access this server. Secure default is false."
  default     = false
}

variable "firewall_rules" {
  description = <<-EOT
  A map of SQL server firewall rules. The map key is the rule name.

  - `start_ip_address` - (Required) Start of the allowed IPv4 range.
  - `end_ip_address`   - (Required) End of the allowed IPv4 range.
  EOT
  type = map(object({
    start_ip_address = string
    end_ip_address   = string
  }))
  default  = {}
  nullable = false
}

###############################################################
# ELASTIC POOLS
###############################################################
variable "elastic_pools" {
  description = <<-EOT
  A map of elastic pools to create on this server. The map key is used as the pool
  name unless `name` is set. Reference a pool from a database entry via its
  `elastic_pool_key`.

  - `name`                  - Pool name (defaults to the map key).
  - `sku`                   - (Required) Compute SKU of the pool:
      - `name`     - (Required) e.g. 'GP_Gen5', 'BC_Gen5', 'HS_Gen5', 'StandardPool', 'PremiumPool'.
      - `tier`     - (Required) 'GeneralPurpose', 'BusinessCritical', 'Hyperscale', 'Basic', 'Standard', 'Premium'.
      - `capacity` - (Required) Pool compute units (vCores or DTUs).
      - `family`   - (Optional) Hardware family: 'Gen4', 'Gen5', 'Fsv2', 'DC', 'PRMS', 'MOPRMS'.
  - `per_database_settings` - (Required) Per-database min/max capacity guaranteed/allowed in the pool.
  - `max_size_gb` / `max_size_bytes` - Exactly one must be set (pool data cap).
  - `maintenance_configuration_name` - Public maintenance window.
  - `enclave_type`          - 'Default' or 'VBS'. All pooled databases must match.
  - `zone_redundant`        - Premium (DTU) / Business Critical (vCore) only.
  - `license_type`          - 'LicenseIncluded' or 'BasePrice'.
  - `high_availability_replica_count` - Hyperscale tier only (0-4).
  - `tags`                  - Per-pool tags (merged over the module tags).
  EOT
  type = map(object({
    name = optional(string)
    sku = object({
      name     = string
      tier     = string
      capacity = number
      family   = optional(string)
    })
    per_database_settings = object({
      min_capacity = number
      max_capacity = number
    })
    max_size_gb                     = optional(number)
    max_size_bytes                  = optional(number)
    maintenance_configuration_name  = optional(string)
    enclave_type                    = optional(string)
    zone_redundant                  = optional(bool)
    license_type                    = optional(string)
    high_availability_replica_count = optional(number)
    tags                            = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for p in var.elastic_pools : contains(["GeneralPurpose", "BusinessCritical", "Hyperscale", "Basic", "Standard", "Premium"], p.sku.tier)])
    error_message = "Each elastic pool sku.tier must be 'GeneralPurpose', 'BusinessCritical', 'Hyperscale', 'Basic', 'Standard' or 'Premium'."
  }

  validation {
    condition     = alltrue([for p in var.elastic_pools : (p.max_size_gb == null) != (p.max_size_bytes == null)])
    error_message = "Each elastic pool must set exactly one of max_size_gb or max_size_bytes."
  }

  validation {
    condition     = alltrue([for p in var.elastic_pools : p.enclave_type == null || contains(["Default", "VBS"], p.enclave_type)])
    error_message = "Each elastic pool enclave_type must be 'Default' or 'VBS'."
  }

  validation {
    condition     = alltrue([for p in var.elastic_pools : p.license_type == null || contains(["LicenseIncluded", "BasePrice"], p.license_type)])
    error_message = "Each elastic pool license_type must be 'LicenseIncluded' or 'BasePrice'."
  }

  validation {
    condition     = alltrue([for p in var.elastic_pools : p.high_availability_replica_count == null || (p.high_availability_replica_count >= 0 && p.high_availability_replica_count <= 4)])
    error_message = "Each elastic pool high_availability_replica_count must be between 0 and 4."
  }
}

###############################################################
# DATABASES
###############################################################
variable "databases" {
  description = <<-EOT
  A map of databases to create on this server. The map key is used as the database
  name unless `name` is set. Every database is created with `prevent_destroy = true`
  to guard against accidental data loss.

  Common fields (all optional unless noted):
  - `name`                 - Database name (defaults to the map key).
  - `sku_name`             - SKU (e.g. 'GP_S_Gen5_2', 'S0', 'BC_Gen5_2', 'HS_Gen5_2'). Defaults to 'GP_S_Gen5_2' (General Purpose serverless).
  - `collation`            - Database collation. Defaults to 'SQL_Latin1_General_CP1_CI_AS'.
  - `max_size_gb`          - Max size in GB.
  - `license_type`         - 'LicenseIncluded' or 'BasePrice'.
  - `zone_redundant`       - Spread replicas across availability zones. OPT-IN, defaults to false (CKV_AZURE_229). Set true where supported; fails at apply on Basic/Standard S0-S2 SKUs, non-AZ regions, or pooled DBs whose pool is not zone-redundant.
  - `read_scale`           - Route readonly intent to a replica (Premium / Business Critical).
  - `read_replica_count`   - Hyperscale readonly replica count.
  - `auto_pause_delay_in_minutes` / `min_capacity` - Serverless only.
  - `storage_account_type` - Backup storage redundancy: 'Geo' (default), 'GeoZone', 'Local', 'Zone'.
  - `geo_backup_enabled`   - DataWarehouse SKUs only.
  - `maintenance_configuration_name` - Public maintenance window.
  - `ledger_enabled`       - Create as a ledger (tamper-evident) database. OPT-IN, defaults to false (CKV_AZURE_224). IRREVERSIBLE — cannot be turned off after creation. Set true for workloads needing cryptographic proof / non-repudiation.
  - `enclave_type`         - 'Default' or 'VBS' (Always Encrypted secure enclaves).
  - `transparent_data_encryption_enabled` - TDE at-rest. Defaults to true.
  - `transparent_data_encryption_key_vault_key_id` / `transparent_data_encryption_key_automatic_rotation_enabled` - Database-level CMK.
  - `create_mode` / `creation_source_database_id` - Advanced placement / restore.
  - `elastic_pool_key` - Place this database into a pool created by this module (key in `elastic_pools`). Mutually exclusive with `elastic_pool_id`.
  - `elastic_pool_id`  - Place this database into a pre-existing external elastic pool (full resource ID).
  - `short_term_retention_days` (1-35, default 7) / `backup_interval_in_hours` (12 or 24) - PITR.
  - `long_term_retention_policy` - LTR (weekly/monthly/yearly ISO-8601 retention).
  - `tags`                 - Per-database tags (merged over the module tags).
  EOT
  type = map(object({
    name         = optional(string)
    sku_name     = optional(string, "GP_S_Gen5_2")
    collation    = optional(string, "SQL_Latin1_General_CP1_CI_AS")
    max_size_gb  = optional(number)
    license_type = optional(string)
    # OPT-IN (CKV_AZURE_229). Default false: zone redundancy fails at apply on
    # SKUs/regions without Availability Zone support (Basic, Standard S0-S2,
    # non-AZ regions) and on pooled DBs whose pool is not itself zone-redundant.
    # Set true per-database to enable the resilient path where supported.
    zone_redundant                 = optional(bool, false)
    read_scale                     = optional(bool)
    read_replica_count             = optional(number)
    auto_pause_delay_in_minutes    = optional(number)
    min_capacity                   = optional(number)
    storage_account_type           = optional(string)
    geo_backup_enabled             = optional(bool)
    maintenance_configuration_name = optional(string)
    # OPT-IN (CKV_AZURE_224). Default false because ledger is IRREVERSIBLE — it
    # cannot be disabled after creation and cannot be applied to an existing
    # non-ledger database (forces replacement, and these DBs carry prevent_destroy).
    # Set true per-database for workloads needing cryptographic proof / non-repudiation.
    ledger_enabled                                             = optional(bool, false)
    enclave_type                                               = optional(string)
    create_mode                                                = optional(string)
    creation_source_database_id                                = optional(string)
    elastic_pool_id                                            = optional(string)
    elastic_pool_key                                           = optional(string)
    transparent_data_encryption_enabled                        = optional(bool, true)
    transparent_data_encryption_key_vault_key_id               = optional(string)
    transparent_data_encryption_key_automatic_rotation_enabled = optional(bool)
    short_term_retention_days                                  = optional(number, 7)
    backup_interval_in_hours                                   = optional(number)
    long_term_retention_policy = optional(object({
      weekly_retention          = optional(string)
      monthly_retention         = optional(string)
      yearly_retention          = optional(string)
      week_of_year              = optional(number)
      immutable_backups_enabled = optional(bool)
    }))
    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for db in var.databases : db.license_type == null || contains(["LicenseIncluded", "BasePrice"], db.license_type)])
    error_message = "Each database license_type must be 'LicenseIncluded' or 'BasePrice'."
  }

  validation {
    condition     = alltrue([for db in var.databases : db.storage_account_type == null || contains(["Geo", "GeoZone", "Local", "Zone"], db.storage_account_type)])
    error_message = "Each database storage_account_type must be 'Geo', 'GeoZone', 'Local' or 'Zone'."
  }

  validation {
    condition     = alltrue([for db in var.databases : db.enclave_type == null || contains(["Default", "VBS"], db.enclave_type)])
    error_message = "Each database enclave_type must be 'Default' or 'VBS'."
  }

  validation {
    condition     = alltrue([for db in var.databases : db.short_term_retention_days == null || (db.short_term_retention_days >= 1 && db.short_term_retention_days <= 35)])
    error_message = "Each database short_term_retention_days must be between 1 and 35."
  }

  validation {
    condition     = alltrue([for db in var.databases : db.backup_interval_in_hours == null || contains([12, 24], db.backup_interval_in_hours)])
    error_message = "Each database backup_interval_in_hours must be 12 or 24."
  }

  validation {
    condition     = alltrue([for db in var.databases : !(db.elastic_pool_key != null && db.elastic_pool_id != null)])
    error_message = "A database cannot set both elastic_pool_key (in-module pool) and elastic_pool_id (external pool)."
  }

  validation {
    condition     = alltrue([for db in var.databases : db.elastic_pool_key == null || contains(keys(var.elastic_pools), coalesce(db.elastic_pool_key, "_"))])
    error_message = "Each database elastic_pool_key must match a key defined in var.elastic_pools."
  }
}

###############################################################
# PRIVATE ENDPOINTS
# Delegated to the in-repo PrivateEndpoint submodule. Target
# sub-resource is always "sqlServer"; the private DNS zone is
# privatelink.database.windows.net.
###############################################################
variable "private_endpoints" {
  description = <<-EOT
  A map of Private Endpoints to create for this SQL logical server. The map key is
  arbitrary. Each endpoint targets the server with sub-resource `sqlServer` and resolves
  to `<server>.privatelink.database.windows.net`.

  - `subnet_id`                     - (Required) Subnet ID where the Private Endpoint NIC lands.
  - `name`                          - (Optional) PE name. Defaults to `pe-{server_name}-{key}`.
  - `private_dns_zone_ids`          - (Optional) Private DNS zone IDs for `privatelink.database.windows.net`. Omit when DNS is wired by an ALZ DINE policy (the PrivateEndpoint module ignores drift on the zone group).
  - `private_ip_address`            - (Optional) Static private IPv4 address (dynamic when null).
  - `member_name`                   - (Optional) IP config member name. Defaults to "default".
  - `custom_network_interface_name` - (Optional) Custom NIC name.
  - `tags`                          - (Optional) Per-endpoint tags (merged over the module tags).
  EOT
  type = map(object({
    subnet_id                     = string
    name                          = optional(string)
    private_dns_zone_ids          = optional(list(string))
    private_ip_address            = optional(string)
    member_name                   = optional(string, "default")
    custom_network_interface_name = optional(string)
    tags                          = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for pe in var.private_endpoints : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", pe.subnet_id))])
    error_message = "Each private endpoint subnet_id must be a valid subnet resource ID."
  }

  validation {
    condition     = alltrue([for pe in var.private_endpoints : pe.private_ip_address == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", pe.private_ip_address))])
    error_message = "Each private endpoint private_ip_address must be a valid IPv4 address."
  }
}

###############################################################
# RBAC & ACCESS
###############################################################
variable "role_assignments" {
  description = <<-EOT
  A map of role assignments to create on this SQL server. The map key is arbitrary.

  - `role_definition_id_or_name`             - (Required) The ID or name of the role definition.
  - `principal_id`                           - (Required) The ID of the principal to assign the role to.
  - `principal_type`                         - (Optional) User, Group or ServicePrincipal.
  - `condition`                              - (Optional) ABAC condition.
  - `condition_version`                      - (Optional) Condition version ("1.0" or "2.0").
  - `description`                            - (Optional) Description of the role assignment.
  - `skip_service_principal_aad_check`       - (Optional) Skip AAD check for the service principal.
  - `delegated_managed_identity_resource_id` - (Optional) Delegated managed identity for cross-tenant scenarios.
  EOT
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    principal_type                         = optional(string)
    condition                              = optional(string)
    condition_version                      = optional(string)
    description                            = optional(string)
    skip_service_principal_aad_check       = optional(bool, false)
    delegated_managed_identity_resource_id = optional(string)
  }))
  default  = {}
  nullable = false
}

###############################################################
# LOCK
###############################################################
variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Controls the Resource Lock configuration for this server.

  - `kind` - (Required) The type of lock. Possible values are "CanNotDelete" and "ReadOnly".
  - `name` - (Optional) The name of the lock. If not specified, generated from the kind value.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags to apply to the SQL server and databases"
  default     = {}
}
