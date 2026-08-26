###############################################################
# MODULE: PostgreSqlFlexible - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit server name. If null, computed (psql-{sub}-{env}-{region}-{workload}). Globally unique, 3-63 lowercase alphanumerics/hyphens."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "name must be 3-63 chars, lowercase letters/digits/hyphens, not starting or ending with a hyphen."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. mgm, con)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, frc)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = "01"
  nullable    = false
  description = "Workload suffix (e.g. 01)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  nullable    = false
}

###############################################################
# SERVER SETTINGS
###############################################################
variable "postgresql_version" {
  type        = string
  default     = "16"
  nullable    = false
  description = "PostgreSQL major version."

  validation {
    condition     = contains(["11", "12", "13", "14", "15", "16", "17"], var.postgresql_version)
    error_message = "postgresql_version must be one of 11, 12, 13, 14, 15, 16, 17."
  }
}

variable "sku_name" {
  type        = string
  default     = "GP_Standard_D2s_v3"
  nullable    = false
  description = "Compute SKU. Prefix B_ (Burstable), GP_ (General Purpose) or MO_ (Memory Optimized), e.g. GP_Standard_D2s_v3, B_Standard_B1ms."

  validation {
    condition     = can(regex("^(B|GP|MO)_", var.sku_name))
    error_message = "sku_name must start with B_ (Burstable), GP_ (General Purpose), or MO_ (Memory Optimized)."
  }
}

variable "storage_mb" {
  type        = number
  default     = 32768
  nullable    = false
  description = "Storage size in MB (e.g. 32768 = 32 GB). Allowed tiers per MS docs (32768, 65536, 131072, ...)."
}

variable "storage_tier" {
  type        = string
  default     = null
  description = "Optional storage performance tier (e.g. P4, P6, P10...). Null = provider default for the storage size."
}

variable "auto_grow_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Auto-grow storage when near capacity. Default true (avoids out-of-storage outages)."
}

variable "backup_retention_days" {
  type        = number
  default     = 7
  nullable    = false
  description = "Backup retention in days (7-35)."

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "geo_redundant_backup_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Geo-redundant backups. Opt-in (default false): immutable after create and adds cost."
}

variable "zone" {
  type        = string
  default     = null
  description = "Availability zone for the primary (1/2/3). Null = platform choice."
}

variable "create_mode" {
  type        = string
  default     = null
  description = "Create mode: Default, PointInTimeRestore, Replica, Update. Null = Default."
}

###############################################################
# ADMIN AUTHENTICATION
###############################################################
variable "administrator_login" {
  type        = string
  default     = null
  description = "SQL administrator login. Required unless Entra-only auth (authentication.password_auth_enabled=false + active_directory_auth_enabled=true). Immutable after create."
}

variable "administrator_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "SQL administrator password. Required when administrator_login is set. Prefer sourcing from Key Vault."
}

variable "authentication" {
  description = "Authentication modes. Set active_directory_auth_enabled=true for Entra auth; password_auth_enabled=false to disable SQL password auth (Entra-only)."
  type = object({
    password_auth_enabled         = optional(bool, true)
    active_directory_auth_enabled = optional(bool, false)
    tenant_id                     = optional(string, null)
  })
  default = null
}

###############################################################
# NETWORKING
# Two mutually-exclusive models:
#  A) VNet integration (private access): delegated_subnet_id + private_dns_zone_id
#  B) Public access + Private Endpoint: public_network_access_enabled + private_endpoints
###############################################################
variable "delegated_subnet_id" {
  type        = string
  default     = null
  description = "VNet-integration mode. Resource ID of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. Requires private_dns_zone_id. Immutable after create."

  validation {
    condition     = var.delegated_subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.delegated_subnet_id))
    error_message = "delegated_subnet_id must be a valid Azure Subnet resource ID."
  }
}

variable "private_dns_zone_id" {
  type        = string
  default     = null
  description = "Private DNS zone ID for VNet-integration mode (privatelink.postgres.database.azure.com, or any zone ending in postgres.database.azure.com). Mandatory when delegated_subnet_id is set."
}

variable "public_network_access_enabled" {
  type        = bool
  default     = null
  description = "Public network access. Null = provider default. Must be omitted/false with delegated_subnet_id (VNet integration). For public+PE, set as needed."
}

