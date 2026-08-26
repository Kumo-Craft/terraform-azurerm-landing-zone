###############################################################
# SecuritySentinel — dedicated LAW + Microsoft Sentinel (SOC)
###############################################################

variable "subscription_acronym" {
  type        = string
  nullable    = false
  description = "Subscription acronym (e.g. 'sec')."
}

variable "environment" {
  type        = string
  nullable    = false
  description = "Environment (prod/nprd)."
}

variable "region_code" {
  type        = string
  nullable    = false
  description = "Region short code (e.g. 'gwc')."
}

variable "workload" {
  type        = string
  default     = "01"
  nullable    = false
  description = "Workload/instance suffix for naming."
}

variable "location" {
  type        = string
  nullable    = false
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  nullable    = false
  description = "Resource group hosting the Sentinel LAW."
}

###############################################################
# LOG ANALYTICS / SENTINEL
###############################################################
variable "log_retention_days" {
  type        = number
  default     = 90
  nullable    = false
  description = "Interactive retention (days) for the Sentinel workspace."
}

variable "daily_quota_gb" {
  type        = number
  default     = -1
  nullable    = false
  description = "Daily ingestion cap in GB. -1 = NO cap (recommended for a Sentinel workspace — a cap blinds the SOC on a spike)."
}

variable "law_internet_ingestion_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Allow public ingestion. false = private only (via AMPLS)."
}

variable "law_internet_query_enabled" {
  type        = bool
  default     = false
  nullable    = false
  description = "Allow public query. false = private only (via AMPLS)."
}

variable "law_local_authentication_disabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Disable workspace-key (local) auth → Entra ID only."
}

variable "enable_cmk" {
  type    = bool
  default = false
  # Only flips customer_managed_key_enabled on the onboarding — it provisions
  # NOTHING. CMK for Sentinel requires (heavy, ops-owned, out of this module):
  #   1. a Log Analytics DEDICATED CLUSTER with >= 100 GB/day commitment, CMK enabled on the cluster;
  #   2. this workspace LINKED to that cluster;
  #   3. a Key Vault (same region, soft-delete + purge protection) holding the key;
  #   4. the cluster's system-assigned identity granted wrap/unwrap on the key;
  #   5. the Azure Cosmos DB RP registered + a KV access policy for its principal.
  # Also: MS supports CMK onboarding only via REST/az CLI (not ARM), so the
  # azurerm flag may fail unless all of the above already exists. Leave false
  # unless you run a dedicated cluster — data is still encrypted at rest (MMK).
  nullable    = false
  description = "Customer-managed key for Sentinel onboarding. Requires a pre-existing CMK-enabled dedicated LA cluster (>=100 GB/day) + Key Vault — see comment. Leave false otherwise (MMK still encrypts at rest)."
}

###############################################################
# DATA CONNECTORS (opt-in — need tenant/subscription permissions)
###############################################################
variable "connectors" {
  type = object({
    entra_id           = optional(bool, false) # Microsoft Entra ID (sign-in/audit) — needs tenant Global/Security Reader
    defender_for_cloud = optional(bool, false) # Microsoft Defender for Cloud (subscription alerts)
  })
  default     = {}
  nullable    = false
  description = "Toggle built-in Sentinel data connectors. Off by default (permission-dependent)."
}

variable "connector_tenant_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Tenant id for the Entra ID connector. Null = current tenant."
}

variable "connector_subscription_id" {
  type        = string
  default     = null
  nullable    = true
  description = "Subscription id for the Defender for Cloud connector. Null = current subscription."
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags."
}
