###############################################################
# MODULE: StorageAccountStack - Variables
# Composes Storage Account + Private Endpoint(s) (via
# ../StorageAccount and ../PrivateEndpoint). The Resource Group is
# caller-provided (var.resource_group_name) — same convention as
# KeyVaultStack and every other leaf module in the repo.
###############################################################

###############################################################
# NAMING CONVENTION
# Storage Account: lowercase alphanumeric only, 3-24 chars.
# Convention: st{subscription_acronym}{environment}{region_code}{workload}
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
  description = "Workload suffix for naming convention. Lowercase alphanumeric only (no hyphens — Storage Account constraint)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,15}$", var.workload))
    error_message = "workload must be 1-16 lowercase alphanumeric characters."
  }
}

variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit Storage Account name (3-24 lowercase alphanumeric). If null, computed by the canonical StorageAccount module from the naming components."

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage Account name must be 3-24 lowercase alphanumeric characters."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the Storage Account and Private Endpoint(s) will be deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which to create the Storage Account and Private Endpoint(s). Caller-provided — this Stack does not create its own RG (same convention as KeyVaultStack)."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9_().-]{1,89}[a-zA-Z0-9_()-]$", var.resource_group_name))
    error_message = "resource_group_name must match Azure RG naming rules (1-90 chars, alphanumerics/underscores/parentheses/hyphens/periods, not ending in period)."
  }
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the Storage Account Private Endpoint(s)."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "Subnet ID must be a valid Azure resource ID."
  }
}

###############################################################
# STORAGE CONFIGURATION (forwarded to ../StorageAccount)
###############################################################
variable "account_tier" {
  type        = string
  description = "Tier: Standard or Premium"
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be 'Standard' or 'Premium'."
  }
}

variable "account_replication_type" {
  type        = string
  description = "Replication type: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS"
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "account_kind" {
  type        = string
  description = "Kind: StorageV2, BlobStorage, BlockBlobStorage, FileStorage"
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "BlobStorage", "BlockBlobStorage", "FileStorage"], var.account_kind)
    error_message = "account_kind must be one of: StorageV2, BlobStorage, BlockBlobStorage, FileStorage."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Enable public network access. Secure default false — reach the account over the Private Endpoint(s)."
  default     = false
}

variable "shared_access_key_enabled" {
  type        = bool
  description = "Enable shared access keys (account keys / connection strings). Disable to force AAD-only auth."
  default     = false
}

variable "default_to_oauth_authentication" {
  type        = bool
  description = "Default the portal/CLI to AAD OAuth instead of access keys for data-plane operations."
  default     = true
}

variable "cross_tenant_replication_enabled" {
  type        = bool
  description = "Allow object replication across Azure AD tenants."
  default     = false
}

variable "infrastructure_encryption_enabled" {
  type        = bool
  description = "Enable infrastructure-level AES-256 encryption (double encryption). Immutable after creation."
  default     = true
}

variable "local_user_enabled" {
  type        = bool
  description = "Enable local users for SFTP/NFS."
  default     = false
}

variable "customer_managed_key" {
  description = "Customer-Managed Key (CMK) configuration backed by Azure Key Vault. See the ../StorageAccount module for prerequisites."
  type = object({
    key_vault_key_id          = string
    user_assigned_identity_id = string
  })
  default = null
}

variable "identity_type" {
  type        = string
  description = "Identity type: SystemAssigned, UserAssigned, or SystemAssigned,UserAssigned"
  default     = null

  validation {
    condition     = var.identity_type == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned,UserAssigned"], var.identity_type)
    error_message = "identity_type must be 'SystemAssigned', 'UserAssigned', or 'SystemAssigned,UserAssigned'."
  }
}

variable "identity_ids" {
  type        = set(string)
  description = "Set of UAMI resource IDs to attach when identity_type contains 'UserAssigned'."
  default     = []
  nullable    = false
}

variable "blob_delete_retention_days" {
  type        = number
  description = "Retention days for deleted blobs"
  default     = 30

  validation {
    condition     = var.blob_delete_retention_days >= 1 && var.blob_delete_retention_days <= 365
    error_message = "blob_delete_retention_days must be between 1 and 365."
  }
}

variable "container_delete_retention_days" {
  type        = number
  description = "Retention days for deleted containers"
  default     = 30

  validation {
    condition     = var.container_delete_retention_days >= 1 && var.container_delete_retention_days <= 365
    error_message = "container_delete_retention_days must be between 1 and 365."
  }
}

variable "blob_versioning_enabled" {
  type        = bool
  description = "Enable blob versioning."
  default     = false
}

variable "blob_change_feed_enabled" {
  type        = bool
  description = "Enable the blob change feed."
  default     = false
}

variable "blob_last_access_time_enabled" {
  type        = bool
  description = "Track last-access time on blobs."
  default     = false
}