###############################################################
# HIGH AVAILABILITY / MAINTENANCE
###############################################################
variable "high_availability" {
  description = "Optional high availability. mode = ZoneRedundant | SameZone."
  type = object({
    mode                      = string
    standby_availability_zone = optional(string, null)
  })
  default = null

  validation {
    condition     = var.high_availability == null || contains(["ZoneRedundant", "SameZone"], var.high_availability.mode)
    error_message = "high_availability.mode must be ZoneRedundant or SameZone."
  }
}

variable "maintenance_window" {
  description = "Optional maintenance window (UTC). day_of_week 0-6 (0=Sunday)."
  type = object({
    day_of_week  = optional(number, 0)
    start_hour   = optional(number, 0)
    start_minute = optional(number, 0)
  })
  default = null
}

###############################################################
# IDENTITY / CMK
###############################################################
variable "identity" {
  description = "Optional user-assigned identity (required for CMK). type must be UserAssigned."
  type = object({
    type         = string
    identity_ids = list(string)
  })
  default = null

  validation {
    condition     = var.identity == null || var.identity.type == "UserAssigned"
    error_message = "identity.type must be UserAssigned (PostgreSQL Flexible Server does not support SystemAssigned)."
  }
}

variable "customer_managed_key" {
  description = "Optional CMK encryption. Requires a user-assigned identity (var.identity) with access to the Key Vault key."
  type = object({
    key_vault_key_id                     = string
    primary_user_assigned_identity_id    = optional(string, null)
    geo_backup_key_vault_key_id          = optional(string, null)
    geo_backup_user_assigned_identity_id = optional(string, null)
  })
  default = null
}

###############################################################
# ENTITIES: DATABASES / FIREWALL RULES / CONFIGURATIONS
###############################################################
variable "databases" {
  description = "Map of databases to create. Key is the database name unless `name` is set."
  type = map(object({
    name      = optional(string, null)
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.utf8")
  }))
  default  = {}
  nullable = false
}

variable "firewall_rules" {
  description = "Map of firewall rules (public-access mode). Key is the rule name."
  type = map(object({
    start_ip_address = string
    end_ip_address   = string
  }))
  default  = {}
  nullable = false
}

variable "configurations" {
  description = "Map of server parameters (name => value), e.g. { require_secure_transport = \"on\", log_min_duration_statement = \"1000\" }."
  type        = map(string)
  default     = {}
  nullable    = false
}

###############################################################
# PRIVATE ENDPOINTS (embedded ../PrivateEndpoint — SqlDatabase pattern)
###############################################################
variable "private_endpoints" {
  description = <<-EOT
  Map of Private Endpoints (public-access mode) delegated to ../PrivateEndpoint.
  Each endpoint targets the server with sub-resource `postgresqlServer` and
  resolves via `privatelink.postgres.database.azure.com`. Do NOT combine with
  delegated_subnet_id (VNet integration already provides private access).

  - `subnet_id`                     - (Required) Subnet ID where the PE NIC lands.
  - `name`                          - (Optional) PE name. Defaults to `pe-{server}-{key}`.
  - `private_dns_zone_ids`          - (Optional) Private DNS zone IDs for privatelink.postgres.database.azure.com.
  - `private_ip_address`            - (Optional) Static private IPv4 (dynamic when null).
  - `member_name`                   - (Optional) IP config member name. Defaults to "postgresqlServer".
  - `custom_network_interface_name` - (Optional) Custom NIC name.
  - `tags`                          - (Optional) Per-endpoint tags.
  EOT
  type = map(object({
    subnet_id                     = string
    name                          = optional(string)
    private_dns_zone_ids          = optional(list(string))
    private_ip_address            = optional(string)
    member_name                   = optional(string, "postgresqlServer")
    custom_network_interface_name = optional(string)
    tags                          = optional(map(string), {})
  }))
  default  = {}
  nullable = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}

###############################################################
# RESOURCE LOCK
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the server. Set to null to skip."
  type = object({
    kind = string
    name = optional(string, null)
  })
  default  = null
  nullable = true

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], coalesce(var.lock != null ? var.lock.kind : null, "CanNotDelete"))
    error_message = "lock.kind must be 'CanNotDelete' or 'ReadOnly'."
  }
}

###############################################################
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the server scope (delegated to ../RoleAssignment). Default principal_type='ServicePrincipal'."
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string, "ServicePrincipal")
    condition                        = optional(string, null)
    condition_version                = optional(string, null)
    description                      = optional(string, null)
    skip_service_principal_aad_check = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)])
    error_message = "Each role_assignments[*].principal_type must be one of User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}
