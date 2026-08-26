###############################################################
# MODULE: PolicyRemediation - Variables
# Creates Azure Policy remediation tasks scoped to Management Groups,
# Subscriptions, Resource Groups, or individual Resources.
# Each entry carries its own scope, so one deployment can
# cover multiple scopes in one apply.
###############################################################

variable "remediations" {
  type = map(object({
    # Scope — EXACTLY ONE of these must be set per entry
    management_group_id = optional(string)
    subscription_id     = optional(string)
    resource_group_id   = optional(string)
    resource_id         = optional(string) # for azurerm_resource_policy_remediation

    # Required
    policy_assignment_id = string

    # Optional — initiative member targeting
    policy_definition_reference_id = optional(string)

    # Optional — behavior tuning (defaults per Azure API)
    resource_discovery_mode = optional(string, "ExistingNonCompliant")
    location_filters        = optional(list(string), [])
    resource_count          = optional(number, 500)
    parallel_deployments    = optional(number, 10)
    failure_percentage      = optional(number, 0.1)
  }))
  nullable = false

  description = <<-EOT
  Map of policy remediation tasks. Key = remediation task name (used as Azure-side resource name; semantic logical key, not convention-named).

  Exactly ONE of these scope IDs must be set per entry:
    - management_group_id : full MG resource ID
    - subscription_id     : full subscription path (/subscriptions/<guid>)
    - resource_group_id   : full RG resource ID
    - resource_id         : full ARM resource ID (for resource-level remediation)

  Other fields:
    - policy_assignment_id             : (Required) Full ARM resource ID of the policy assignment to remediate. Typically `module.policy_assignments.assignment_ids[<key>]` when composing.
    - policy_definition_reference_id   : (Optional) For initiatives — the policyDefinitionReferenceId of the member definition to remediate (one task per member). Look up from the initiative definition; not in PolicyAssignment outputs.
    - resource_discovery_mode          : (Optional, default "ExistingNonCompliant") Either "ExistingNonCompliant" (only existing non-compliant resources) or "ReEvaluateCompliance" (re-evaluate compliance before remediating). NOTE: "ReEvaluateCompliance" is NOT valid for management-group-scoped remediations (Azure API restriction — MG scope does not support resource_discovery_mode at all).
    - location_filters                 : (Optional, default []) POSITIVE allowlist — restrict remediation to resources IN these locations only. NOT an exclude filter. Empty list means all locations.
    - resource_count                   : (Optional, default 500) Max resources to remediate per task. Range 1-50000.
    - parallel_deployments             : (Optional, default 10) Concurrent deployments. Range 1-30.
    - failure_percentage               : (Optional, default 0.1) Failure threshold (0-1 = 0%-100%). Task halts if exceeded.

  RBAC propagation: Remediation tasks require the policy assignment's managed identity to have its role assignments propagated through Entra ID (~30-120s). When composing with `../PolicyAssignment`, use `depends_on = [module.pa]` to ensure the PolicyAssignment time_sleep completes first. Without it, first-apply race conditions cause silent task failures.

  Schema note: `resource_discovery_mode` is NOT a valid argument for management-group-scoped remediations (azurerm provider schema omits it from azurerm_management_group_policy_remediation). This module ignores that field for MG-scope entries; only "ExistingNonCompliant" behaviour applies at MG scope per Azure API.
  EOT

  # ===== Validators =====

  validation {
    condition = alltrue([
      for v in var.remediations :
      length(compact([v.management_group_id, v.subscription_id, v.resource_group_id, v.resource_id])) == 1
    ])
    error_message = "Each remediation must set exactly ONE of management_group_id, subscription_id, resource_group_id, or resource_id."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      contains(["ExistingNonCompliant", "ReEvaluateCompliance"], v.resource_discovery_mode)
    ])
    error_message = "resource_discovery_mode must be \"ExistingNonCompliant\" or \"ReEvaluateCompliance\"."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      !(v.management_group_id != null && v.resource_discovery_mode == "ReEvaluateCompliance")
    ])
    error_message = "resource_discovery_mode = \"ReEvaluateCompliance\" is not valid for management-group-scoped remediations (Azure API restriction — MG scope does not support resource_discovery_mode)."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      v.failure_percentage >= 0 && v.failure_percentage <= 1
    ])
    error_message = "failure_percentage must be between 0 and 1 (0% to 100%)."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      v.parallel_deployments >= 1 && v.parallel_deployments <= 30
    ])
    error_message = "parallel_deployments must be between 1 and 30."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      v.resource_count >= 1 && v.resource_count <= 50000
    ])
    error_message = "resource_count must be between 1 and 50000."
  }

  validation {
    condition = alltrue([
      for k in keys(var.remediations) : length(k) <= 64
    ])
    error_message = "Remediation task names (map keys) must not exceed 64 characters (Azure API limit)."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      v.management_group_id == null || can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", v.management_group_id))
    ])
    error_message = "management_group_id must be a valid Azure Management Group resource ID."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      v.subscription_id == null || can(regex("^/subscriptions/[0-9a-fA-F-]{36}$", v.subscription_id))
    ])
    error_message = "subscription_id must be a full subscription path: /subscriptions/<sub-guid>."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      v.resource_group_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", v.resource_group_id))
    ])
    error_message = "resource_group_id must be a full Azure RG resource ID: /subscriptions/<sub-guid>/resourceGroups/<rg-name>."
  }

  validation {
    condition = alltrue([
      for v in var.remediations :
      v.resource_id == null || can(regex("^/subscriptions/[^/]+/", v.resource_id))
    ])
    error_message = "resource_id must be a full Azure resource ARM ID starting with /subscriptions/."
  }
}
