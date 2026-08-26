###############################################################
# NAMING CONVENTION
# The workload determines the suffix for all resource names:
#   ILB : lbi-{sub}-{env}-{region}-{workload}-trust  (via ../Naming, v0.2.26+)
#         OR the explicit var.name override
#   VM  : fw-{sub}-{env}-{region}-{key}              (key = obew-01, obew-02, ...)
#
# Example with workload = "palo-obew":
#   lbi-con-prod-gwc-palo-obew-trust
#   fw-con-prod-gwc-obew-01
#
# v0.2.26 BREAKING (ILB rename): convention naming now uses the ../Naming
# submodule slug "lbi-..." instead of the legacy "ilb-..." literal. Callers
# that relied on convention naming (var.name = null) will see the ILB renamed
# in Azure on upgrade. Pin var.name = "ilb-{old-name}-trust" to suppress.
###############################################################

variable "name" {
  type        = string
  default     = null
  description = <<-EOT
  Optional override for the ILB name (Palo cluster identifier). When null,
  computed via the ../Naming submodule as lbi-{subscription_acronym}-
  {environment}-{region_code}-{workload}-trust.

  Pass explicitly to preserve byte-for-byte Azure resource names on
  upgrade — legacy names used the "ilb-..." prefix while the Naming
  submodule produces "lbi-...". Example: set to
  "ilb-con-prod-gwc-palo-obew-trust" to suppress the ILB rename.
  EOT

  validation {
    condition = (
      var.name != null ||
      (var.subscription_acronym != null && var.environment != null &&
      var.region_code != null && var.workload != null)
    )
    error_message = "Either var.name OR all 4 naming vars (subscription_acronym, environment, region_code, workload) must be set."
  }
}

variable "subscription_acronym" {
  type        = string
  nullable    = false
  description = "Subscription acronym (e.g. con)"

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  nullable    = false
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  nullable    = false
  description = "Region code (e.g. gwc)"

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  nullable    = false
  description = "Workload / cluster name (e.g. palo-obew, palo-in)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }

  validation {
    # KV name format: "kv-{sub}-{env}-{region}-{kv_workload}" where kv_workload = replace(workload, "palo-", "")
    # sub: 2-5 chars, env: 2-4 chars, region: 2-5 chars → prefix "kv-" (3) + "-" separators (3) + max 14 = 20
    # Azure KV name limit: 24 chars → kv_workload must be ≤ 24 - 3 - 14 = 7 chars at worst-case prefix.
    # We allow 8 to match the more typical 3+3+3 prefix (13 chars with separators → 24-3-13 = 8).
    condition     = length(replace(var.workload, "palo-", "")) <= 8
    error_message = "After stripping the 'palo-' prefix, the workload segment must be <= 8 chars to keep the Key Vault name within Azure's 24-char limit."
  }
}

variable "location" {
  type        = string
  nullable    = false
  description = "Azure region (e.g. germanywestcentral)."
}

variable "resource_group_name" {
  type        = string
  nullable    = false
  description = <<-EOT
  Existing resource group name (caller-provided).

  PaloCluster v0.2.25+ no longer creates the RG — caller must supply
  an existing one. Create via ../ResourceGroup in your root module
  if needed.

  Migration from v0.2.24 and earlier: see README "Breaking changes (v0.2.25)"
  for the state-preserving migration recipe using `removed { lifecycle.destroy=false }`.
  EOT
}

variable "tags" {
  type        = map(string)
  nullable    = false
  default     = {}
  description = "Tags to assign"
}

###############################################################
# NETWORK — Subnet IDs (existing, already deployed)
###############################################################

variable "subnet_mgmt_id" {
  type        = string
  nullable    = false
  description = "Management subnet ID for management NICs."
}

variable "subnet_untrust_id" {
  type        = string
  nullable    = false
  description = "Untrust subnet ID for external NICs."
}

variable "subnet_trust_id" {
  type        = string
  nullable    = false
  description = "Trust subnet ID for internal NICs (ILB)."
}

###############################################################
# INTERNAL LOAD BALANCER (trust)
###############################################################

