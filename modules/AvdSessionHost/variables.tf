###############################################################
# MODULE: AvdSessionHost - Variables
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

# F-12: explicit name override / XOR escape hatch
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

# F-11: nullable = false
variable "workload" {
  type        = string
  description = "Workload suffix for VM naming (e.g. sh for session host)."
  default     = "sh"
  nullable    = false
}

variable "computer_name_prefix" {
  type        = string
  description = "Windows computer name prefix (≤ 12 chars; 2 digits appended). Lowercase alphanumeric."
  default     = null

  validation {
    condition     = var.computer_name_prefix == null || can(regex("^[a-z][a-z0-9]{0,11}$", var.computer_name_prefix))
    error_message = "computer_name_prefix must be 1-12 lowercase alphanumeric chars (starts with a letter)."
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
  type     = string
  nullable = false

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
  description = "Number of session hosts to create."
  default     = 1

  validation {
    condition     = var.vm_count >= 1 && var.vm_count <= 100
    error_message = "vm_count must be between 1 and 100."
  }
}

variable "vm_size" {
  type        = string
  description = "VM size. D4s_v5 recommended for Win11 multi-session (min 4 vCPU)."
  default     = "Standard_D4s_v5"
}

variable "availability_zones" {
  type        = list(string)
  description = "Zones to spread VMs across (round-robin). Empty = no zone placement."
  default     = ["1", "2", "3"]
}

variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
  })
  description = "Marketplace image. Default: Win11 24H2 AVD multi-session (FSLogix pre-installed)."
  default = {
    publisher = "microsoftwindowsdesktop"
    offer     = "windows-11"
    sku       = "win11-24h2-avd"
    version   = "latest"
  }
}

variable "image_plan" {
  type = object({
    name      = string
    publisher = string
    product   = string
  })
  default     = null
  nullable    = true
  description = "Marketplace plan for images that require purchase terms (e.g. office-365/win11-25h2-avd-m365). Leave null for first-party images (windows-11/win11-*-avd) that need no plan. Terms must be accepted once: `az vm image terms accept`. Ignored when `source_image_id` is set."
}

variable "source_image_id" {
  type        = string
  default     = null
  nullable    = true
  description = "ID of a Compute Gallery image version (or Shared/Community Gallery image / version ID). If provided, it takes precedence over `image`/`image_plan` — the `source_image_reference` and `plan` blocks are suppressed. The custom image inherits Trusted Launch (Secure Boot + vTPM) from its gallery image definition, so `enable_trusted_launch` on the VM is unaffected."

  validation {
    condition     = var.source_image_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/galleries/[^/]+/images/[^/]+(/versions/[^/]+)?$", var.source_image_id)) || can(regex("^/(Community|Shared)Galleries/[^/]+/[Ii]mages/[^/]+(/[Vv]ersions/[^/]+)?$", var.source_image_id))
    error_message = "source_image_id must be a valid Compute Gallery image / image-version resource ID, or a Community/Shared Gallery image / version ID."
  }
}

variable "os_disk" {
  type = object({
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadWrite")
    disk_size_gb         = optional(number, 128)
    ephemeral            = optional(bool, true) # D4s_v5 has 150 GiB temp — fits 128 GiB ephemeral
  })
  default = {}
}

variable "accelerated_networking_enabled" {
  type        = bool
  description = "Enable Accelerated Networking on the session host NICs. Most ≥ D4s_v5 sizes support it; required for production AVD performance. Set to false only for VM sizes that do not support SR-IOV."
  default     = true
}

variable "admin_username" {
  type        = string
  description = "Local admin username (for break-glass access)."
  default     = "azureadmin"
}

variable "admin_password_kv_id" {
  type        = string
  description = "Key Vault ID holding the local admin password secret."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", var.admin_password_kv_id))
    error_message = "admin_password_kv_id must be a valid Key Vault resource ID."
  }
}

