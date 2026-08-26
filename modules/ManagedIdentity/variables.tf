###############################################################
# MODULE: ManagedIdentity - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Explicit identity name. If null, computed from naming components."

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{2,127}$", var.name))
    error_message = "name must start with a letter or number, be 3-128 characters, and contain only alphanumerics, hyphens, or underscores."
  }

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (legacy resource), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. api, lfr, mgm)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name (e.g. aks, kubelet, wi-kv)"

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9_-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  nullable    = false
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "federated_identity_credentials" {
  description = <<-EOT
  A map of federated identity credentials to create. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `name`     - (Required) Name of the federated identity credential.
  - `audience` - (Optional) Token audiences. Defaults to ["api://AzureADTokenExchange"].
  - `issuer`   - (Required) The issuer URL (e.g. AKS OIDC issuer).
  - `subject`  - (Required) The subject identifier (e.g. system:serviceaccount:ns:sa).
  EOT
  type = map(object({
    name     = string
    audience = optional(list(string), ["api://AzureADTokenExchange"])
    issuer   = string
    subject  = string
  }))
  default  = {}
  nullable = false
}

variable "role_assignments" {
  description = <<-EOT
  A map of role assignments to create on this identity. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `role_definition_id_or_name`             - (Required) The ID or name of the role definition.
  - `scope`                                  - (Required) The scope to assign the role to.
  - `condition`                              - (Optional) ABAC condition for the role assignment.
  - `condition_version`                      - (Optional) Condition version. Valid values: "2.0".
  - `delegated_managed_identity_resource_id` - (Optional) Delegated managed identity for cross-tenant scenarios.
  - `description`                            - (Optional) Description of the role assignment.
  - `skip_service_principal_aad_check`       - (Optional) Skip AAD check for the service principal.
  EOT
  type = map(object({
    role_definition_id_or_name             = string
    scope                                  = string
    condition                              = optional(string)
    condition_version                      = optional(string)
    delegated_managed_identity_resource_id = optional(string)
    description                            = optional(string)
    # Defaults to true so the first apply does not race against AAD propagation
    # of the freshly-created UAMI principal_id. Override to false once the
    # identity is stable (subsequent applies have no propagation delay).
    skip_service_principal_aad_check = optional(bool, true)
  }))
  default  = {}
  nullable = false
}

variable "lock" {
  description = <<-EOT
  Controls the Resource Lock configuration for this resource.

  - `kind` - (Required) The type of lock. Possible values are "CanNotDelete" and "ReadOnly".
  - `name` - (Optional) The name of the lock. If not specified, generated from the kind value.
  EOT
  type = object({
    kind = string
    name = optional(string)
  })
  default = null

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags"
  default     = {}
  nullable    = false
}
