###############################################################
# MODULE: AvdImageTemplate - Variables
#
# Azure Image Builder (AIB) template — Microsoft.VirtualMachineImages/
# imageTemplates. There is no native azurerm resource, so this is
# driven via azapi. No naming convention type exists upstream for
# image templates, so template_name is an explicit required input.
###############################################################

variable "template_name" {
  type        = string
  description = "Name of the image template."
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-_.]{1,64}$", var.template_name))
    error_message = "template_name must be 1-64 chars of letters, digits, '-', '_' or '.'."
  }
}

variable "location" {
  type        = string
  description = "Region where the image template (and the MS-managed build) runs. Must be a region the target gallery replicates to."
  nullable    = false
}

variable "resource_group_id" {
  type        = string
  description = "Resource ID of the resource group that holds the image template (azapi parent_id)."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.resource_group_id))
    error_message = "resource_group_id must be a resource group resource ID (/subscriptions/<id>/resourceGroups/<name>)."
  }
}

###############################################################
# IDENTITY
# AIB needs a User-Assigned Managed Identity with rights on the
# target gallery (image contributor) — imageTemplates only supports
# 'None' or 'UserAssigned' (no SystemAssigned).
###############################################################
variable "identity_ids" {
  type        = list(string)
  description = "User-assigned managed identity resource IDs granted to the image template. At least one; it must have permission to write image versions into the target gallery."
  nullable    = false

  validation {
    condition     = length(var.identity_ids) >= 1
    error_message = "At least one user-assigned identity ID is required."
  }

  validation {
    condition     = alltrue([for id in var.identity_ids : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ManagedIdentity/userAssignedIdentities/[^/]+$", id))])
    error_message = "Each identity_ids entry must be a user-assigned managed identity resource ID."
  }
}

###############################################################
# BUILD VM PROFILE
###############################################################
variable "build_timeout_minutes" {
  type        = number
  description = "Maximum build duration (all customizers + distribution). 0 = service default (4h)."
  default     = 120

  validation {
    condition     = var.build_timeout_minutes >= 0 && var.build_timeout_minutes <= 960
    error_message = "build_timeout_minutes must be between 0 and 960."
  }
}

variable "vm_size" {
  type        = string
  description = "Size of the ephemeral build VM. Pick a size available in var.location. Empty string = service default (Standard_D2ds_v4 for Gen2)."
  default     = "Standard_D4as_v7"
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size (GB) of the build VM. 0 = image default."
  default     = 128

  validation {
    condition     = var.os_disk_size_gb >= 0
    error_message = "os_disk_size_gb must be >= 0."
  }
}

variable "staging_resource_group_id" {
  type        = string
  description = "Optional staging resource group ID for the build. Null = AIB creates a randomly-named staging RG (MS-managed). If set, the RG must be empty and in the same region/subscription."
  default     = null
}

variable "auto_run_enabled" {
  type        = bool
  description = "When true, sets properties.autoRun.state = Enabled so Azure automatically starts a build on template CREATE or UPDATE (server-side, async — does not block the apply). Leave false and drive builds from a scheduled pipeline for cadence (rebuild from `latest`). Note: it re-triggers on every template update."
  default     = false
  nullable    = false
}

###############################################################
# SOURCE (base image) — PlatformImage
###############################################################
variable "source_image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
  })
  description = "Base marketplace (PlatformImage) image to build from. Default: the Win11 25H2 AVD M365 multi-session image."
  default = {
    publisher = "microsoftwindowsdesktop"
    offer     = "office-365"
    sku       = "win11-25h2-avd-m365"
    version   = "latest"
  }
}

variable "source_plan" {
  type = object({
    name      = string # planName
    product   = string # planProduct
    publisher = string # planPublisher
  })
  default     = null
  nullable    = true
  description = "Purchase plan (planInfo) for the source image. Required when the marketplace image carries purchase terms (the office-365 M365 AVD image does). Leave null for first-party images with no plan. Accept terms once: `az vm image terms accept`."
}

###############################################################
# CUSTOMIZERS
# Script-based customizers (PowerShell / Shell). Provide either
# script_uri OR inline per entry.
###############################################################
variable "customizers" {
  type = list(object({
    name             = string
    type             = optional(string, "PowerShell") # PowerShell | Shell
    script_uri       = optional(string)
    inline           = optional(list(string))
    sha256_checksum  = optional(string)
    run_elevated     = optional(bool)         # PowerShell only
    run_as_system    = optional(bool)         # PowerShell only
    valid_exit_codes = optional(list(number)) # PowerShell only
  }))
  description = "Ordered list of customization steps. Each provides script_uri (github/SAS URI) or inline commands. Trusted script hosting: use a SAS URI or a github raw URL reachable from the MS-managed build VM."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.customizers : contains(["PowerShell", "Shell"], c.type)])
    error_message = "Each customizer type must be 'PowerShell' or 'Shell'."
  }

  validation {
    condition     = alltrue([for c in var.customizers : (c.script_uri != null) != (c.inline != null)])
    error_message = "Each customizer must set exactly one of script_uri or inline."
  }

  validation {
    condition     = alltrue([for c in var.customizers : c.run_as_system != true || c.run_elevated == true])
    error_message = "run_as_system can only be true when run_elevated is also true."
  }
}

###############################################################
# DISTRIBUTION — SharedImage (Azure Compute Gallery)
###############################################################
variable "image_definition_id" {
  type        = string
  description = "galleryImageId — the Compute Gallery image DEFINITION ID (automatic versioning), e.g. .../galleries/<gal>/images/<def>. Append /versions/<x.y.z> for explicit versioning."
  nullable    = false

  validation {
    condition     = can(regex("/providers/Microsoft\\.Compute/galleries/[^/]+/images/[^/]+", var.image_definition_id))
    error_message = "image_definition_id must be a Compute Gallery image definition (or version) resource ID."
  }
}

variable "run_output_name" {
  type        = string
  description = "Unique runOutput name to query the distribution result. Null = defaults to template_name."
  default     = null

  validation {
    condition     = var.run_output_name == null || can(regex("^[A-Za-z0-9-_.]{1,64}$", var.run_output_name))
    error_message = "run_output_name must be 1-64 chars of letters, digits, '-', '_' or '.'."
  }
}

variable "target_regions" {
  type = list(object({
    name                 = string
    replica_count        = optional(number, 1)
    storage_account_type = optional(string, "Standard_LRS")
  }))
  description = "Gallery replication targets. One entry MUST be the gallery's home region. Empty = defaults to a single replica in var.location."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.target_regions : contains(["Standard_LRS", "Standard_ZRS", "Premium_LRS"], r.storage_account_type)])
    error_message = "target_regions[*].storage_account_type must be Standard_LRS, Standard_ZRS or Premium_LRS."
  }

  validation {
    condition     = alltrue([for r in var.target_regions : r.replica_count >= 1])
    error_message = "target_regions[*].replica_count must be >= 1."
  }
}

variable "exclude_from_latest" {
  type        = bool
  description = "If true, the produced image version is not marked as 'latest' in the gallery definition."
  default     = false
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags applied to the image template and set as distribution artifactTags."
}