variable "ilb_frontend_ip" {
  type        = string
  nullable    = false
  description = "Static private IP for the ILB frontend in the trust subnet (e.g. 10.238.200.36)."
}

variable "ilb_probe_port" {
  type        = number
  default     = 443
  description = "ILB health probe port."
}

variable "ilb_probe_threshold" {
  type        = number
  default     = 2
  description = "Number of consecutive probe failures before marking backend unhealthy."
}

variable "ilb_probe_interval" {
  type        = number
  default     = 5
  description = "Health probe interval in seconds."
}

###############################################################
# VM-SERIES INSTANCES
###############################################################

variable "firewalls" {
  type = map(object({
    mgmt_ip    = string
    untrust_ip = string
    trust_ip   = string
    zone       = optional(string)
  }))
  description = <<-EOT
    Map of firewall instances to deploy.
    The key is the name suffix (e.g. "obew-01", "obew-02").
    Example:
      firewalls = {
        "fw-01" = { mgmt_ip = "x.x.x.4",  untrust_ip = "x.x.x.20", trust_ip = "x.x.x.37", zone = "1" }
        "fw-02" = { mgmt_ip = "x.x.x.5",  untrust_ip = "x.x.x.21", trust_ip = "x.x.x.38", zone = "2" }
      }
  EOT
}

variable "vm_size" {
  type        = string
  nullable    = false
  default     = "Standard_DS4_v3"
  description = <<-EOT
  VM SKU for the Palo VM-Series cluster.

  Minimum requirements: 4 vCPU, 14 GB RAM (Palo VM-300+).

  Encryption at Host compatibility:
  - Dsv2 family (Standard_DS3_v2 etc.) is NOT compatible with
    encryption_at_host_enabled = true → VM create fails.
  - Dsv3 / Dsv4 / Esv3+ families are compatible.

  Default Standard_DS4_v3 (4 vCPU, 16 GB) satisfies both Palo VM-300
  requirements and Encryption at Host. If you must use Dsv2, set
  encryption_at_host_enabled = false explicitly.
  EOT
}

variable "vm_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "paloaltonetworks"
    offer     = "vmseries-flex"
    sku       = "byol"
    version   = "latest"
  }
  description = "Palo Alto VM-Series marketplace image reference."
}

variable "accept_marketplace_agreement" {
  type        = bool
  default     = false
  description = <<-EOT
  Accept the Azure Marketplace agreement for Palo Alto VM-Series.

  Set to true on FIRST deployment per subscription. Subsequent deployments
  can leave this false (the agreement persists at subscription level).

  If the agreement was accepted out-of-band (Azure portal, or pre-existing
  Terraform code), leave this false to avoid a duplicate-acceptance error.
  EOT
}

variable "panos_version" {
  type        = string
  nullable    = false
  default     = "11.1.607"
  description = "PAN-OS version. Applied as the 'PanosVersion' tag on all cluster resources for lifecycle visibility. The actual running version is controlled by var.vm_image."
}

variable "admin_username" {
  type        = string
  nullable    = false
  default     = "panadmin"
  description = "Admin username for VM-Series instances."
}

variable "admin_password" {
  type        = string
  sensitive   = true
  default     = null
  description = "Admin password. If null and no SSH key provided, a random password is generated and stored in Key Vault (requires enable_disk_encryption = true)."

  validation {
    condition     = var.admin_password != null || var.admin_ssh_public_key != null || var.enable_disk_encryption
    error_message = "Either admin_password, admin_ssh_public_key, or enable_disk_encryption (for auto-generated password stored in KV) must be set."
  }
}

variable "admin_ssh_public_key" {
  type        = string
  default     = null
  description = "SSH public key for authentication. Mutually exclusive with admin_password."
}

variable "encryption_at_host_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
  Enables Encryption at Host on the VMs. Encrypts temp disk + cache + pagefile
  at the hypervisor level (complements disk_encryption_set_id which covers
  the managed disks with CMK).

  Prerequisite: feature 'Microsoft.Compute/EncryptionAtHost' must be
  registered on the subscription:
    az feature register --namespace Microsoft.Compute --name EncryptionAtHost
    az provider register --namespace Microsoft.Compute

  Requires a compatible VM size (Dsv4+, Esv4+, etc. — not D_v3 or similar).
  EOT
}