variable "admin_password_secret_name" {
  type        = string
  description = "Name of the Key Vault secret holding the local admin password."
  default     = "sh-local-admin-password"
}

variable "enable_trusted_launch" {
  type        = bool
  description = "Enable Trusted Launch (vTPM + Secure Boot). Recommended."
  default     = true
}

variable "license_type" {
  type        = string
  description = <<-EOT
  Azure Hybrid Benefit license type. For AVD multi-session (Windows Client),
  set "Windows_Client" to consume the AHB / M365 entitlement and avoid
  paying the full Windows VM compute price. For Windows Server SKUs, use
  "Windows_Server" or "None".
  Allowed: "Windows_Client", "Windows_Server", "None".
  EOT
  default     = "Windows_Client"

  validation {
    condition     = contains(["Windows_Client", "Windows_Server", "None"], var.license_type)
    error_message = "license_type must be 'Windows_Client', 'Windows_Server', or 'None'."
  }
}

variable "patch_mode" {
  type        = string
  description = <<-EOT
  Patch orchestration mode. AutomaticByPlatform aligns with Azure Update
  Manager and is the modern Microsoft recommendation for AVD; pair with
  bypass_platform_safety_checks_on_user_schedule = true and a maintenance
  configuration if you orchestrate patching from outside the VM.
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
  description = "When patch_mode = AutomaticByPlatform, set true to defer to a user-defined maintenance configuration (Update Manager) instead of platform-managed safety checks."
  default     = true
}

variable "hotpatching_enabled" {
  type        = bool
  description = "Enable hotpatching where supported (Win11 24H2+ multi-session, Server 2022 Datacenter Azure Edition). Reduces reboots required for security patches."
  default     = false
}

# F-2: encryption_at_host_enabled — CAF secure default = true
variable "encryption_at_host_enabled" {
  description = "Enable host-level encryption (additional layer over disk SSE). CAF baseline = true. Requires Az.Compute feature 'EncryptionAtHost' registered + VM SKU support (most modern Dsv3+/Esv3+ SKUs support it; check the SKU table). Setting this to true is Azure-immutable post-VM-create — a flip from false to true on an existing VM requires destroy+recreate (state surgery required, NOT done by Terraform automatically)."
  type        = bool
  default     = true
  nullable    = false
}

###############################################################
# AVD AGENT / SESSION HOST REGISTRATION
###############################################################
variable "hostpool_name" {
  type        = string
  description = "Host pool name to register the session host with (passed to AVD DSC)."
  nullable    = false
}

variable "hostpool_registration_token" {
  type        = string
  description = "Registration token from azurerm_virtual_desktop_host_pool_registration_info."
  sensitive   = true
  nullable    = false
}

variable "avd_dsc_artifact_url" {
  type        = string
  description = "URL of the AVD DSC Configuration.zip (Azure-hosted artifact)."
  default     = "https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02990.697.zip"
}

###############################################################
# FSLOGIX CONFIGURATION (registry via CustomScriptExtension)
###############################################################
variable "fslogix_vhd_location" {
  type        = string
  description = "SMB UNC path to FSLogix profiles share (e.g. \\\\\\\\<sa>.file.core.windows.net\\\\profiles)."
  nullable    = false
}

variable "fslogix_profile_size_mb" {
  type        = number
  description = "FSLogix container max size in MB."
  default     = 30000
}

###############################################################
# RESOURCE LOCK (F-5)
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) applied to each session host VM. Set to null to skip."
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
# ROLE ASSIGNMENTS (F-6)
###############################################################
variable "role_assignments" {
  description = "Map of role assignments to apply at each VM scope. Common AVD roles: 'Virtual Machine User Login' / 'Virtual Machine Administrator Login' for AAD-joined hosts. Assignments are applied to EVERY session host VM in the pool (role_key × vm_key composite keys). For external/cross-module scoping, layer ../RoleAssignment directly."
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string, "Group")
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
# TAGS (F-10)
###############################################################
# F-10: nullable = false
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags applied to all taggable resources in this module."
}
