###############################################################
# MODULE: Vm-Custom - Variables
# Linux VM with flexible image source (marketplace OR custom /
# Shared Image Gallery), SSH-key auth, Trusted Launch, host
# encryption, optional CMK disks + data disks, and Entra ID SSH
# login. Companion to Vm-Windows.
#
# NAMING
# Azure VM:  vm-{sub_acronym}-{env}-{region_code}-{workload}-{index}
#
# XOR escape hatch:
#   var.name != null  → explicit base name, ../Naming not instantiated
#   var.name == null  → all 4 convention components required
###############################################################

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
  type    = string
  default = null

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9-]{0,29}$", var.workload))
    error_message = "workload must be 1 to 30 characters: lowercase letters, digits, hyphens."
  }
}

variable "computer_name_prefix" {
  type        = string
  description = "Optional explicit Linux hostname prefix (the per-VM index is appended). If null, derived from workload/environment or the VM base name."
  default     = null
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name."
  nullable    = false
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the VM NIC(s)."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet resource ID."
  }
}

variable "vm_count" {
  type        = number
  description = "Number of Linux VMs to create."
  default     = 1

  validation {
    condition     = var.vm_count >= 1 && var.vm_count <= 100
    error_message = "vm_count must be between 1 and 100."
  }
}

variable "vm_size" {
  type        = string
  description = "VM size. D2s_v5 is a sensible general-purpose Linux default."
  default     = "Standard_D2s_v5"
}

variable "availability_zones" {
  type        = list(string)
  description = "Zones to spread VMs across (round-robin). Empty list = no zone placement."
  default     = ["1", "2", "3"]
}

###############################################################
# IMAGE
# Either a marketplace image (source_image_reference, with optional
# plan) OR a custom / Shared Image Gallery image (source_image_id).
# `source_image_id` takes precedence when set — the marketplace
# `image`/`image_plan` are then ignored.
###############################################################
variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
  })
  description = "Marketplace image reference. Default: Ubuntu Server 22.04 LTS (Gen2). Ignored when source_image_id is set."
  default = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  nullable = false
}

variable "image_plan" {
  type = object({
    name      = string
    publisher = string
    product   = string
  })
  default     = null
  description = "Marketplace plan for images that require purchase terms (paid/3rd-party offers). Leave null for first-party images (Ubuntu, RHEL PAYG, etc.). Ignored when source_image_id is set. Accept terms once: `az vm image terms accept`."
}

variable "source_image_id" {
  type        = string
  description = "Resource ID of a custom image, Shared/Community Image Gallery image, or gallery image version. When set, takes precedence over the marketplace `image`/`image_plan`."
  default     = null

  validation {
    condition     = var.source_image_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/(images|galleries)/", var.source_image_id)) || can(regex("^/communityGalleries/", var.source_image_id))
    error_message = "source_image_id must be a managed image ID, a Shared Image Gallery image/version ID, or a community gallery image ID."
  }
}

variable "os_disk" {
  type = object({
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadWrite")
    disk_size_gb         = optional(number, 64)
  })
  description = "OS disk configuration. Defaults to Premium_LRS 64 GiB, ReadWrite caching."
  default     = {}
  nullable    = false

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.os_disk.storage_account_type)
    error_message = "os_disk.storage_account_type must be Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS or Premium_ZRS."
  }

  validation {
    condition     = contains(["None", "ReadOnly", "ReadWrite"], var.os_disk.caching)
    error_message = "os_disk.caching must be None, ReadOnly or ReadWrite."
  }
}

variable "accelerated_networking_enabled" {
  type        = bool
  description = "Enable Accelerated Networking on the VM NIC. Set false for sizes that do not support SR-IOV."
  default     = true
}

variable "enable_trusted_launch" {
  type        = bool
  description = "Enable Trusted Launch (vTPM + Secure Boot). Microsoft-recommended for Gen2 Linux VMs. Requires a Gen2/Trusted Launch capable image and VM size."
  default     = true
}

variable "license_type" {
  type        = string
  description = "Optional Linux license type / Azure Hybrid Benefit. Allowed: RHEL_BYOS, RHEL_BASE, RHEL_EUS, RHEL_SAPAPPS, RHEL_SAPHA, RHEL_BASESAPAPPS, RHEL_BASESAPHA, SLES_BYOS, SLES_SAP, SLES_HPC, UBUNTU_PRO. Null = none (PAYG)."
  default     = null

  validation {
    condition     = var.license_type == null || contains(["RHEL_BYOS", "RHEL_BASE", "RHEL_EUS", "RHEL_SAPAPPS", "RHEL_SAPHA", "RHEL_BASESAPAPPS", "RHEL_BASESAPHA", "SLES_BYOS", "SLES_SAP", "SLES_HPC", "UBUNTU_PRO"], var.license_type)
    error_message = "license_type must be null or one of the supported Linux license types (RHEL_*, SLES_*, UBUNTU_PRO)."
  }
}

variable "patch_mode" {
  type        = string
  description = "Patch orchestration mode for Linux. Allowed: 'AutomaticByPlatform' (integrates with Azure Update Manager) or 'ImageDefault'."
  default     = "AutomaticByPlatform"

  validation {
    condition     = contains(["AutomaticByPlatform", "ImageDefault"], var.patch_mode)
    error_message = "patch_mode must be 'AutomaticByPlatform' or 'ImageDefault' (Linux supports only these two)."
  }
}

