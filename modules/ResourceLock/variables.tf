###############################################################
# MODULE: ResourceLock - Variables
###############################################################

variable "locks" {
  description = <<-EOT
  A map of management locks to create. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `scope`      - (Required) Azure resource ID to lock (RG or resource).
  - `name`       - (Optional) Lock name. Defaults to "lock-<map-key>" when omitted.
  - `lock_level` - (Optional) Lock level: "CanNotDelete" or "ReadOnly". Defaults to "CanNotDelete".
  - `notes`      - (Optional) Lock description.

  WARNING: CanNotDelete locks also block `terraform destroy`.
  Set enable_locks = false for maintenance operations.
  EOT
  type = map(object({
    scope      = string
    name       = optional(string)
    lock_level = optional(string, "CanNotDelete")
    notes      = optional(string, "Lock applied by Terragrunt — Azure Landing Zone")
  }))
  nullable = false

  validation {
    condition = alltrue([
      for l in var.locks :
      can(regex("^/subscriptions/[^/]+($|/.+)$", l.scope)) ||
      can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", l.scope))
    ])
    error_message = "Each lock scope must be a valid Azure ID — subscription (/subscriptions/<guid>), resource group (/subscriptions/<guid>/resourceGroups/<name>), child resource (/subscriptions/<guid>/resourceGroups/<name>/providers/...), or management group (/providers/Microsoft.Management/managementGroups/<name>)."
  }

  validation {
    condition = alltrue([
      for l in var.locks :
      contains(["CanNotDelete", "ReadOnly"], l.lock_level)
    ])
    error_message = "lock_level must be either \"CanNotDelete\" or \"ReadOnly\"."
  }

  validation {
    condition = alltrue([
      for l in var.locks :
      l.name == null || length(l.name) <= 90
    ])
    error_message = "Lock name must not exceed 90 characters (Azure management lock hard limit)."
  }

  validation {
    condition = alltrue([
      for l in var.locks :
      l.notes == null || length(l.notes) <= 512
    ])
    error_message = "Lock notes must not exceed 512 characters (Azure management lock hard limit)."
  }
}

variable "enable_locks" {
  type        = bool
  default     = true
  description = "Set to false to disable all locks (e.g. for maintenance terraform destroy)."
}
