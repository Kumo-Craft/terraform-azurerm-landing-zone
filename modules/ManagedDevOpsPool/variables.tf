###############################################################
# MODULE: ManagedDevOpsPool - Variables
# Azure Managed DevOps Pool (Microsoft.DevOpsInfrastructure/pools)
# — a managed fleet of Azure DevOps agents, organized under a Dev
# Center project. Supports VNet injection (agents into an existing
# subnet) via virtual_machine_scale_set_fabric.subnet_id.
#
# NAMING
# Convention: mdp-{subscription_acronym}-{environment}-{region_code}-{workload}
#
# XOR escape hatch:
#   var.name != null  → explicit name used verbatim
#   var.name == null  → all 4 convention components required
###############################################################

variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit pool name (3-44 chars, alphanumerics/periods/hyphens, start alphanumeric, not ending in a period). If null, computed as mdp-{acr}-{env}-{region}-{workload}."

  validation {
    condition     = var.name == null || (length(var.name) >= 3 && length(var.name) <= 44 && can(regex("^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$", var.name)))
    error_message = "Pool name must be 3-44 chars: alphanumerics, periods, hyphens; start alphanumeric; not end with a period."
  }

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym for naming convention (e.g. mgm, api)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment for naming convention (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code for naming convention (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name for naming convention. Keep short — composed name must be <= 44 chars."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9-]{0,20}$", var.workload))
    error_message = "workload must be 1 to 21 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the Managed DevOps Pool will be deployed"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  nullable    = false
}

variable "dev_center_project_id" {
  type        = string
  description = "ID of the Dev Center Project that organizes this pool (e.g. module.dev_center_project.id). Managed DevOps Pools require a Dev Center project."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.devcenter/projects/[^/]+$", lower(var.dev_center_project_id)))
    error_message = "dev_center_project_id must be a valid Microsoft.DevCenter/projects resource ID."
  }
}

variable "maximum_concurrency" {
  type        = number
  description = "Maximum number of agent resources that can exist at any time (1-10000)."
  default     = 1

  validation {
    condition     = var.maximum_concurrency >= 1 && var.maximum_concurrency <= 10000
    error_message = "maximum_concurrency must be between 1 and 10000."
  }
}

