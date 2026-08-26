###############################################################
# MODULE: Naming - Variables
# Description: Inputs for the house naming convention. The module
#              composes them into the `suffix` list expected by
#              Azure/naming/azurerm (the type prefix — kv-, cr, st,
#              etc. — is added by the upstream module per resource).
###############################################################

###############################################################
# NAMING CONVENTION (required segments)
# Final name pattern (per resource type, produced by the upstream
# module's outputs):
#   {type_prefix}-{subscription_acronym}-{environment}-{region_code}-{workload}
# Example for a Key Vault:
#   kv-shc-nprd-gwc-platform
###############################################################
variable "subscription_acronym" {
  type        = string
  description = "Subscription acronym for naming convention (e.g. mgm, con, idn, sec, shc)."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  description = "Environment for naming convention (e.g. prod, nprd). Automatically injected by root.hcl."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  description = "Region code for naming convention (e.g. gwc, weu). Automatically injected by root.hcl."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  description = "Workload identifier. Appended last in the suffix so a name reads {type}-{acr}-{env}-{region}-{workload}."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens (must start with a letter or digit)."
  }
}

###############################################################
# OPTIONAL — passthrough to Azure/naming/azurerm
###############################################################
variable "prefix" {
  type        = list(string)
  description = "Extra segments prepended BEFORE the upstream type prefix. Azure recommends suffixing rather than prefixing — leave empty unless you have a hard requirement."
  default     = []
  nullable    = false
}

variable "extra_suffix" {
  type        = list(string)
  description = "Extra suffix segments appended AFTER `workload`. Useful when you need an instance index or a sub-component qualifier (e.g. [\"01\"], [\"primary\"])."
  default     = []
  nullable    = false
}

variable "unique_length" {
  type        = number
  description = "Length of the random unique segment the upstream module appends. Defaults to 0 (deterministic names — same inputs always produce the same name). Set > 0 if you need collision resistance across deployments."
  default     = 0
  nullable    = false

  validation {
    condition     = var.unique_length >= 0 && var.unique_length <= 60
    error_message = "unique_length must be between 0 and 60."
  }
}

variable "unique_seed" {
  type        = string
  description = "Seed used when unique_length > 0. If null, the seed defaults to the composed suffix ({acr}-{env}-{region}-{workload}) so the random segment stays stable across applies for the same inputs."
  default     = null
}

variable "unique_include_numbers" {
  type        = bool
  description = "Allow digits in the random unique segment. Only relevant when unique_length > 0."
  default     = true
  nullable    = false
}
