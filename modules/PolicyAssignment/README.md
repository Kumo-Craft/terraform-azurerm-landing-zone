# PolicyAssignment

Map-shape module dispatching Azure Policy assignments to one of three scopes (Management Group, Subscription, Resource Group) per entry, with optional managed identity and inline role grants for DINE/Modify effects.

## Usage

### Standalone

```hcl
module "policy_assignments" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/PolicyAssignment?ref=v0.2.10"

  assignments = {
    "require-tag-environment" = {
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/<id>"
      subscription_id      = "/subscriptions/<guid>"
      display_name         = "Require Environment tag"
      enforce              = true
      parameters = {
        tagName = "Environment"
      }
    }

    "deploy-log-analytics" = {
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/<dine-id>"
      resource_group_id    = "/subscriptions/<guid>/resourceGroups/<rg-name>"
      display_name         = "Deploy LAW"
      enforce              = true
      identity_type        = "SystemAssigned"
      location             = "germanywestcentral"
      not_scopes           = []
      role_assignments = [
        {
          scope                = "/subscriptions/<guid>/resourceGroups/<rg-name>"
          role_definition_name = "Log Analytics Contributor"
        }
      ]
    }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PolicyAssignment"
}

inputs = {
  assignments = {
    # same shape as above
  }
}
```

## Scope dispatch

Each assignment entry MUST specify EXACTLY ONE of:
- `management_group_id` — assignment to a Management Group
- `subscription_id` — assignment to a Subscription
- `resource_group_id` — assignment to a Resource Group

The module validates this via `length(compact([...])) == 1` and dispatches to the appropriate `azurerm_*_policy_assignment` resource.

## Identity & role assignments

For policies with `DeployIfNotExists` or `Modify` effects, set `identity_type = "SystemAssigned"` and supply `location` (required by Azure when identity is enabled).

The module supports inline role grants via `role_assignments` — for each entry, a role is granted to the policy assignment's SystemAssigned identity. A 60-second `time_sleep` guards against RBAC propagation race conditions.

**Important constraints (validated at plan time)**:
- `role_assignments` requires `identity_type = "SystemAssigned"`. UserAssigned identities do not expose `principal_id` on the policy assignment resource — use the UAMI's principal_id with a separate `../RoleAssignment` call instead.
- `identity_ids` is required (non-empty list) when `identity_type = "UserAssigned"` — either per-entry or via module-level `var.default_identity_ids`.
- `location` is required when `identity_type` is set.

## Shared UAMI pattern (CAF recommendation)

For ALZ at scale, prefer a single User-Assigned Managed Identity shared across multiple DINE assignments instead of per-assignment SystemAssigned identities. This:
- Reduces SPN churn in Microsoft Entra ID
- Centralizes role management (grant roles once to the shared UAMI)
- Avoids the F-2 v0.2.10 caveat where SystemAssigned + role_assignments is the only validated path

**Composition pattern:**

```hcl
# 1. Create a shared UAMI for policy remediation
module "policy_uami" {
  source              = "../ManagedIdentity"
  resource_group_name = var.shared_rg_name
  location            = var.location
  workload            = "policy-shared"
}

# 2. Grant required roles to the UAMI (built-in roles only — CAF #9)
module "policy_uami_roles" {
  source = "../RoleAssignment"
  assignments = {
    "log-analytics-contributor" = {
      principal_id         = module.policy_uami.principal_id
      scope                = local.target_scope
      role_definition_name = "Log Analytics Contributor"
    }
    # ... other required built-in roles per the policy/initiative metadata
  }
}

# 3. Reference the shared UAMI on policy assignments
module "policy_assignments" {
  source               = "../PolicyAssignment"
  default_identity_ids = [module.policy_uami.id]

  assignments = {
    "deploy-law-vms" = {
      policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/<dine-id>"
      subscription_id      = "/subscriptions/<guid>"
      description          = "Deploy Log Analytics agent to all VMs (centralized monitoring)"
      identity_type        = "UserAssigned"
      # identity_ids omitted — falls back to default_identity_ids
      location             = "germanywestcentral"
      # NO role_assignments here — UAMI roles are managed centrally above
    }
  }
}
```

Per CAF Landing Zone identity recommendation #9: **policy remediation managed identities don't support custom role definitions**. Use built-in roles only.

