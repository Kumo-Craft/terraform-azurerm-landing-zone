###############################################################
# MODULE: RoleDefinition - Variables
#
# Reusable custom (least-privilege) Azure role definition, with
# optional one-shot assignments. Use this for the custom roles you
# will accrue (restricted peering, DDoS plan operators, KV data-plane
# subsets, …) instead of an inline azurerm_role_definition per unit.
#
# BEST PRACTICE (Microsoft Learn — Azure RBAC / custom roles):
#   - Prefer BUILT-IN roles; create a custom role only when none fit.
#   - Least privilege: list actions EXPLICITLY, avoid wildcards ("*")
#     which also grant future actions.
#   - `assignable_scopes` = the broadest scope the role may be assigned
#     under (MG / subscription / resource group) — NOT a resource
#     instance (that burns the 5,000 custom-roles-per-tenant budget).
#     Then ASSIGN with a narrow scope.
###############################################################

variable "name" {
  type        = string
  description = "Display name of the custom role (must be unique within the tenant)."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 512
    error_message = "name must be 1 to 512 characters."
  }
}

variable "description" {
  type        = string
  default     = ""
  description = "Description of the role (shown in the portal)."
  nullable    = false
}

variable "scope" {
  type        = string
  description = <<-EOT
  CREATION scope of the role (subscription or management group ID). Must
  encompass every entry in `assignable_scopes`. It is automatically added to
  `assignable_scopes` if that list is empty. Changing this forces recreation.
  EOT
  nullable    = false

  validation {
    condition     = can(regex("^/(subscriptions|providers/Microsoft.Management/managementGroups)/", var.scope))
    error_message = "scope must be a subscription (/subscriptions/<id>[/resourceGroups/…]) or a management group (/providers/Microsoft.Management/managementGroups/<id>)."
  }
}

variable "actions" {
  type        = list(string)
  default     = []
  description = "Allowed control-plane actions (e.g. \"Microsoft.Network/virtualNetworks/peer/action\"). Prefer explicit actions over wildcards."
  nullable    = false
}

variable "not_actions" {
  type        = list(string)
  default     = []
  description = "Control-plane actions subtracted from `actions` (only meaningful when `actions` uses a wildcard). Not a deny rule."
  nullable    = false
}

variable "data_actions" {
  type        = list(string)
  default     = []
  description = "Allowed data-plane actions. NOTE: a role with data_actions cannot be assignable at a management-group scope (Azure restriction)."
  nullable    = false
}

variable "not_data_actions" {
  type        = list(string)
  default     = []
  description = "Data-plane actions subtracted from `data_actions`."
  nullable    = false
}

variable "assignable_scopes" {
  type        = list(string)
  default     = []
  description = <<-EOT
  Scopes where the role may be assigned. Empty = `[scope]`. Use MG /
  subscription / resource-group scopes, not resource instances. Azure allows
  AT MOST ONE management group in this list, and forbids management-group
  entries entirely when the role has data_actions.
  EOT
  nullable    = false
}

variable "assignments" {
  type = list(object({
    scope          = string
    principal_id   = string
    principal_type = optional(string, "ServicePrincipal")
  }))
  default     = []
  description = <<-EOT
  Optional role assignments created alongside the definition (handy for the
  one-shot "define + assign to this SPN" case). Each is delegated to the
  in-repo RoleAssignment module.

  - `scope`          - (Required) narrow scope to assign at (resource / RG / sub).
  - `principal_id`   - (Required) object ID of the principal.
  - `principal_type` - (Optional) User | Group | ServicePrincipal (default). For
                       ServicePrincipal the AAD existence pre-check is skipped to
                       avoid a first-apply race on freshly-created SPNs.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for a in var.assignments : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", a.principal_id))])
    error_message = "Each assignment principal_id must be a GUID (object ID)."
  }

  validation {
    condition     = alltrue([for a in var.assignments : contains(["User", "Group", "ServicePrincipal"], a.principal_type)])
    error_message = "assignment principal_type must be User, Group, or ServicePrincipal."
  }
}