variable "containers" {
  description = "A map of containers to create in the Storage Account (key arbitrary; name + optional access_type)."
  type = map(object({
    name        = string
    access_type = optional(string, "private")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for c in var.containers : contains(["private", "blob", "container"], c.access_type)])
    error_message = "Container access_type must be 'private', 'blob', or 'container'."
  }
}

variable "file_shares" {
  description = "A map of file shares to create (key arbitrary; name + quota_gb + optional access_tier)."
  type = map(object({
    name        = string
    quota_gb    = number
    access_tier = optional(string)
  }))
  default  = {}
  nullable = false
}

variable "azure_files_authentication" {
  description = "Identity-based authentication for Azure Files shares. See the ../StorageAccount module for the full shape."
  type = object({
    directory_type                 = string
    default_share_level_permission = optional(string)
    active_directory = optional(object({
      domain_guid         = string
      domain_name         = string
      domain_sid          = optional(string)
      forest_name         = optional(string)
      netbios_domain_name = optional(string)
      storage_sid         = optional(string)
    }))
  })
  default = null

  validation {
    condition     = var.azure_files_authentication == null || contains(["AADDS", "AD", "AADKERB"], try(var.azure_files_authentication.directory_type, ""))
    error_message = "directory_type must be 'AADDS', 'AD', or 'AADKERB'."
  }
}

variable "network_rules" {
  description = "Storage Account firewall rules. When null, no network_rules block is created. See the ../StorageAccount module for the full shape."
  type = object({
    default_action             = string
    bypass                     = optional(list(string), ["AzureServices"])
    virtual_network_subnet_ids = optional(list(string), [])
    ip_rules                   = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.network_rules == null || contains(["Allow", "Deny"], try(var.network_rules.default_action, ""))
    error_message = "network_rules.default_action must be 'Allow' or 'Deny'."
  }
}

variable "sas_policy" {
  type = object({
    expiration_period = string
    expiration_action = optional(string, "Log")
  })
  default     = null
  description = "Optional SAS token expiration policy (expiration_period ISO 8601 `d.HH:mm:ss`; expiration_action Log/Block)."

  validation {
    condition     = var.sas_policy == null || contains(["Log", "Block"], try(var.sas_policy.expiration_action, "Log"))
    error_message = "sas_policy.expiration_action must be \"Log\" or \"Block\"."
  }
}

variable "role_assignments" {
  description = "A map of role assignments to create on the Storage Account (forwarded to the canonical StorageAccount module). The map key is arbitrary."
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

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = "Management lock applied to the Storage Account (CanNotDelete or ReadOnly)."

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

###############################################################
# PRIVATE ENDPOINT CONFIGURATION
# One Private Endpoint per Storage sub-resource. The map key IS the
# Storage sub-resource (blob, file, queue, table, web, dfs, and
# their *_secondary variants for RA-GRS). Azure requires a separate
# Private Endpoint per sub-resource.
###############################################################
variable "private_endpoints" {
  description = <<-EOT
  A map of Private Endpoints to create, keyed by Storage **sub-resource**
  (`blob`, `file`, `queue`, `table`, `web`, `dfs`, plus the `*_secondary`
  variants for RA-GRS read access). Azure requires one Private Endpoint per
  sub-resource, each resolving via its own private DNS zone
  (e.g. `privatelink.blob.core.windows.net`).

  Per-entry fields (all optional):
  - `private_dns_zone_ids`          - Private DNS zone IDs for this sub-resource's zone. Omit when an ALZ DINE policy wires DNS (the PrivateEndpoint module ignores drift on the zone group).
  - `private_ip_address`            - Static private IPv4 (dynamic when null).
  - `custom_network_interface_name` - Custom NIC name.

  Default `{ blob = {} }` — a single Blob Private Endpoint. Set `{}` to create no PE.
  EOT
  type = map(object({
    private_dns_zone_ids          = optional(list(string))
    private_ip_address            = optional(string)
    custom_network_interface_name = optional(string)
  }))
  default  = { blob = {} }
  nullable = false

  validation {
    condition = alltrue([
      for sr in keys(var.private_endpoints) :
      contains([
        "blob", "blob_secondary",
        "file", "file_secondary",
        "queue", "queue_secondary",
        "table", "table_secondary",
        "web", "web_secondary",
        "dfs", "dfs_secondary",
      ], sr)
    ])
    error_message = "Each private_endpoints key must be a valid Storage sub-resource: blob, file, queue, table, web, dfs (or their *_secondary variants)."
  }

  validation {
    condition     = alltrue([for pe in var.private_endpoints : pe.private_ip_address == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", pe.private_ip_address))])
    error_message = "Each private_endpoints[*].private_ip_address must be a valid IPv4 address."
  }
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
  nullable    = false
}
