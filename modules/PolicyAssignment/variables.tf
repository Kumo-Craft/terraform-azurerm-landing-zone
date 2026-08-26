###############################################################
# MODULE: PolicyAssignment - Variables
# Creates Azure Policy assignments scoped to Resource Groups,
# Subscriptions, or Management Groups. Each assignment carries
# its own scope, so one deployment can cover multiple scopes
# in one apply (mirrors PolicyExemption pattern).
###############################################################

variable "assignments" {
  type = map(object({
    # ─── Scope — exactly ONE of the following must be set ────
    resource_group_id   = optional(string)
    subscription_id     = optional(string)
    management_group_id = optional(string)

    # ─── Assignment details ──────────────────────────────────
    policy_definition_id = string # accepts both individual policies and initiatives (policySetDefinitions)
    display_name         = string
    description          = string # (Required, v0.2.12+) Human-readable description for audit trail. CAF governance recommendation.
    enforce              = optional(bool, true)
    parameters           = optional(map(any)) # caller passes { effect = "audit" }; module wraps each value as { value = ... }
    not_scopes           = optional(list(string), [])
    metadata             = optional(string)

    # ─── Managed identity (DeployIfNotExists/Modify) ─────────
    # Required when the policy/initiative contains DINE or Modify
    # effects. Audit/Deny-only assignments don't need an identity.
    identity_type = optional(string)       # "SystemAssigned" or "UserAssigned"
    identity_ids  = optional(list(string)) # required when identity_type = "UserAssigned"; falls back to var.default_identity_ids
    location      = optional(string)       # required when identity_type is set

    non_compliance_messages = optional(list(object({
      content                        = string
      policy_definition_reference_id = optional(string)
    })), [])

    # ─── Role assignments for the assignment's identity (DINE/Modify) ────
    # Required when the policy/initiative needs to deploy or modify
    # resources outside its own scope (e.g. write to a central storage
    # account, attach flow logs on VNets). Each entry creates an
    # azurerm_role_assignment with principal_id = this assignment's
    # SystemAssigned identity.
    #
    # Specify exactly ONE of role_definition_name (built-in role) or
    # role_definition_id (custom role definition GUID).
    role_assignments = optional(list(object({
      scope                = string           # full Azure resource ID at which to grant the role
      role_definition_name = optional(string) # built-in role display name (e.g. "Contributor")
      role_definition_id   = optional(string) # GUID for built-in or custom roles
    })), [])

    # ─── Cat 5 #12 (v0.2.89, opt-in NON-BREAKING) ───────────────
    # When true, the module fetches the policy definition at plan
    # time via `data.azurerm_policy_definition` and reads the
    # `role_definition_ids` attribute that the azurerm provider
    # pre-parses from the policy's built-in metadata.
    # The derived role IDs are MERGED with any explicit
    # role_assignments[] entries above.
    #
    # Only effective when:
    #   - identity_type = "SystemAssigned"
    #   - policy_definition_id refers to a single built-in policy
    #     (not a policySetDefinition / initiative)
    #   - the built-in definition declares roleDefinitionIds in its
    #     metadata (DINE and Modify effects typically do)
    #
    # Auto-scope: the derived role assignments are granted at the
    # same scope as the policy assignment itself.
    #
    # Default = false → existing callers are unaffected (NON-BREAKING).
    auto_derive_roles_from_definition = optional(bool, false)

    # ─── Safe Deployment Practices (CAF) ────────────────────
    # overrides: override the policy effect for this assignment, or for
    # specific policy definitions within an initiative. Each entry maps
    # to an azurerm `overrides` block. The `value` is the override value
    # (e.g. "Disabled", "Audit"). Use `selectors` to target specific
    # definitions within an initiative by policyDefinitionReferenceId or
    # limit to specific resourceLocations.
    overrides = optional(list(object({
      value = string # the override value (e.g. "Disabled", "Audit", "AuditIfNotExists")
      selectors = optional(list(object({
        kind   = optional(string) # "policyDefinitionReferenceId" or "resourceLocation"
        in     = optional(list(string))
        not_in = optional(list(string))
      })), [])
    })), [])

    # resource_selectors: limit the assignment's effect to a subset of
    # resources matched by resourceType, resourceLocation, or
    # resourceWithoutLocation. Used for canary/ring rollouts (deploy to
    # one region first, then expand). CAF Safe Deployment Practices.
    resource_selectors = optional(list(object({
      name = string # arbitrary identifier (used as a label in the portal)
      selectors = optional(list(object({
        kind   = optional(string) # "resourceType", "resourceLocation", or "resourceWithoutLocation"
        in     = optional(list(string))
        not_in = optional(list(string))
      })), [])
    })), [])
  }))
  description = <<-EOT
  Map of policy assignments. Key = assignment name (must be unique within scope, max 64 chars).

  Exactly ONE scope must be set per assignment:
    - resource_group_id   : full RG resource ID
    - subscription_id     : full subscription path (/subscriptions/<guid>)
    - management_group_id : full MG resource ID

  Other fields:
    - policy_definition_id : full resource ID. Accepts both:
        /providers/Microsoft.Authorization/policyDefinitions/<id>      (single policy)
        /providers/Microsoft.Authorization/policySetDefinitions/<id>   (initiative)
    - description          : (Required, v0.2.12+) Human-readable description for audit trail. CAF governance recommendation.
    - parameters           : map of policy parameter name => value. Module wraps each value
                             as Azure Policy expects: { name = { value = <value> } }.
    - enforce              : false = "DoNotEnforce" mode (assignment exists but doesn't audit/deny).
    - not_scopes           : (Optional) List of scope IDs to exempt from this assignment. Useful for excluding child scopes (e.g. break-glass subscriptions from a deny assignment).
    - metadata             : (Optional) Free-form JSON-encoded string metadata visible in the portal.
    - identity_type        : SystemAssigned or UserAssigned. Required when policy uses DINE/Modify.
    - location             : required if identity_type is set.
    - non_compliance_messages : optional human-readable messages shown in compliance reports.
    - overrides            : (Optional) List of policy effect overrides. Each entry has `value` (override
                             value, e.g. "Disabled") and optional `selectors` to target specific policy
                             definitions within an initiative or specific resource locations.
                             CAF Safe Deployment Practices: use to disable effects during canary rollout.
    - resource_selectors   : (Optional) List of resource selector sets that limit which resources are
                             affected. Each entry has `name` (identifier) and `selectors` (filter by
                             resourceType, resourceLocation, or resourceWithoutLocation).
                             CAF Safe Deployment Practices: use for ring-based rollout (e.g. deploy to
                             germanywestcentral first, then expand to all regions).
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for a in var.assignments :
      length(compact([
        try(a.resource_group_id, null),
        try(a.subscription_id, null),
        try(a.management_group_id, null),
      ])) == 1
    ])
    error_message = "Each assignment must set exactly ONE of resource_group_id, subscription_id, or management_group_id."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      a.management_group_id == null || can(regex("^/providers/Microsoft\\.Management/managementGroups/[^/]+$", a.management_group_id))
    ])
    error_message = "management_group_id must be a valid Azure Management Group resource ID."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      a.resource_group_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", a.resource_group_id))
    ])
    error_message = "resource_group_id must be a full Azure RG resource ID: /subscriptions/<sub-guid>/resourceGroups/<rg-name>."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      a.subscription_id == null || can(regex("^/subscriptions/[0-9a-fA-F-]{36}$", a.subscription_id))
    ])
    error_message = "subscription_id must be a full subscription path: /subscriptions/<sub-guid>."
  }

  validation {
    condition     = alltrue([for k in keys(var.assignments) : length(k) <= 64])
    error_message = "Assignment names (map keys) must not exceed 64 characters (Azure API limit)."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      a.identity_type == null || contains(["SystemAssigned", "UserAssigned"], a.identity_type)
    ])
    error_message = "identity_type must be SystemAssigned or UserAssigned."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      a.identity_type == null || a.location != null
    ])
    error_message = "location is required when identity_type is set."
  }

  validation {
    condition = alltrue([
      for k, a in var.assignments :
      !(a.identity_type == "UserAssigned") || (
        (a.identity_ids != null && length(a.identity_ids) > 0) ||
        (var.default_identity_ids != null && length(var.default_identity_ids) > 0)
      )
    ])
    error_message = "identity_ids must be set (non-empty) when identity_type = \"UserAssigned\" — either per-entry or via module-level var.default_identity_ids."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      length(a.role_assignments) == 0 || a.identity_type != null
    ])
    error_message = "role_assignments require identity_type to be set (a managed identity must exist to be granted roles)."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      length(a.role_assignments) == 0 || a.identity_type == "SystemAssigned"
    ])
    error_message = "role_assignments can only be used with identity_type = \"SystemAssigned\" (UserAssigned identities do not expose principal_id on the policy assignment resource — use the UAMI's own principal_id and a separate RoleAssignment module call instead)."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      !a.auto_derive_roles_from_definition || a.identity_type == "SystemAssigned"
    ])
    error_message = "auto_derive_roles_from_definition = true requires identity_type = \"SystemAssigned\"."
  }

  validation {
    condition = alltrue([
      for a in var.assignments :
      a.display_name == null || length(a.display_name) <= 128
    ])
    error_message = "display_name must not exceed 128 characters (Azure API limit)."
  }

  validation {
    condition = alltrue([
      for a in var.assignments : alltrue([
        for ra in a.role_assignments :
        ra.role_definition_id == null ||
        can(regex("^/providers/Microsoft\\.Authorization/roleDefinitions/[0-9a-fA-F-]{36}$", ra.role_definition_id))
      ])
    ])
    error_message = "role_assignments[].role_definition_id must be a built-in role ID (/providers/Microsoft.Authorization/roleDefinitions/<guid>). CAF Landing Zone #9: policy remediation MIs do not support custom role definitions. If using role_definition_name instead, ensure the role is built-in."
  }

  validation {
    condition = alltrue([
      for a in var.assignments : alltrue([
        for ov in a.overrides : alltrue([
          for sel in ov.selectors :
          sel.kind == null || contains(["policyDefinitionReferenceId", "resourceLocation"], sel.kind)
        ])
      ])
    ])
    error_message = "overrides[].selectors[].kind must be one of: \"policyDefinitionReferenceId\", \"resourceLocation\"."
  }

  validation {
    condition = alltrue([
      for a in var.assignments : alltrue([
        for rs in a.resource_selectors : alltrue([
          for sel in rs.selectors :
          sel.kind == null || contains(["resourceType", "resourceLocation", "resourceWithoutLocation"], sel.kind)
        ])
      ])
    ])
    error_message = "resource_selectors[].selectors[].kind must be one of: \"resourceType\", \"resourceLocation\", \"resourceWithoutLocation\"."
  }
}

variable "default_identity_ids" {
  type        = list(string)
  default     = null
  description = <<-EOT
  Optional list of User-Assigned Managed Identity resource IDs to apply by default to all
  assignments that use `identity_type = "UserAssigned"` AND don't specify their own `identity_ids`.

  CAF Landing Zone identity recommendation #9 — at scale, prefer a single shared UAMI across
  multiple policy assignments (reduces SPN churn, simpler role management vs SystemAssigned per
  assignment).

  Per-entry `identity_ids` (in `var.assignments[k].identity_ids`) takes precedence when set.
  EOT
}
