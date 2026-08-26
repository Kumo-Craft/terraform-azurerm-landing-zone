###############################################################
# MODULE: Vm-Windows - Variables
###############################################################

###############################################################
# NAMING
# Azure VM:  vm-{sub_acronym}-{env}-{region_code}-{workload}-{index}
# Computer:  {computer_name_prefix}{index}   (max 15 chars total — NetBIOS)
#
# XOR escape hatch:
#   var.name != null  → explicit base name, ../Naming not instantiated
#   var.name == null  → all 4 convention components required
###############################################################

# F-5: explicit name override / XOR escape hatch
variable "name" {
  description = "Explicit VM base name override (escape hatch). If set, bypasses ../Naming. If null, uses the canonical convention via ../Naming submodule."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    error_message = "Either var.name must be set (escape hatch) OR all 4 naming components (subscription_acronym, environment, region_code, workload) must be non-null."
  }
}

variable "subscription_acronym" {
  type    = string
  default = null

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type    = string
  default = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type    = string
  default = null

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  description = "Workload suffix for VM naming (e.g. app, srv, web)."
  default     = null

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9-]{1,15}$", var.workload))
    error_message = "workload must start with a lowercase letter and be 2-16 lowercase alphanumeric or hyphen chars."
  }
}

variable "computer_name_prefix" {
  type        = string
  description = "Windows computer name prefix (≤ 13 chars; 2 digits appended → 15 total NetBIOS max). Lowercase alphanumeric. Defaults to '{workload}{env}'."
  default     = null

  validation {
    condition     = var.computer_name_prefix == null || can(regex("^[a-z][a-z0-9]{0,12}$", var.computer_name_prefix))
    error_message = "computer_name_prefix must be 1-13 lowercase alphanumeric chars (starts with a letter)."
  }
}

###############################################################
# REQUIRED
###############################################################
variable "location" {
  type     = string
  nullable = false
}

variable "resource_group_name" {
  type     = string
  nullable = false
}

variable "subnet_id" {
  type        = string
  description = "Subnet resource ID where the NIC(s) will be deployed."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet resource ID."
  }
}

###############################################################
# VM CONFIGURATION
###############################################################
variable "vm_count" {
  type        = number
  description = "Number of Windows VMs to create."
  default     = 1

  validation {
    condition     = var.vm_count >= 1 && var.vm_count <= 100
    error_message = "vm_count must be between 1 and 100."
  }
}

variable "vm_size" {
  type        = string
  description = "VM size. D4s_v5 is a sensible general-purpose default."
  default     = "Standard_D4s_v5"
}

variable "availability_zones" {
  type        = list(string)
  description = "Zones to spread VMs across (round-robin). Empty list = no zone placement."
  default     = ["1", "2", "3"]
}

variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
  })
  description = "Marketplace image reference. Default: Windows Server 2022 Datacenter Azure Edition."
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

variable "os_disk" {
  type = object({
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadWrite")
    disk_size_gb         = optional(number, 128)
  })
  description = "OS disk configuration. Defaults to Premium_LRS 128 GiB, ReadWrite caching."
  default     = {}
}

variable "accelerated_networking_enabled" {
  type        = bool
  description = "Enable Accelerated Networking on the VM NIC. Set false for sizes that do not support SR-IOV."
  default     = true
}

variable "enable_trusted_launch" {
  type        = bool
  description = "Enable Trusted Launch (vTPM + Secure Boot). Microsoft-recommended for new Windows VMs."
  default     = true
}

variable "license_type" {
  type        = string
  description = <<-EOT
  Azure Hybrid Benefit license type for the Windows VM.
  Allowed: "Windows_Client", "Windows_Server", "None".
  Default is "None" (pay-as-you-go). Set "Windows_Server" only if you hold active
  Software Assurance entitlement — applying AHB without a valid SA licence is a
  compliance violation under the Microsoft Product Terms.
  BREAKING CHANGE (v0.2.72): default changed from "Windows_Server" to "None".
  Callers relying on the previous implicit AHB default MUST explicitly set
  license_type = "Windows_Server" before upgrading to preserve AHB pricing.
  EOT
  default     = "None"

  validation {
    condition     = contains(["Windows_Client", "Windows_Server", "None"], var.license_type)
    error_message = "license_type must be 'Windows_Client', 'Windows_Server', or 'None'."
  }
}

variable "patch_mode" {
  type        = string
  description = <<-EOT
  Patch orchestration mode. AutomaticByPlatform integrates with Azure Update Manager.
  Allowed: "Manual", "AutomaticByOS", "AutomaticByPlatform".
  EOT
  default     = "AutomaticByPlatform"

  validation {
    condition     = contains(["Manual", "AutomaticByOS", "AutomaticByPlatform"], var.patch_mode)
    error_message = "patch_mode must be 'Manual', 'AutomaticByOS', or 'AutomaticByPlatform'."
  }
}

variable "bypass_platform_safety_checks_on_user_schedule" {
  type        = bool
  description = "When patch_mode = AutomaticByPlatform, defer to a user-defined maintenance configuration (Update Manager)."
  default     = true
}

variable "hotpatching_enabled" {
  type        = bool
  description = "Enable hotpatching where supported (Server 2022 Datacenter Azure Edition). Reduces reboots for security patches."
  default     = false
}

