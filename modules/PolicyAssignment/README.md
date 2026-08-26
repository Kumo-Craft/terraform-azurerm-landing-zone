# PolicyAssignment

Map-shape module dispatching Azure Policy assignments to one of three scopes (Management Group, Subscription, Resource Group) per entry, with optional managed identity and inline role grants for DINE/Modify effects.

## Usage

### Standalone

```hcl
module "policy_assignments" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/PolicyAssignment?ref=v0.2.10"

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