###############################################################
# AZURE DEVOPS ORGANIZATIONS
###############################################################
variable "organizations" {
  description = <<-EOT
  One or more Azure DevOps organizations the pool serves. The sum of `parallelism`
  across organizations should equal `maximum_concurrency`.

  - `url`         - (Required) Azure DevOps org URL (e.g. https://dev.azure.com/contoso). Must end with a letter or number.
  - `parallelism` - (Optional) Max machines for this org (1-10000). Defaults to `maximum_concurrency`.
  - `projects`    - (Optional) Restrict the pool to these Azure DevOps project names. Empty = all projects.
  EOT
  type = list(object({
    url         = string
    parallelism = optional(number)
    projects    = optional(list(string), [])
  }))
  nullable = false

  validation {
    condition     = length(var.organizations) >= 1
    error_message = "At least one organization must be provided."
  }

  validation {
    condition     = alltrue([for o in var.organizations : can(regex("^https://", o.url))])
    error_message = "Each organization url must be an https:// URL."
  }
}

variable "permission" {
  description = <<-EOT
  Optional admin permission model for the pool.

  - `kind`                  - (Required) "Inherit" (Azure DevOps project admins) or "SpecificAccounts".
  - `administrator_groups`  - (Optional) Group email addresses (only with SpecificAccounts).
  - `administrator_users`   - (Optional) User email addresses (only with SpecificAccounts).
  EOT
  type = object({
    kind                 = string
    administrator_groups = optional(list(string), [])
    administrator_users  = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.permission == null || contains(["Inherit", "SpecificAccounts"], try(var.permission.kind, ""))
    error_message = "permission.kind must be 'Inherit' or 'SpecificAccounts'."
  }

  validation {
    condition     = var.permission == null || var.permission.kind != "SpecificAccounts" || (length(var.permission.administrator_groups) + length(var.permission.administrator_users)) > 0
    error_message = "When permission.kind is 'SpecificAccounts', at least one administrator group or user must be set."
  }
}

###############################################################
# FABRIC (VM Scale Set) — compute + NETWORK INJECTION
###############################################################
variable "sku_name" {
  type        = string
  description = "Azure VM SKU for the agent machines (e.g. Standard_D2ads_v5)."
  default     = "Standard_D2ads_v5"
  nullable    = false
}

variable "subnet_id" {
  type        = string
  description = <<-EOT
  Optional. Subnet ID to inject the agents into ("Agents injected into existing
  virtual network"). When null, the pool uses an isolated Microsoft-managed network.
  The subnet must be delegated to `Microsoft.DevOpsInfrastructure/pools`.
  EOT
  default     = null

  validation {
    condition     = var.subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet resource ID."
  }
}

variable "os_disk_storage_account_type" {
  type        = string
  description = "OS disk storage type for the agents. Possible values: Premium, Standard, StandardSSD."
  default     = "Premium"

  validation {
    condition     = contains(["Premium", "Standard", "StandardSSD"], var.os_disk_storage_account_type)
    error_message = "os_disk_storage_account_type must be 'Premium', 'Standard' or 'StandardSSD'."
  }
}

variable "images" {
  description = <<-EOT
  One or more images for the agents. Exactly one of `well_known_image_name` or `id`
  per image.

  - `well_known_image_name` - (Optional) Predefined alias (e.g. "ubuntu-22.04/latest", "windows-2022/latest").
  - `id`                    - (Optional) Resource ID of a custom / Azure Compute Gallery image.
  - `aliases`               - (Optional) Aliases to reference the image by.
  - `buffer`                - (Optional) Percentage of the standby buffer for this image ("*" or 0-100). Defaults to "*".
  EOT
  type = list(object({
    well_known_image_name = optional(string)
    id                    = optional(string)
    aliases               = optional(list(string), [])
    buffer                = optional(string, "*")
  }))
  default = [{
    well_known_image_name = "ubuntu-22.04/latest"
  }]
  nullable = false

  validation {
    condition     = length(var.images) >= 1
    error_message = "At least one image must be provided."
  }

  validation {
    condition     = alltrue([for i in var.images : (i.well_known_image_name != null) != (i.id != null)])
    error_message = "Each image must set EXACTLY ONE of well_known_image_name or id."
  }
}

variable "storage" {
  description = <<-EOT
  Optional additional data disk for the agents.

  - `disk_size_in_gb`       - (Required) 1-32767.
  - `caching`               - (Optional) ReadOnly or ReadWrite.
  - `drive_letter`          - (Optional) Windows drive letter.
  - `storage_account_type`  - (Optional) Premium_LRS, Premium_ZRS, Standard_LRS, StandardSSD_LRS, StandardSSD_ZRS. Defaults to Standard_LRS.
  EOT
  type = object({
    disk_size_in_gb      = number
    caching              = optional(string)
    drive_letter         = optional(string)
    storage_account_type = optional(string)
  })
  default = null
}

variable "interactive_logon_enabled" {
  type        = bool
  description = "Whether the agent runs in interactive mode (security block). Defaults to false."
  default     = false
}

###############################################################
# AGENT PROFILE (stateless vs stateful) + RESOURCE PREDICTION
###############################################################
variable "agent_type" {
  type        = string
  description = "Agent profile: 'stateless' (clean agent per job — recommended for CI) or 'stateful' (agents persist between jobs)."
  default     = "stateless"

  validation {
    condition     = contains(["stateless", "stateful"], var.agent_type)
    error_message = "agent_type must be 'stateless' or 'stateful'."
  }
}

variable "automatic_resource_prediction_enabled" {
  type        = bool
  description = "Enable automatic standby-agent prediction (Azure decides how many warm agents to keep). When false, no resource prediction block is set (agents created on demand)."
  default     = true
}

variable "prediction_preference" {
  type        = string
  description = "Cost/performance balance for automatic prediction. Possible values: MostCostEffective, MoreCostEffective, Balanced, MorePerformance, BestPerformance."
  default     = "Balanced"

  validation {
    condition     = contains(["MostCostEffective", "MoreCostEffective", "Balanced", "MorePerformance", "BestPerformance"], var.prediction_preference)
    error_message = "prediction_preference must be one of MostCostEffective, MoreCostEffective, Balanced, MorePerformance, BestPerformance."
  }
}

variable "manual_standby_agent_count" {
  type        = number
  default     = null
  description = "Mode Manual : nombre d'agents standby CHAUDS 24/7 (all_week_schedule). Si defini (>=1), prime sur l'Automatic. Doit etre entre 1 et maximum_concurrency."
  validation {
    condition     = var.manual_standby_agent_count == null || (var.manual_standby_agent_count >= 1 && var.manual_standby_agent_count <= var.maximum_concurrency)
    error_message = "manual_standby_agent_count doit etre entre 1 et maximum_concurrency."
  }
}

variable "manual_time_zone" {
  type        = string
  default     = "UTC"
  description = "Fuseau des plannings Manual. Defaut UTC."
}

variable "stateful_grace_period_time_span" {
  type        = string
  description = "Stateful only. Time an idle agent waits before shutting down (format dd.hh:mm:ss or hh:mm:ss)."
  default     = null
}

variable "stateful_maximum_agent_lifetime" {
  type        = string
  description = "Stateful only. Maximum lifetime of an agent before it is recycled (format dd.hh:mm:ss or hh:mm:ss)."
  default     = null
}

###############################################################
# IDENTITY
###############################################################
variable "identity_ids" {
  type        = list(string)
  description = "User-Assigned Managed Identity IDs to attach to the pool. Managed DevOps Pools only support UserAssigned identities. Empty list = no identity."
  default     = []
  nullable    = false
}

variable "work_folder" {
  type        = string
  description = "Optional work folder for every agent in the pool."
  default     = null
}

###############################################################
# LOCK & TAGS
###############################################################
variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = "Optional management lock (CanNotDelete or ReadOnly)."

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the Managed DevOps Pool"
  default     = {}
  nullable    = false
}
