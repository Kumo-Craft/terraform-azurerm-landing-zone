###############################################################
# MODULE: ComputeGallery - Variables
###############################################################

###############################################################
# NAMING
# Azure Compute Gallery (Shared Image Gallery) names disallow
# hyphens — the upstream Azure/naming/azurerm handles that per-type
# (prefix `gal`, no dashes).
#
# XOR escape hatch:
#   var.gallery_name != null → explicit name, ../Naming not instantiated
#   var.gallery_name == null → all 4 convention components required
###############################################################

variable "gallery_name" {
  type        = string
  default     = null
  nullable    = true
  description = "Explicit Compute Gallery name override (escape hatch). If set, bypasses ../Naming. If null, the name is derived from the convention via ../Naming (result.shared_image_gallery.name). Gallery names allow letters, digits, '.', '_' — NO hyphens."

  validation {
    condition     = var.gallery_name != null || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    error_message = "Either var.gallery_name must be set (escape hatch) OR all 4 naming components (subscription_acronym, environment, region_code, workload) must be non-null."
  }

  validation {
    condition     = var.gallery_name == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._]{0,78}[a-zA-Z0-9])?$", var.gallery_name))
    error_message = "gallery_name must be 1-80 chars of letters, digits, '.' or '_' (start/end alphanumeric). Hyphens are not allowed for Compute Galleries."
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
  description = "Workload suffix for the gallery name (e.g. avd)."
  default     = "avd"
  nullable    = false
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

###############################################################
# GALLERY
###############################################################
variable "gallery_description" {
  type        = string
  description = "Optional description for the Compute Gallery."
  default     = null
}

###############################################################
# IMAGE DEFINITION (optional — null = gallery only)
###############################################################
variable "image_definition_name" {
  type        = string
  description = "Name of the image definition to create in the gallery (e.g. win11-avd-m365-dev). Set to null to create the gallery only (no image definition)."
  default     = null

  validation {
    condition     = var.image_definition_name == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9])?$", var.image_definition_name))
    error_message = "image_definition_name must be 1-80 chars of letters, digits, '.', '_' or '-' (start/end alphanumeric)."
  }
}

variable "image_identifier" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
  })
  description = "The image definition identifier (publisher/offer/sku). This triple must be unique within the gallery and is immutable."
  default = {
    publisher = "POST"
    offer     = "win11-avd-m365"
    sku       = "dev"
  }
}

variable "os_type" {
  type        = string
  description = "OS type of the image definition."
  default     = "Windows"

  validation {
    condition     = contains(["Windows", "Linux"], var.os_type)
    error_message = "os_type must be 'Windows' or 'Linux'."
  }
}

variable "hyper_v_generation" {
  type        = string
  description = "Hyper-V generation. V2 is required for Trusted Launch / Confidential VM and recommended for Win11 + AVD."
  default     = "V2"

  validation {
    condition     = contains(["V1", "V2"], var.hyper_v_generation)
    error_message = "hyper_v_generation must be 'V1' or 'V2'."
  }
}

variable "architecture" {
  type        = string
  description = "CPU architecture supported by the image."
  default     = "x64"

  validation {
    condition     = contains(["x64", "Arm64"], var.architecture)
    error_message = "architecture must be 'x64' or 'Arm64'."
  }
}

# The azurerm_shared_image resource allows AT MOST ONE of
# trusted_launch_supported / trusted_launch_enabled /
# confidential_vm_supported / confidential_vm_enabled. Expose a single
# enum and map it to the right flag in main.tf so callers can't set a
# conflicting combination.
variable "security_type" {
  type        = string
  description = <<-EOT
  Security type of the image definition. Maps to exactly one azurerm flag:
    - "Standard"                -> none (legacy Gen2 / Gen1)
    - "TrustedLaunchSupported"  -> trusted_launch_supported  (image can be used for BOTH Trusted Launch and standard Gen2 VMs) [default]
    - "TrustedLaunch"           -> trusted_launch_enabled    (image REQUIRES Trusted Launch)
    - "ConfidentialVmSupported" -> confidential_vm_supported
    - "ConfidentialVm"          -> confidential_vm_enabled
  Default matches AVD session hosts built with Trusted Launch (secure_boot + vTPM inherited from the definition).
  EOT
  default     = "TrustedLaunchSupported"

  validation {
    condition     = contains(["Standard", "TrustedLaunchSupported", "TrustedLaunch", "ConfidentialVmSupported", "ConfidentialVm"], var.security_type)
    error_message = "security_type must be one of: Standard, TrustedLaunchSupported, TrustedLaunch, ConfidentialVmSupported, ConfidentialVm."
  }
}

variable "image_description" {
  type        = string
  description = "Optional description for the image definition."
  default     = null
}

variable "purchase_plan" {
  type = object({
    name      = string
    publisher = optional(string)
    product   = optional(string)
  })
  default     = null
  nullable    = true
  description = "Optional marketplace purchase plan for the image definition. Required when the image is derived from a paid/3rd-party marketplace offer that carries a plan (e.g. the office-365 M365 AVD image). Leave null for first-party / custom images."
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags applied to the gallery and image definition."
}
