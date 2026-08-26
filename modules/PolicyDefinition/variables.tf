###############################################################
# MODULE: PolicyDefinition - Variables
# Creates custom Azure Policy Definitions scoped to either a
# Subscription (provider default) or a Management Group.
# Each entry carries its own scope, so one deployment can
# cover multiple scopes in one apply.
###############################################################

variable "definitions" {
  type = map(object({
    # Required
    display_name = string
    policy_rule  = any # caller passes as object/map; module jsonencodes

    # Scope — null = subscription-scoped (provider's subscription),
    #         else full MG resource ID = MG-scoped
    management_group_id = optional(string)

    # Optional
    description = optional(string)
    mode        = optional(string, "All")
    metadata    = optional(map(string))
    parameters  = optional(any) # caller passes as object/map; module jsonencodes
    policy_type = optional(string, "Custom")
  }))
  nullable = false

  description = <<-EOT
  Map of custom policy definitions. Key = definition name (Azure-side resource name; semantic logical key).

  Scope: omit management_group_id for subscription-scoped definitions; set it for MG-scoped.

  - display_name        : (Required) Human-readable name visible in the portal.
  - policy_rule         : (Required) The policy rule as a Terraform object — module jsonencodes it.
                          Example: { if = { field = "type", equals = "Microsoft.Compute/virtualMachines" }, then = { effect = "audit" } }
  - description         : (Optional) Description visible in the portal.
  - mode                : (Optional, default "All") Evaluation mode.
                          Enum: All, Indexed, Microsoft.Kubernetes.Data, Microsoft.KeyVault.Data, Microsoft.Network.Data.
  - metadata            : (Optional) Free-form key-value metadata. Module jsonencodes.
  - parameters          : (Optional) Parameter definitions as Terraform object — module jsonencodes.
                          Example: { tagName = { type = "String", metadata = { displayName = "Tag Name" } } }
  - policy_type         : (Optional, default "Custom") Enum: Custom, BuiltIn, NotSpecified, Static.
                          Almost always Custom for caller-authored definitions.
  - management_group_id : (Optional) When set, definition is MG-scoped. Omit for subscription scope.
  EOT

  validation {
    condition = alltrue([
      for d in var.definitions :
      contains(["Custom", "BuiltIn", "NotSpecified", "Static"], d.policy_type)
    ])
    error_message = "policy_type must be one of: Custom, BuiltIn, NotSpecified, Static."
  }

  validation {
    condition = alltrue([
      for d in var.definitions :
      contains(["All", "Indexed", "Microsoft.Kubernetes.Data", "Microsoft.KeyVault.Data", "Microsoft.Network.Data"], d.mode)
    ])
    error_message = "mode must be one of: All, Indexed, Microsoft.Kubernetes.Data, Microsoft.KeyVault.Data, Microsoft.Network.Data."
  }

  validation {
    condition     = alltrue([for k in keys(var.definitions) : length(k) <= 64])
    error_message = "Policy definition names (map keys) must not exceed 64 characters (Azure API limit)."
  }

  validation {
    condition = alltrue([
      for d in var.definitions :
      length(d.display_name) <= 128
    ])
    error_message = "display_name must not exceed 128 characters (Azure API limit)."
  }

  validation {
    condition = alltrue([
      for d in var.definitions :
      d.management_group_id == null || can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", d.management_group_id))
    ])
    error_message = "management_group_id must be a valid Azure Management Group resource ID (/providers/Microsoft.Management/managementGroups/<name>)."
  }
}