variable "os_disk_size_gb" {
  type        = number
  default     = 80
  description = "OS disk size in GB."
}

variable "os_disk_storage_account_type" {
  type        = string
  default     = "Premium_LRS"
  description = "OS disk storage account type: Standard_LRS, StandardSSD_LRS, or Premium_LRS."

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.os_disk_storage_account_type)
    error_message = "os_disk_storage_account_type must be Standard_LRS, StandardSSD_LRS, or Premium_LRS."
  }
}

variable "accelerated_networking" {
  type        = bool
  default     = true
  description = "Enable accelerated networking on dataplane NICs (untrust + trust). Strongly recommended by Palo Alto for DPDK throughput."
}

variable "enable_boot_diagnostics" {
  type        = bool
  default     = false
  description = "Enable boot diagnostics for troubleshooting VM boot failures."
}

variable "boot_diagnostics_storage_uri" {
  type        = string
  default     = null
  description = "Storage account URI for boot diagnostics. If null with boot diagnostics enabled, uses managed storage."
}

###############################################################
# MANAGEMENT LOCK (optional)
###############################################################

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Optional management lock on the ILB (Internal Load Balancer) — the
  critical Palo cluster ingress point. When set, blocks accidental delete
  of the ILB without affecting individual VMs/NICs (which have their own
  prevent_destroy guard).

  - kind: "CanNotDelete" or "ReadOnly".
  - name: optional override (defaults to lock-ilb).
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be CanNotDelete or ReadOnly when lock is set."
  }
}

###############################################################
# DISK ENCRYPTION (optional — Key Vault + key + DES per cluster)
###############################################################

variable "enable_disk_encryption" {
  type        = bool
  default     = true
  description = "Creates a Key Vault, RSA key and Disk Encryption Set for CMK OS disk encryption."
}

variable "kv_secrets_readers" {
  type        = list(string)
  default     = []
  description = "List of Entra ID group object IDs granted Key Vault Secrets User on the cluster KV."
}

variable "kv_admin_principal_ids" {
  type        = list(string)
  default     = []
  description = <<-EOT
  List of Entra ID principal object IDs (users, groups, or service principals)
  granted 'Key Vault Administrator' on the cluster KV.

  Must include every identity that will run 'terragrunt apply' on this module:
    - The pipeline SPN (e.g. spn-azdo-alz-001 OID)
    - Any local admin deploying from their workstation

  Avoids the ping-pong replacement triggered when the previous auto-
  assignment used 'data.azurerm_client_config.current.object_id'.

  For prod, prefer a single Entra ID group OID (GRP_AZ_PIM_*) containing
  the authorized members — enables JIT activation and a clean audit trail.
  EOT
}

variable "kv_allowed_ips" {
  type        = list(string)
  default     = []
  description = "Public IPs (CIDR /32) added to the KV network_acls allowlist. The KV is always publicly reachable (required for DES key unwrap via AzureServices bypass) with default_action = Deny; this list grants additional explicit callers."
}

variable "disk_encryption_key_expiration_days" {
  type        = number
  default     = 730
  description = <<-EOT
  Validity period (in days) applied as `expiration_date` on the disk-encryption
  Key Vault key (CKV_AZURE_40). Default 730 days (2 years) is aligned with the
  key's P2Y `rotation_policy`.

  Why expiry is SAFE for this disk-encryption key (per Microsoft Learn):
    - The key carries a rotation_policy that auto-rotates a fresh version 30 days
      before expiry, and the Disk Encryption Set has auto_key_rotation_enabled =
      true. Azure updates all disks referencing the DES to the new key version
      within one hour, and re-wraps the DEK without re-encrypting disk data.
    - Existing disks keep decrypting: an expired *version* does not break the DES
      while a newer version exists. Data loss only occurs if the whole key is
      DELETED/DISABLED, or if it expires with NO auto-rotation configured — neither
      applies here.

  The expiration anchor is frozen (via time_offset) at the apply that first
  introduces it, so the date is always `upgrade_time + N days` (future) and stable
  across plans.
  EOT

  validation {
    condition     = var.disk_encryption_key_expiration_days > 0
    error_message = "disk_encryption_key_expiration_days must be > 0."
  }
}

