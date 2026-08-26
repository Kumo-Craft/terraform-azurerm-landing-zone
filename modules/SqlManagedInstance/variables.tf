###############################################################
# MODULE: SqlManagedInstance - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name. If null, computed from naming components (sqlmi-{sub}-{env}-{region}-{workload})."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }

  validation {
    # SQL MI name: 1-63 chars, lowercase letters/digits/hyphens, no leading/trailing hyphen.
    condition     = var.name == null || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be 1-63 chars, lowercase letters/digits/hyphens, and must not start or end with a hyphen."
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

variable "subnet_id" {
  type        = string
  nullable    = false
  description = "REQUIRED. Resource ID of the DEDICATED subnet delegated to Microsoft.Sql/managedInstances (with the mandatory NSG + route table). SQL MI can only be deployed into such a subnet; the module does not create it."

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a valid Azure Subnet resource ID."
  }
}

###############################################################
# ADMIN AUTHENTICATION
# Provide SQL admin (login + password) and/or an Entra admin.
# At least one is required (enforced by a precondition in main.tf).
###############################################################
variable "administrator_login" {
  type        = string
  default     = null
  description = "SQL administrator login. Optional if an Entra admin with entra-only auth is configured. Cannot be changed after creation."
}

variable "administrator_login_password" {
  type        = string
  default     = null
  sensitive   = true
  description = "SQL administrator password. Required when administrator_login is set. Prefer sourcing from Key Vault."
}

variable "entra_administrator" {
  description = "Optional Microsoft Entra (Azure AD) administrator. Set azuread_authentication_only_enabled = true to disable SQL auth entirely."
  type = object({
    login_username                      = string
    object_id                           = string
    principal_type                      = string # User | Group | Application
    tenant_id                           = optional(string, null)
    azuread_authentication_only_enabled = optional(bool, false)
  })
  default = null

  validation {
    condition     = var.entra_administrator == null || contains(["User", "Group", "Application"], coalesce(try(var.entra_administrator.principal_type, null), "User"))
    error_message = "entra_administrator.principal_type must be one of User, Group, Application."
  }
}

###############################################################
# COMPUTE / STORAGE / LICENSING
###############################################################
variable "sku_name" {
  type        = string
  default     = "GP_Gen5"
  nullable    = false
  description = "SKU name. General Purpose (GP_*) or Business Critical (BC_*), e.g. GP_Gen5, BC_Gen5, GP_Gen8IM."

  validation {
    condition     = can(regex("^(GP|BC)_", var.sku_name))
    error_message = "sku_name must start with GP_ (General Purpose) or BC_ (Business Critical)."
  }
}

variable "vcores" {
  type        = number
  default     = 4
  nullable    = false
  description = "Number of vCores. Minimum 4."

  validation {
    condition     = var.vcores >= 4
    error_message = "vcores must be at least 4."
  }
}

variable "storage_size_in_gb" {
  type        = number
  default     = 32
  nullable    = false
  description = "Storage size in GB (32 to 16384)."

  validation {
    condition     = var.storage_size_in_gb >= 32 && var.storage_size_in_gb <= 16384
    error_message = "storage_size_in_gb must be between 32 and 16384."
  }
}

variable "license_type" {
  type        = string
  default     = "LicenseIncluded"
  nullable    = false
  description = "License model: LicenseIncluded (pay-as-you-go) or BasePrice (Azure Hybrid Benefit)."

  validation {
    condition     = contains(["LicenseIncluded", "BasePrice"], var.license_type)
    error_message = "license_type must be LicenseIncluded or BasePrice."
  }
}

variable "storage_account_type" {
  type        = string
  default     = "GRS"
  nullable    = false
  description = "Backup storage redundancy: LRS, ZRS, GRS, GZRS. Default GRS (geo-redundant backups)."

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.storage_account_type)
    error_message = "storage_account_type must be one of LRS, ZRS, GRS, GZRS."
  }
}

###############################################################
# NETWORK / SECURITY (secure-by-default)
###############################################################
variable "public_data_endpoint_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Whether the public data endpoint is enabled. Default false (private-only): connect via the delegated subnet or a Private Endpoint."
}

variable "minimum_tls_version" {
  type        = string
  default     = "1.2"
  nullable    = false
  description = "Minimum TLS version for connections. Default 1.2."

  validation {
    condition     = contains(["1.1", "1.2", "1.3"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be 1.1, 1.2, or 1.3."
  }
}

variable "proxy_override" {
  type        = string
  default     = null
  description = "Connection type: Default, Proxy, or Redirect. Null = provider default."

  validation {
    condition     = var.proxy_override == null || contains(["Default", "Proxy", "Redirect"], var.proxy_override)
    error_message = "proxy_override must be Default, Proxy, or Redirect."
  }
}

variable "zone_redundant_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Zone redundancy. Opt-in (default false): only supported on eligible tiers/regions and increases cost."
}

variable "collation" {
  type        = string
  default     = null
  description = "Server collation. Null = provider default (SQL_Latin1_General_CP1_CI_AS). Cannot be changed after creation."
}

variable "timezone_id" {
  type        = string
  default     = null
  description = "Time zone ID (e.g. 'W. Europe Standard Time'). Null = provider default (UTC). Cannot be changed after creation."
}

variable "maintenance_configuration_name" {
  type        = string
  default     = null
  description = "Optional maintenance window configuration name (e.g. SQL_WestEurope_MI_1)."
}

variable "dns_zone_partner_id" {
  type        = string
  default     = null
  description = "Optional. Resource ID of a partner MI to share the DNS zone with (failover group scenarios)."
}

###############################################################
# IDENTITY (for CMK/TDE, Entra auth)
###############################################################
variable "identity" {
  description = "Optional managed identity. type = SystemAssigned | UserAssigned | 'SystemAssigned, UserAssigned'. identity_ids required for UserAssigned."
  type = object({
    type         = string
    identity_ids = optional(list(string), null)
  })
  default = null

  validation {
    condition     = var.identity == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity.type)
    error_message = "identity.type must be SystemAssigned, UserAssigned, or 'SystemAssigned, UserAssigned'."
  }
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
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the Managed Instance. Set to null to skip."
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
  description = "Map of role assignments at the Managed Instance scope (delegated to ../RoleAssignment). Default principal_type='ServicePrincipal'."
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
