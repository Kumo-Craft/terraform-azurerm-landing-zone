###############################################################
# MODULE: KeyVault - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# Key Vault name max 24 characters!
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit Key Vault name (3-24 chars). If null, computed from naming components."

  validation {
    condition     = var.name == null || (length(var.name) >= 3 && length(var.name) <= 24 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.name)))
    error_message = "Key Vault name must be 3-24 characters, start with a letter, end with a letter or digit, and contain only letters, digits, and hyphens."
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
  description = "Workload name for naming convention. Keep short (max 24 chars total name)."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9-]{0,15}$", var.workload))
    error_message = "workload must be 1 to 16 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the Key Vault will be deployed"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  nullable    = false
}

###############################################################
# KEY VAULT CONFIGURATION
###############################################################
variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID for the Key Vault (auto-detected if null)"
  default     = null

  validation {
    condition     = var.tenant_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.tenant_id))
    error_message = "Tenant ID must be a valid GUID format."
  }
}

variable "sku_name" {
  type        = string
  description = "SKU name: 'standard' or 'premium' (HSM-backed)"
  default     = "premium"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU must be 'standard' or 'premium'."
  }
}

variable "enable_rbac" {
  type        = bool
  description = "Enable RBAC authorization (recommended over access policies)"
  default     = true
}

variable "enabled_for_disk_encryption" {
  type        = bool
  description = "Enable Azure Disk Encryption to retrieve secrets and unwrap keys"
  default     = false
}

variable "enabled_for_deployment" {
  type        = bool
  description = "Enable VMs to retrieve certificates stored as secrets"
  default     = false
}

variable "enabled_for_template_deployment" {
  type        = bool
  description = "Enable ARM templates to retrieve secrets"
  default     = false
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Number of days to retain soft-deleted Key Vault (7-90)"
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "purge_protection_enabled" {
  type        = bool
  description = "Enable purge protection (IRREVERSIBLE once enabled)"
  default     = true
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Enable public network access (disable in production)"
  default     = false
}

variable "network_acls" {
  description = "Network ACLs configuration for Key Vault firewall"
  type = object({
    default_action = string
    bypass         = string
    ip_rules       = optional(list(string), [])
    subnet_ids     = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.network_acls == null || contains(["Allow", "Deny"], var.network_acls.default_action)
    error_message = "network_acls.default_action must be 'Allow' or 'Deny'."
  }

  validation {
    condition     = var.network_acls == null || contains(["AzureServices", "None"], var.network_acls.bypass)
    error_message = "network_acls.bypass must be 'AzureServices' or 'None'."
  }
}

###############################################################
# RBAC & ACCESS
###############################################################
variable "assign_rbac_to_current_user" {
  type        = bool
  default     = false
  description = <<-EOT
  Automatically assign `Key Vault Administrator` to the current deployer (the identity
  running `terraform apply`).

  **Default: false.** The recommended Azure-native pattern for a Landing Zone is to grant
  the Terraform service principal `Key Vault Administrator` inherited from the Management
  Group (or Subscription) scope ONCE, so it applies to every Key Vault deployed under that
  hierarchy without per-KV state pollution. See README "Prerequisites" section.

  Set to `true` only when:
  - The deployer cannot be granted inherited MG/Sub-level RBAC (least-privilege policy), AND
  - You need the deployer to manage child resources (keys, secrets, certs) in the same plan.

  Trade-off when `true`: every KV deployed by this module records an explicit role
  assignment for the deployer identity in state — auditability cost, and that identity
  remains admin on the KV permanently unless explicitly revoked.
  EOT
}

variable "role_assignments" {
  description = <<-EOT
  A map of role assignments to create on this Key Vault. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `role_definition_id_or_name`             - (Required) The ID or name of the role definition.
  - `principal_id`                           - (Required) The ID of the principal to assign the role to.
  - `principal_type`                         - (Optional) The type of principal. Values: User, Group, ServicePrincipal.
  - `condition`                              - (Optional) ABAC condition for the role assignment.
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
  Controls the Resource Lock configuration for this resource.

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
  description = "Tags to apply to the Key Vault"
  default     = {}
}