variable "kv_secret_expiration_days" {
  type        = number
  default     = 365
  description = <<-EOT
  Validity period (in days) applied as `expiration_date` on the vwan BGP-peer
  Key Vault secrets (CKV_AZURE_41). Default 365 days. Anchored via time_offset
  (frozen at first apply) so the date is stable across plans.
  EOT

  validation {
    condition     = var.kv_secret_expiration_days > 0
    error_message = "kv_secret_expiration_days must be > 0."
  }
}

###############################################################
# VWAN BGP PEER CONFIG (optional)
# Consumed from module.vwan.virtual_hub_router_ips / _asns outputs
# (added in vwan v0.2.17 specifically to unblock this wiring).
###############################################################

variable "vwan_bgp_peer_ips" {
  type        = list(string)
  default     = null
  description = <<-EOT
  Optional list of vwan virtual hub router BGP peer IPs (consumed from
  module.vwan.virtual_hub_router_ips[<hub_key>]).

  When set together with enable_disk_encryption = true, the IPs are stored
  as a Key Vault secret for Panorama / bootstrap.xml pickup. Enables a
  Terraform-managed dependency chain between vwan and Palo BGP config.

  When null, BGP peer config is assumed to be managed externally
  (Panorama, bootstrap.xml hardcoded values, etc.).
  EOT
}

variable "vwan_bgp_peer_asn" {
  type        = number
  default     = null
  description = <<-EOT
  Optional vwan virtual hub router BGP ASN (consumed from
  module.vwan.virtual_hub_router_asns[<hub_key>]). Typically 65515.

  Companion to var.vwan_bgp_peer_ips. Stored as KV secret when
  enable_disk_encryption = true.
  EOT
}

###############################################################
# MONITORING — Application Insights (optional)
###############################################################

variable "log_analytics_workspace_id" {
  type        = string
  default     = null
  description = "Log Analytics Workspace ID for Application Insights. If null, no APPI is created."
}

variable "panos_spn_object_id" {
  type        = string
  default     = null
  description = "PAN-OS SPN object ID (e.g. spn-prod-panos-001). Receives the custom AppInsights role on the subscription."
}

###############################################################
# BOOTSTRAP (optional)
###############################################################

variable "bootstrap_storage_account_name" {
  type        = string
  default     = null
  description = "Bootstrap storage account NAME (not ARM resource ID). PAN-OS expects the account name, not the full /subscriptions/.../storageAccounts/... path. If null, no bootstrap."
}

variable "bootstrap_share_name" {
  type        = string
  default     = null
  description = "File share name for bootstrap."
}

variable "bootstrap_share_directory" {
  type        = string
  default     = null
  description = "Optional subdirectory within the file share for bootstrap packages."
}

variable "bootstrap_storage_account_access_key" {
  type        = string
  sensitive   = true
  default     = null
  description = "Bootstrap storage account access key."
}

variable "bootstrap_storage_account_sas_token" {
  type        = string
  default     = null
  sensitive   = true
  description = <<-EOT
  Optional SAS token (time-limited) as an alternative to bootstrap_storage_account_access_key.

  If both are set, the SAS token takes precedence (access-key= in custom_data is set to the
  SAS value). Trade-off: SAS tokens expire and must be rotated; master access keys persist
  but are more sensitive. Choose based on operational tolerance.
  EOT
}

variable "bootstrap_storage_account_use_msi" {
  type        = bool
  default     = false
  description = <<-EOT
  Use the VM's System-Assigned Managed Identity for bootstrap SA access instead of an access
  key or SAS token.

  Requires PAN-OS 10.2+ (native MSI-based blob storage access). When true, no credential
  is embedded in custom_data. The VM's MSI must be granted "Storage Blob Data Reader" on the
  bootstrap container before first boot — wire this via ../RoleAssignment in the caller.
  EOT
}
