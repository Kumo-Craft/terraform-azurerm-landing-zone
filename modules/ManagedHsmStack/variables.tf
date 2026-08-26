###############################################################
# MODULE: ManagedHsmStack - Variables
# Composes Managed HSM + Private Endpoint (via ../ManagedHsm and
# ../PrivateEndpoint). Mirror of KeyVaultStack. RG is caller-provided.
#
# HSM-related inputs are thin passthroughs to ../ManagedHsm, which
# owns their validation (secure defaults, purge protection forced,
# name rules, etc.). Only Stack-specific inputs are validated here.
###############################################################

###############################################################
# NAMING CONVENTION (forwarded to ../ManagedHsm)
# Convention: mhsm-{acronym}-{env}-{region}[-{workload}] (workload optional)
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional explicit Managed HSM name (3-24 chars). Null = derived by ../ManagedHsm as mhsm-{acr}-{env}-{region}[-{workload}]."
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. idt, con, sec). Forwarded to ../ManagedHsm."
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd). Forwarded to ../ManagedHsm."
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu). Forwarded to ../ManagedHsm."
}

variable "workload" {
  type        = string
  default     = null
  description = "Optional workload suffix segment. Forwarded to ../ManagedHsm."
  nullable    = true
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the Managed HSM and Private Endpoint are deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group hosting the Managed HSM and Private Endpoint (caller-provided, typically from a ../ResourceGroup module instance)."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9_().-]{1,89}[a-zA-Z0-9_()-]$", var.resource_group_name))
    error_message = "resource_group_name must match Azure RG naming rules (1-90 chars, alphanumerics/underscores/parentheses/hyphens/periods, not ending in period)."
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the Managed HSM Private Endpoint."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet Azure resource ID."
  }
}

variable "admin_object_ids" {
  type        = list(string)
  description = "Entra object IDs of the initial Managed HSM administrators (>= 1). Forwarded to ../ManagedHsm."
  nullable    = false
}

###############################################################
# MANAGED HSM CONFIGURATION (forwarded to ../ManagedHsm)
###############################################################
variable "tenant_id" {
  type        = string
  default     = null
  description = "Tenant ID. Null = current tenant (resolved by ../ManagedHsm)."
  nullable    = true
}

variable "sku_name" {
  type        = string
  default     = "Standard_B1"
  description = "Managed HSM SKU (only Standard_B1). Forwarded to ../ManagedHsm."
}

variable "soft_delete_retention_days" {
  type        = number
  default     = 90
  description = "Soft-delete retention (7-90, default 90). Forwarded to ../ManagedHsm."
  nullable    = false
}

variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = "Allow public network access. Default false (reach via the composed Private Endpoint). Forwarded to ../ManagedHsm."
  nullable    = false
}

variable "network_acls" {
  type = object({
    bypass         = optional(string, "AzureServices")
    default_action = optional(string, "Deny")
  })
  default     = {}
  nullable    = false
  description = "Network ACLs (bypass: AzureServices|None, default_action: Allow|Deny). Forwarded to ../ManagedHsm."
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = "Optional Resource Lock on the Managed HSM. Forwarded to ../ManagedHsm (on top of its prevent_destroy)."
}

variable "role_assignments" {
  type = map(object({
    principal_id         = string
    scope                = optional(string, "/keys")
    role_definition_name = optional(string)
    role_definition_id   = optional(string)
    name                 = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "Managed HSM LOCAL RBAC (data-plane) role assignments. Forwarded to ../ManagedHsm — see its README. NOTE: requires the HSM to be activated (security domain) first; typically a second apply."
}

###############################################################
# BACKUP IDENTITY (user-assigned managed identity for HSM backup)
#
# Managed HSM full backup/restore authenticates to the backup storage
# account via a USER-ASSIGNED managed identity that holds Storage Blob
# Data Contributor on the container. This composes ../ManagedIdentity to
# create that UAMI (+ the storage role assignment when a scope is given).
#
# NOTE: associating the UAMI to the HSM (az keyvault update-hsm
# --mi-user-assigned <id>) is an out-of-band step — the azurerm Managed
# HSM resource has no identity block. Then run
#   az keyvault backup start --use-managed-identity true ...
###############################################################
variable "enable_backup_identity" {
  type        = bool
  default     = false
  description = "Create a user-assigned managed identity (via ../ManagedIdentity) for Managed HSM full backup/restore. Default false."
  nullable    = false
}

variable "backup_identity_name" {
  type        = string
  default     = null
  description = "Optional name override for the backup UAMI. Null = id-{hsm_name}-backup."
}

variable "backup_storage_scope_id" {
  type        = string
  default     = null
  description = "Optional resource ID of the backup storage account (or blob container) to grant the backup UAMI 'Storage Blob Data Contributor'. Null = no role assignment (grant it out-of-band). Ignored when enable_backup_identity = false."
}

###############################################################
# PRIVATE ENDPOINT CONFIGURATION
###############################################################
variable "private_dns_zone_ids" {
  type        = list(string)
  default     = null
  description = "Private DNS Zone IDs for the Private Endpoint (use the privatelink.managedhsm.azure.net zone). Null = no DNS zone group (wire DNS elsewhere)."
}

variable "pe_private_ip_address" {
  type        = string
  default     = null
  description = "Optional static private IP for the Private Endpoint."

  validation {
    condition     = var.pe_private_ip_address == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.pe_private_ip_address))
    error_message = "pe_private_ip_address must be a valid IPv4 address."
  }
}

variable "pe_custom_network_interface_name" {
  type        = string
  default     = null
  description = "Optional custom network interface name for the Private Endpoint."
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the Managed HSM and Private Endpoint."
}