variable "bypass_platform_safety_checks_on_user_schedule" {
  type        = bool
  description = "When patch_mode = AutomaticByPlatform, defer to a user-defined maintenance configuration (Update Manager)."
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Enable host-based encryption (encrypts temp disk + OS/data disk caches at the hypervisor layer). CAF secure-by-default = true. Azure platform default is false; enabling on existing VMs requires stop/dealloc. Requires the EncryptionAtHost feature to be registered on the subscription."
  type        = bool
  default     = true
  nullable    = false
}

###############################################################
# ADMIN ACCESS
# SSH-key authentication (best practice). Password authentication
# is disabled unless a Key Vault password secret is supplied.
###############################################################
variable "admin_username" {
  type        = string
  description = "Local admin username for the Linux VM."
  default     = "azureadmin"
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key (ssh-rsa >= 2048-bit or ssh-ed25519) written to /home/<admin_username>/.ssh/authorized_keys."
  nullable    = false

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519) ", var.admin_ssh_public_key))
    error_message = "admin_ssh_public_key must start with 'ssh-rsa ' or 'ssh-ed25519 '."
  }
}

variable "admin_password_kv_id" {
  type        = string
  description = "Optional. Key Vault resource ID holding a local admin password secret. When set (with admin_password_secret_name), password authentication is ENABLED alongside the SSH key. Leave null to keep password auth disabled (recommended)."
  default     = null

  validation {
    condition     = var.admin_password_kv_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", var.admin_password_kv_id))
    error_message = "admin_password_kv_id must be a valid Key Vault resource ID."
  }
}

variable "admin_password_secret_name" {
  type        = string
  description = "Optional. Name of the Key Vault secret holding the local admin password. Required when admin_password_kv_id is set."
  default     = null

  validation {
    condition     = (var.admin_password_kv_id == null) == (var.admin_password_secret_name == null)
    error_message = "admin_password_kv_id and admin_password_secret_name must be set together (or both left null)."
  }
}

variable "entra_ssh_login_enabled" {
  type        = bool
  description = "Install the AADSSHLoginForLinux extension to enable Microsoft Entra ID SSH login (RBAC: Virtual Machine User/Administrator Login). Requires the SystemAssigned identity (always enabled by this module)."
  default     = true
}

###############################################################
# IDENTITY
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
# DATA DISK NETWORK ACCESS (secure-by-default — CKV_AZURE_251)
# Governs the disk data-plane (SAS import/export). VM attach/boot,
# backup/restore and resize are unaffected by these settings.
###############################################################
variable "disk_public_network_access_enabled" {
  type        = bool
  description = "Whether data disks are reachable via public network for SAS import/export. Secure default false (blocks public data-plane access — CKV_AZURE_251)."
  default     = false
  nullable    = false
}

variable "disk_network_access_policy" {
  type        = string
  description = "Network access policy for data disks (SAS import/export). 'DenyAll' (secure default — no SAS export/import at all), 'AllowPrivate' (SAS only via a Disk Access private endpoint — requires disk_access_id), or 'AllowAll'."
  default     = "DenyAll"
  nullable    = false

  validation {
    condition     = contains(["AllowAll", "AllowPrivate", "DenyAll"], var.disk_network_access_policy)
    error_message = "disk_network_access_policy must be AllowAll, AllowPrivate or DenyAll."
  }
}

variable "disk_access_id" {
  type        = string
  description = "Disk Access resource ID enabling private-endpoint SAS access to data disks. Only applied when disk_network_access_policy = 'AllowPrivate'."
  default     = null

  validation {
    condition     = var.disk_access_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/diskAccesses/[^/]+$", var.disk_access_id))
    error_message = "disk_access_id must be a valid Disk Access resource ID."
  }

  validation {
    condition     = var.disk_network_access_policy != "AllowPrivate" || var.disk_access_id != null
    error_message = "disk_access_id must be set when disk_network_access_policy = 'AllowPrivate'."
  }
}

###############################################################
# DATA DISKS
###############################################################
variable "data_disks" {
  type = map(object({
    disk_size_gb         = number
    lun                  = number
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadWrite")
    create_option        = optional(string, "Empty")
  }))
  description = <<-EOT
  Data disks to create and attach to every VM. Map key becomes part of the disk name.
  Each disk is replicated for every VM in vm_count.
  - disk_size_gb          : size in GiB
  - lun                   : LUN (must be unique per VM)
  - storage_account_type  : Standard_LRS | StandardSSD_LRS | Premium_LRS | PremiumV2_LRS | UltraSSD_LRS
  - caching               : None | ReadOnly | ReadWrite
  - create_option         : Empty | Copy | Restore (defaults to Empty)
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
# RESOURCE LOCK
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
# ROLE ASSIGNMENTS
###############################################################
variable "role_assignments" {
  description = "Map of role assignments to apply at each VM scope (applied to EVERY VM in the pool). Use 'Virtual Machine Administrator Login' / 'Virtual Machine User Login' with Entra SSH login."
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