## Breaking changes (v0.2.12)

### Mandatory `description` field

The `description` field on each `var.assignments` entry is now **required** (was optional in v0.2.11 and earlier). This aligns with CAF Landing Zone governance recommendations — every policy assignment must have a description visible in the Azure Portal compliance dashboard for audit purposes.

**Migration**: Add a `description` field to every entry in your `var.assignments` map. Example:

```hcl
assignments = {
  "deploy-log-analytics" = {
    policy_definition_id = "..."
    subscription_id      = "..."
    description          = "Deploy Log Analytics agent to all VMs for centralized monitoring (compliance: ISO 27001 A.12.1.3)"  # NEW: required
    # ... other fields
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

`var.assignments` — `map(object({...}))`, required. Key = assignment name (max 64 chars, must be unique within scope).

### Assignment Object Fields

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `resource_group_id` | `string` | null | One scope required | Full Azure RG resource ID: `/subscriptions/<sub-guid>/resourceGroups/<rg-name>` |
| `subscription_id` | `string` | null | One scope required | Full subscription path: `/subscriptions/<sub-guid>` |
| `management_group_id` | `string` | null | One scope required | Full MG resource ID: `/providers/Microsoft.Management/managementGroups/<id>` |
| `policy_definition_id` | `string` | — | Yes | Full resource ID. Accepts both individual policies and initiatives (policySetDefinitions). |
| `display_name` | `string` | — | Yes | Human-readable name shown in the portal (max 128 chars). |
| `description` | `string` | — | **Yes (v0.2.12+)** | Human-readable description for audit trail. Required for CAF compliance dashboard visibility. |
| `enforce` | `bool` | `true` | No | Set `false` for DoNotEnforce mode (assignment exists but does not audit/deny). |
| `parameters` | `map(any)` | null | No | Map of policy parameter name => value. Module wraps each value as `{ value = ... }` automatically. |
| `not_scopes` | `list(string)` | `[]` | No | List of scope IDs to exempt from this assignment. Useful for excluding child scopes (e.g. break-glass subscriptions from a deny assignment). |
| `metadata` | `string` | null | No | Free-form JSON-encoded string metadata visible in the portal. |
| `identity_type` | `string` | null | No | `"SystemAssigned"` or `"UserAssigned"`. Required when policy uses DINE/Modify effects. |
| `identity_ids` | `list(string)` | null | When `identity_type = "UserAssigned"` (unless `var.default_identity_ids` set) | List of User-Assigned Managed Identity resource IDs. Falls back to `var.default_identity_ids`. |
| `location` | `string` | null | When `identity_type` is set | Azure region for the managed identity. |
| `non_compliance_messages` | `list(object({content, policy_definition_reference_id?}))` | `[]` | No | Human-readable messages shown in compliance reports. |
| `role_assignments` | `list(object({scope, role_definition_name?, role_definition_id?}))` | `[]` | No | Role grants for the assignment's SystemAssigned identity. Built-in roles only (CAF #9). Only valid with `identity_type = "SystemAssigned"`. |
| `overrides` | `list(object({value, selectors?}))` | `[]` | No | Override the policy effect for this assignment (or specific definitions within an initiative). CAF Safe Deployment Practices — use to disable effects during canary rollout. |
| `resource_selectors` | `list(object({name, selectors?}))` | `[]` | No | Limit which resources are affected by this assignment. Filter by `resourceType`, `resourceLocation`, or `resourceWithoutLocation`. CAF Safe Deployment Practices — use for ring-based rollout. |

### Module-level inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `assignments` | `map(object({...}))` | — | Map of policy assignments (see table above). Key = assignment name (max 64 chars). |
| `default_identity_ids` | `list(string)` | null | Shared UAMI resource IDs applied to all `identity_type = "UserAssigned"` assignments that don't specify their own `identity_ids`. CAF Landing Zone identity recommendation #9. |

## Outputs

| Name | Description |
|------|-------------|
| `assignment_ids` | Map of assignment name => resource ID (across all scopes). |
| `identity_principal_ids` | Map of assignment name => managed identity principal ID. SystemAssigned: populated after first apply. UserAssigned: null (the provider does not expose UAMI principal_id on policy assignments — use the UAMI's own principal_id from the ManagedIdentity module instead). |
| `role_assignment_ids` | Map of `"<assignment_key>-<index>"` => role assignment resource ID created by inline `role_assignments` wiring. Empty when no role_assignments are configured. |
| `compliance_query_urls` | Map of assignment name => Azure Policy compliance REST query URL. Useful for audit scripts and external compliance dashboards. |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |
| time | >= 0.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| policy\_identity | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_management_group_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_resource_group_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_assignment) | resource |
| [azurerm_subscription_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_assignment) | resource |
| [time_sleep.role_assignment_propagation](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [azurerm_policy_definition.derived](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/policy_definition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| assignments | Map of policy assignments. Key = assignment name (must be unique within scope, max 64 chars).<br><br>Exactly ONE scope must be set per assignment:<br>  - resource\_group\_id   : full RG resource ID<br>  - subscription\_id     : full subscription path (/subscriptions/<guid>)<br>  - management\_group\_id : full MG resource ID<br><br>Other fields:<br>  - policy\_definition\_id : full resource ID. Accepts both:<br>      /providers/Microsoft.Authorization/policyDefinitions/<id>      (single policy)<br>      /providers/Microsoft.Authorization/policySetDefinitions/<id>   (initiative)<br>  - description          : (Required, v0.2.12+) Human-readable description for audit trail. CAF governance recommendation.<br>  - parameters           : map of policy parameter name => value. Module wraps each value<br>                           as Azure Policy expects: { name = { value = <value> } }.<br>  - enforce              : false = "DoNotEnforce" mode (assignment exists but doesn't audit/deny).<br>  - not\_scopes           : (Optional) List of scope IDs to exempt from this assignment. Useful for excluding child scopes (e.g. break-glass subscriptions from a deny assignment).<br>  - metadata             : (Optional) Free-form JSON-encoded string metadata visible in the portal.<br>  - identity\_type        : SystemAssigned or UserAssigned. Required when policy uses DINE/Modify.<br>  - location             : required if identity\_type is set.<br>  - non\_compliance\_messages : optional human-readable messages shown in compliance reports.<br>  - overrides            : (Optional) List of policy effect overrides. Each entry has `value` (override<br>                           value, e.g. "Disabled") and optional `selectors` to target specific policy<br>                           definitions within an initiative or specific resource locations.<br>                           CAF Safe Deployment Practices: use to disable effects during canary rollout.<br>  - resource\_selectors   : (Optional) List of resource selector sets that limit which resources are<br>                           affected. Each entry has `name` (identifier) and `selectors` (filter by<br>                           resourceType, resourceLocation, or resourceWithoutLocation).<br>                           CAF Safe Deployment Practices: use for ring-based rollout (e.g. deploy to<br>                           germanywestcentral first, then expand to all regions). | <pre>map(object({<br>    # ─── Scope — exactly ONE of the following must be set ────<br>    resource_group_id   = optional(string)<br>    subscription_id     = optional(string)<br>    management_group_id = optional(string)<br><br>    # ─── Assignment details ──────────────────────────────────<br>    policy_definition_id = string # accepts both individual policies and initiatives (policySetDefinitions)<br>    display_name         = string<br>    description          = string # (Required, v0.2.12+) Human-readable description for audit trail. CAF governance recommendation.<br>    enforce              = optional(bool, true)<br>    parameters           = optional(map(any)) # caller passes { effect = "audit" }; module wraps each value as { value = ... }<br>    not_scopes           = optional(list(string), [])<br>    metadata             = optional(string)<br><br>    # ─── Managed identity (DeployIfNotExists/Modify) ─────────<br>    # Required when the policy/initiative contains DINE or Modify<br>    # effects. Audit/Deny-only assignments don't need an identity.<br>    identity_type = optional(string)       # "SystemAssigned" or "UserAssigned"<br>    identity_ids  = optional(list(string)) # required when identity_type = "UserAssigned"; falls back to var.default_identity_ids<br>    location      = optional(string)       # required when identity_type is set<br><br>    non_compliance_messages = optional(list(object({<br>      content                        = string<br>      policy_definition_reference_id = optional(string)<br>    })), [])<br><br>    # ─── Role assignments for the assignment's identity (DINE/Modify) ────<br>    # Required when the policy/initiative needs to deploy or modify<br>    # resources outside its own scope (e.g. write to a central storage<br>    # account, attach flow logs on VNets). Each entry creates an<br>    # azurerm_role_assignment with principal_id = this assignment's<br>    # SystemAssigned identity.<br>    #<br>    # Specify exactly ONE of role_definition_name (built-in role) or<br>    # role_definition_id (custom role definition GUID).<br>    role_assignments = optional(list(object({<br>      scope                = string           # full Azure resource ID at which to grant the role<br>      role_definition_name = optional(string) # built-in role display name (e.g. "Contributor")<br>      role_definition_id   = optional(string) # GUID for built-in or custom roles<br>    })), [])<br><br>    # ─── Cat 5 #12 (v0.2.89, opt-in NON-BREAKING) ───────────────<br>    # When true, the module fetches the policy definition at plan<br>    # time via `data.azurerm_policy_definition` and reads the<br>    # `role_definition_ids` attribute that the azurerm provider<br>    # pre-parses from the policy's built-in metadata.<br>    # The derived role IDs are MERGED with any explicit<br>    # role_assignments[] entries above.<br>    #<br>    # Only effective when:<br>    #   - identity_type = "SystemAssigned"<br>    #   - policy_definition_id refers to a single built-in policy<br>    #     (not a policySetDefinition / initiative)<br>    #   - the built-in definition declares roleDefinitionIds in its<br>    #     metadata (DINE and Modify effects typically do)<br>    #<br>    # Auto-scope: the derived role assignments are granted at the<br>    # same scope as the policy assignment itself.<br>    #<br>    # Default = false → existing callers are unaffected (NON-BREAKING).<br>    auto_derive_roles_from_definition = optional(bool, false)<br><br>    # ─── Safe Deployment Practices (CAF) ────────────────────<br>    # overrides: override the policy effect for this assignment, or for<br>    # specific policy definitions within an initiative. Each entry maps<br>    # to an azurerm `overrides` block. The `value` is the override value<br>    # (e.g. "Disabled", "Audit"). Use `selectors` to target specific<br>    # definitions within an initiative by policyDefinitionReferenceId or<br>    # limit to specific resourceLocations.<br>    overrides = optional(list(object({<br>      value = string # the override value (e.g. "Disabled", "Audit", "AuditIfNotExists")<br>      selectors = optional(list(object({<br>        kind   = optional(string) # "policyDefinitionReferenceId" or "resourceLocation"<br>        in     = optional(list(string))<br>        not_in = optional(list(string))<br>      })), [])<br>    })), [])<br><br>    # resource_selectors: limit the assignment's effect to a subset of<br>    # resources matched by resourceType, resourceLocation, or<br>    # resourceWithoutLocation. Used for canary/ring rollouts (deploy to<br>    # one region first, then expand). CAF Safe Deployment Practices.<br>    resource_selectors = optional(list(object({<br>      name = string # arbitrary identifier (used as a label in the portal)<br>      selectors = optional(list(object({<br>        kind   = optional(string) # "resourceType", "resourceLocation", or "resourceWithoutLocation"<br>        in     = optional(list(string))<br>        not_in = optional(list(string))<br>      })), [])<br>    })), [])<br>  }))</pre> | n/a | yes |
| default\_identity\_ids | Optional list of User-Assigned Managed Identity resource IDs to apply by default to all<br>assignments that use `identity_type = "UserAssigned"` AND don't specify their own `identity_ids`.<br><br>CAF Landing Zone identity recommendation #9 — at scale, prefer a single shared UAMI across<br>multiple policy assignments (reduces SPN churn, simpler role management vs SystemAssigned per<br>assignment).<br><br>Per-entry `identity_ids` (in `var.assignments[k].identity_ids`) takes precedence when set. | `list(string)` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| assignment\_ids | Map of assignment name => resource ID (across all scopes). |
| compliance\_query\_urls | Map of assignment name => Azure Policy compliance API query URL (REST GET). Useful for audit scripts and external compliance dashboards. |
| identity\_principal\_ids | Map of assignment name => managed identity principal ID. SystemAssigned: populated after first apply. UserAssigned: null (the provider does not expose UAMI principal\_id on policy assignments — use the UAMI's own principal\_id from the ManagedIdentity module instead). |
| role\_assignment\_ids | Map of "<assignment\_key>-<index>" => role assignment resource ID created by the inline role\_assignments wiring. Empty when no role\_assignments are configured. |
<!-- END_TF_DOCS -->
