###############################################################
# NAMING CONVENTION
###############################################################

# F-7: var.name escape hatch (nullable, XOR validator)
variable "name" {
  description = "Explicit module-level name override (escape hatch). If null, derived from naming convention via ../Naming."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    error_message = "Either var.name must be set OR all 4 naming components (subscription_acronym, environment, region_code, workload) must be non-null."
  }
}

variable "subscription_acronym" {
  description = "Subscription acronym (e.g. mgm, con)"
  type        = string
  default     = null

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  description = "Environment (e.g. prod, nprd)"
  type        = string
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  description = "Region code (e.g. gwc, weu)"
  type        = string
  default     = null

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

# F-6: workload var (required for Naming submodule)
variable "workload" {
  description = "Workload identifier — typically 'finops' for FinOpsHub deployments."
  type        = string
  default     = "finops"
  nullable    = false
}

variable "location" {
  description = "Azure region (e.g. germanywestcentral)"
  type        = string
  nullable    = false
}

###############################################################
# CALLER-PROVIDED RESOURCE GROUP (F-1 BREAKING)
###############################################################

variable "resource_group_name" {
  description = "Name of the resource group where FinOpsHub resources will be deployed. Must be created by the caller (e.g. via ../ResourceGroup at root)."
  type        = string
  nullable    = false
}

###############################################################
# TAGS
###############################################################

# F-11: nullable = false
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
  nullable    = false
}

###############################################################
# STORAGE
###############################################################

variable "storage_replication_type" {
  description = "Replication type for the storage account (LRS, ZRS)"
  type        = string
  default     = "LRS"
  nullable    = false

  validation {
    condition     = contains(["LRS", "ZRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be LRS or ZRS."
  }
}

variable "export_retention_days" {
  description = "Number of days to retain raw exports in msexports container (0 = delete after processing)"
  type        = number
  default     = 0

  validation {
    condition     = var.export_retention_days >= 0
    error_message = "export_retention_days must be >= 0."
  }
}

variable "ingestion_retention_months" {
  description = "Number of months to retain ingested data in ingestion container"
  type        = number
  default     = 13

  validation {
    condition     = var.ingestion_retention_months >= 1
    error_message = "ingestion_retention_months must be >= 1."
  }
}

###############################################################
# AZURE DATA EXPLORER
###############################################################

variable "enable_data_explorer" {
  description = "Deploy Azure Data Explorer cluster and databases"
  type        = bool
  default     = true
}

variable "hub_additional_viewers" {
  description = <<-EOT
    Extra Viewer principals on the Data Explorer Hub database (key = short
    name, value = principal/object ID). Typically an application/managed
    identity — e.g. Grafana's identity reading FinOps data.

    NOTE: created with principal_type = "App" (managed identities / service
    principals). To grant an Entra GROUP or USER, this map isn't enough
    (a Group would be created as App and rejected) — extend the module to a
    per-entry principal_type first. Ignored when enable_data_explorer = false.
  EOT
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "adx_sku_name" {
  description = "ADX cluster SKU name (e.g. Dev(No SLA)_Standard_D11_v2 for dev, Standard_D11_v2 for prod)"
  type        = string
  default     = "Dev(No SLA)_Standard_D11_v2"
  nullable    = false
}

variable "adx_sku_capacity" {
  description = "ADX cluster node count (1 for dev, 2+ for prod)"
  type        = number
  default     = 1

  validation {
    condition     = var.adx_sku_capacity >= 1
    error_message = "adx_sku_capacity must be >= 1."
  }
}

variable "adx_disk_encryption_enabled" {
  description = "Encrypt the ADX cluster's VM disks (hot-cache data volumes + OS disk) at rest with Microsoft-managed keys. Secure-by-default true (CKV_AZURE_74)."
  type        = bool
  default     = true
  nullable    = false
}

variable "adx_double_encryption_enabled" {
  description = <<-EOT
    Enable infrastructure-level (double) encryption on the ADX cluster storage
    (CKV_AZURE_75). OPT-IN: default false.

    BREAKING / RECREATION: this property can only be set at cluster CREATION and
    cannot be changed afterwards (Azure platform constraint — see
    https://learn.microsoft.com/azure/data-explorer/cluster-encryption-double).
    The azurerm provider marks it ForceNew, so flipping this on an EXISTING
    cluster forces the cluster to be DESTROYED and RECREATED (raw ingested data
    is lost unless re-ingested). It is therefore kept opt-in / default false so
    it never destroys an existing FinOpsHub cluster implicitly. Set true on a
    NEW deployment to get infrastructure-level double encryption from creation.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "adx_hot_cache_days" {
  description = "Number of days for ADX hot cache"
  type        = number
  default     = 31
}

variable "adx_soft_delete_days" {
  description = "Number of days for ADX soft delete retention"
  type        = number
  default     = 365
}

# F-13: explicit zones override
variable "adx_zones" {
  description = "Availability zones for the ADX cluster. If null, defaults to [\"1\",\"2\",\"3\"] for non-Dev SKUs and [] for Dev SKUs."
  type        = list(string)
  default     = null
}

###############################################################
# COST MANAGEMENT EXPORTS
###############################################################

variable "cost_management_exports_principal_id" {
  description = "Principal ID of the Azure Cost Management Exports Service Principal (null = no role assignment)"
  type        = string
  default     = null
}

###############################################################
# NETWORKING
###############################################################

variable "enable_public_access" {
  description = "Enable public network access on storage and ADF. WARNING: bypasses firewall perimeter. Use Private Endpoints in production."
  type        = bool
  default     = false
}
