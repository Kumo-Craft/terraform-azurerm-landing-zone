###############################################################
# MODULE: ManagedHsm - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# Convention: mhsm-{acronym}-{env}-{region}[-{workload}]
#   e.g. mhsm-idt-prod-gwc   (workload optional — omitted here)
#
# NOTE: composed manually (not via ../Naming) because that submodule
# requires a mandatory `workload` segment, whereas the mHSM convention
# leaves workload optional. Same house pattern, `compact()` drops it.
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional explicit name (3-24 chars). If null, computed as mhsm-{acronym}-{env}-{region}[-{workload}]."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code` must be provided (workload is optional)."
  }

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]{2,23}$", var.name))
    error_message = "name must be 3 to 24 characters, alphanumeric + hyphens, and start with a letter."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. idt, con, sec)."

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)."

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)."

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Optional workload suffix segment. Null = omitted from the name (mhsm-{acr}-{env}-{region})."
  nullable    = true

  validation {
    condition     = var.workload == null || can(regex("^[a-z0-9][a-z0-9-]{0,20}$", var.workload))
    error_message = "workload must be 1 to 21 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the Managed HSM is deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group hosting the Managed HSM."
  nullable    = false
}

variable "admin_object_ids" {
  type        = list(string)
  description = "Entra ID object IDs of the initial Managed HSM administrators (Crypto Officer/User at the data plane). At least one required. Changing this forces a new resource."
  nullable    = false

  validation {
    condition     = length(var.admin_object_ids) >= 1
    error_message = "admin_object_ids must contain at least one object ID."
  }
}

###############################################################
# OPTIONAL
###############################################################
variable "tenant_id" {
  type        = string
  default     = null
  description = "Entra ID tenant ID for authenticating requests. Null = current tenant (data.azurerm_client_config)."
  nullable    = true
}

variable "sku_name" {
  type        = string
  default     = "Standard_B1"
  description = "Managed HSM SKU. Only Standard_B1 is available."

  validation {
    condition     = var.sku_name == "Standard_B1"
    error_message = "sku_name must be 'Standard_B1' (only supported value)."
  }
}

variable "soft_delete_retention_days" {
  type        = number
  default     = 90
  description = "Soft-delete retention window in days (7-90, default 90). Immutable once set. Soft-delete is always on for Managed HSM."
  nullable    = false

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = "Allow traffic from public networks. Default false (secure — reach it via Private Endpoint)."
  nullable    = false
}

variable "network_acls" {
  type = object({
    bypass         = optional(string, "AzureServices")
    default_action = optional(string, "Deny")
  })
  default     = {}
  nullable    = false
  description = "Network ACLs. bypass: AzureServices | None. default_action: Allow | Deny (default Deny — deny-by-default posture)."

  validation {
    condition     = contains(["AzureServices", "None"], var.network_acls.bypass)
    error_message = "network_acls.bypass must be 'AzureServices' or 'None'."
  }
  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls.default_action)
    error_message = "network_acls.default_action must be 'Allow' or 'Deny'."
  }
}

###############################################################
# LOCAL RBAC (data-plane role assignments)
#
# Managed HSM uses its OWN local RBAC at the data plane — separate from
# Azure RBAC. It stores ONLY keys (no secrets/certs), so roles are
# key-centric (Crypto User/Officer, Administrator, ...).
#
# IMPORTANT: these assignments require the HSM to be ACTIVATED first
# (security domain downloaded — an out-of-band step). On a fresh HSM they
# FAIL at create time. In practice apply them in a SECOND stage/apply once
# the HSM is activated. Default empty = none created.
###############################################################
variable "role_assignments" {
  type = map(object({
    principal_id         = string
    scope                = optional(string, "/keys") # "/" | "/keys" | "/keys/<key-name>"
    role_definition_name = optional(string)          # built-in role name (see below)
    role_definition_id   = optional(string)          # OR explicit role definition resource id (custom roles)
    name                 = optional(string)          # GUID; auto-generated (uuidv5) when null
  }))
  default     = {}
  nullable    = false
  description = <<-EOT
    Managed HSM LOCAL RBAC (data-plane) role assignments, keyed by an arbitrary
    stable key. Each entry sets EXACTLY ONE of role_definition_name (built-in)
    or role_definition_id (custom). Built-in role names:
      Managed HSM Administrator | Managed HSM Crypto Officer |
      Managed HSM Crypto User | Managed HSM Policy Administrator |
      Managed HSM Crypto Auditor | Managed HSM Crypto Service Encryption User |
      Managed HSM Crypto Service Release User | Managed HSM Backup | Managed HSM Restore
    scope: "/" (HSM-wide), "/keys" (all keys, default), or "/keys/<key-name>".
    REQUIRES the HSM to be activated (security domain) — typically a second apply.
  EOT

  validation {
    condition = alltrue([
      for r in var.role_assignments :
      (r.role_definition_name != null) != (r.role_definition_id != null)
    ])
    error_message = "Each role_assignments entry must set EXACTLY ONE of role_definition_name or role_definition_id."
  }

  validation {
    condition = alltrue([
      for r in var.role_assignments :
      r.role_definition_name == null || contains([
        "Managed HSM Administrator", "Managed HSM Crypto Officer", "Managed HSM Crypto User",
        "Managed HSM Policy Administrator", "Managed HSM Crypto Auditor",
        "Managed HSM Crypto Service Encryption User", "Managed HSM Crypto Service Release User",
        "Managed HSM Backup", "Managed HSM Restore",
      ], r.role_definition_name)
    ])
    error_message = "role_definition_name must be a Managed HSM built-in role (see variable description)."
  }

  validation {
    condition = alltrue([
      for r in var.role_assignments :
      r.scope == "/" || can(regex("^/keys(/[^/]+)?$", r.scope))
    ])
    error_message = "scope must be '/', '/keys', or '/keys/<key-name>'."
  }
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
  Optional Resource Lock. The resource also carries an unconditional
  `lifecycle.prevent_destroy` guard at the Terraform level — this variable
  adds a second, Azure-side guard that survives state loss/refresh.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Generated from kind if not specified.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply to the Managed HSM."
}