# F-2: encryption_at_host_enabled — CAF secure default = true
variable "encryption_at_host_enabled" {
  description = "Enable host-based encryption (encrypts temp disk + OS disk cache at hypervisor layer). CAF secure-by-default = true. Azure platform default is false; setting true on existing VMs requires VM stop/dealloc. Callers with existing non-encrypted VMs should set this to false during transition, then schedule a maintenance window to flip back to true."
  type        = bool
  default     = true
  nullable    = false
}

###############################################################
# ADMIN ACCESS
# Even with Entra ID login, Windows requires a local admin user
# created at provisioning time (Azure platform constraint).
# The password is stored out-of-band in Key Vault and rotated
# via `az vm reset` — never committed to state.
###############################################################
variable "admin_username" {
  type        = string
  description = "Local admin username (created at provisioning; intended for break-glass only — primary access is Entra ID)."
  default     = "azureadmin"
}

variable "admin_password_kv_id" {
  type        = string
  description = "Key Vault resource ID holding the local admin password secret."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", var.admin_password_kv_id))
    error_message = "admin_password_kv_id must be a valid Key Vault resource ID."
  }
}

variable "admin_password_secret_name" {
  type        = string
  description = "Name of the Key Vault secret holding the local admin password."
  nullable    = false
}

###############################################################
# IDENTITY
# Entra ID login extension is always installed (AAD-only auth pattern).
# SystemAssigned is enabled by default; pass user_assigned_identity_ids
# to also attach one or more user-assigned identities.
###############################################################
variable "user_assigned_identity_ids" {
  type        = list(string)
  description = "User-Assigned Managed Identity resource IDs to attach to the VM. Empty list = SystemAssigned only."
  default     = []
  nullable    = false
}

###############################################################
# DISK ENCRYPTION (CMK via Disk Encryption Set)
###############################################################
variable "disk_encryption_set_id" {
  type        = string
  description = "Disk Encryption Set resource ID used to encrypt OS and data disks with a customer-managed key. Null = platform-managed key."
  default     = null

  validation {
    condition     = var.disk_encryption_set_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/diskEncryptionSets/[^/]+$", var.disk_encryption_set_id))
    error_message = "disk_encryption_set_id must be a valid Disk Encryption Set resource ID."
  }
}

###############################################################
# DATA DISKS
# Map key is used as the data-disk suffix (e.g. "data01" → disk-vm-...-data01).
# LUNs must be unique per VM.
###############################################################
variable "data_disks" {
  type = map(object({
    disk_size_gb         = number
    lun                  = number
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadWrite")
    create_option        = optional(string, "Empty")
    # CKV_AZURE_251: secure-by-default — public network access to the disk's
    # underlying data (via SAS export/import) is DISABLED by default. Azure
    # platform default is true. Attached VM operation, backup/restore, and
    # resize are unaffected; only SAS-based public export/import is blocked.
    # Set true per-disk only when SAS export over the public internet is required.
    public_network_access_enabled = optional(bool, false)
  }))
  description = <<-EOT
  Data disks to create and attach to every VM. Map key becomes part of the disk name.
  Each disk is replicated for every VM in vm_count.
  - disk_size_gb                   : size in GiB
  - lun                            : LUN (must be unique per VM)
  - storage_account_type           : Standard_LRS | StandardSSD_LRS | Premium_LRS | PremiumV2_LRS | UltraSSD_LRS
  - caching                        : None | ReadOnly | ReadWrite
  - create_option                  : Empty | Copy | Restore (defaults to Empty)
  - public_network_access_enabled  : allow SAS export/import over the public internet (defaults to false — secure)
  EOT
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for d in values(var.data_disks) : contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "PremiumV2_LRS", "UltraSSD_LRS"], d.storage_account_type)])
    error_message = "data_disks[*].storage_account_type must be one of Standard_LRS, StandardSSD_LRS, Premium_LRS, PremiumV2_LRS, UltraSSD_LRS."
  }

  validation {
    condition     = alltrue([for d in values(var.data_disks) : contains(["None", "ReadOnly", "ReadWrite"], d.caching)])
    error_message = "data_disks[*].caching must be one of None, ReadOnly, ReadWrite."
  }

  validation {
    condition     = length(distinct([for d in values(var.data_disks) : d.lun])) == length(values(var.data_disks))
    error_message = "data_disks[*].lun values must be unique."
  }
}

###############################################################
# BOOT DIAGNOSTICS
# Default = Azure-managed storage (no SA URI required).
# Set boot_diagnostics_storage_account_uri to use a custom storage account.
###############################################################
variable "boot_diagnostics_enabled" {
  type        = bool
  description = "Enable boot diagnostics. Uses Azure-managed storage unless boot_diagnostics_storage_account_uri is set."
  default     = true
}

variable "boot_diagnostics_storage_account_uri" {
  type        = string
  description = "Custom storage account primary blob endpoint for boot diagnostics. Null = use Azure-managed storage."
  default     = null
}

###############################################################
# RESOURCE LOCK (F-6)
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) applied to each VM. Set to null to skip."
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
# ROLE ASSIGNMENTS (F-7)
###############################################################
variable "role_assignments" {
  description = "Map of role assignments to apply at each VM scope. Assignments are applied to EVERY VM in the pool (role_key × vm_key composite keys). Default principal_type='ServicePrincipal' for VM-scoped RBAC (e.g. granting access to managed identities)."
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

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources created by this module."
  default     = {}
  nullable    = false
}
