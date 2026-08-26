###############################################################
# MODULE: KeyVaultStack - Variables
# Composes Key Vault + Private Endpoint (via ../KeyVault and
# ../PrivateEndpoint). The Resource Group is caller-provided
# (var.resource_group_name) — same convention as every other
# leaf module in the repo since v0.2.1.
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "subscription_acronym" {
  type        = string
  description = "Subscription acronym for naming convention (e.g. api, mgm, con)"

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  description = "Environment for naming convention (e.g. prod, nprd)"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  description = "Region code for naming convention (e.g. gwc, weu)"

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  description = "Workload name for naming convention. Keep short (max 24 chars total for KV name)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the Key Vault and Private Endpoint will be deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which to create the Key Vault and Private Endpoint. Must be caller-provided — KVStack no longer creates its own RG since v0.2.2 (same convention as NetworkWatcher v0.2.1, KeyVault, StorageAccount, etc.). Typically wired from a `../ResourceGroup` module instance in the consumer's Terragrunt config."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9_().-]{1,89}[a-zA-Z0-9_()-]$", var.resource_group_name))
    error_message = "resource_group_name must match Azure RG naming rules (1-90 chars, alphanumerics/underscores/parentheses/hyphens/periods, not ending in period)."
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the Key Vault Private Endpoint"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "Subnet ID must be a valid Azure resource ID."
  }
}

###############################################################
# NAMING OVERRIDES
###############################################################
variable "kv_suffix" {
  type        = string
  default     = null
  description = "Optional. Suffix for the KV and PE name. If null, uses the workload."
}

variable "kv_name" {
  type        = string
  default     = null
  description = "Optional. Explicit Key Vault name (3-24 chars). If null, computed."

  validation {
    condition     = var.kv_name == null || (length(var.kv_name) >= 3 && length(var.kv_name) <= 24 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.kv_name)))
    error_message = "Key Vault name must be 3-24 characters, start with a letter, end with a letter or digit, and contain only letters, digits, and hyphens."
  }
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

variable "assign_rbac_to_current_user" {
  type        = bool
  default     = false
  description = <<-EOT
  Forwarded to the canonical ../KeyVault module's `assign_rbac_to_current_user`
  input. **Default: false** to align with the canonical KV's secure-by-default
  posture (see modules/KeyVault/README.md — Prerequisites section). The
  recommended Azure-native pattern is to grant the Terraform SPN
  `Key Vault Administrator` inherited from the Management Group / Subscription
  scope ONCE, so it applies to every KV deployed without per-KV state pollution.

  Set to `true` only when:
  - The deployer cannot be granted inherited MG/Sub-level RBAC, AND
  - You need the deployer to manage child resources (keys, secrets, certs) in
    the same plan.

  Trade-off when `true`: every KV records an explicit role assignment for the
  deployer identity in state — auditability cost, and that identity remains
  admin on the KV permanently unless explicitly revoked.
  EOT
}

variable "kv_admin_group_object_id" {
  type        = string
  description = "Object ID of an Entra group to grant Key Vault Administrator at the Key Vault scope. Recommended over assign_rbac_to_current_user for pipeline-driven deployments where the deployer identity changes between runs. Forwarded to the canonical KV's role_assignments map as an `admin_group` entry."
  default     = null

  validation {
    condition     = var.kv_admin_group_object_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.kv_admin_group_object_id))
    error_message = "kv_admin_group_object_id must be a valid GUID."
  }
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
# PRIVATE ENDPOINT CONFIGURATION
###############################################################
variable "private_dns_zone_ids" {
  type        = list(string)
  description = "Private DNS Zone IDs for the Private Endpoint (e.g. privatelink.vaultcore.azure.net)"
  default     = null
}

variable "pe_private_ip_address" {
  type        = string
  description = "Optional. Static private IP for the Private Endpoint."
  default     = null

  validation {
    condition     = var.pe_private_ip_address == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.pe_private_ip_address))
    error_message = "pe_private_ip_address must be a valid IPv4 address."
  }
}

variable "pe_custom_network_interface_name" {
  type        = string
  description = "Optional. Custom network interface name for the Private Endpoint."
  default     = null
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}
