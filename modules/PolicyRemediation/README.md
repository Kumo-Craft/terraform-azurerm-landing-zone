# PolicyRemediation

Map-shape module dispatching Azure Policy remediation tasks to one of four scopes (Management Group, Subscription, Resource Group, or individual Resource) per entry. Designed to compose downstream of `../PolicyAssignment` for DINE / Modify effect remediation of existing non-compliant resources.

## Usage

### Standalone

```hcl
module "policy_remediation" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/PolicyRemediation?ref=v0.2.13"

  remediations = {
    "remediate-law-vms-prod-sub" = {
      subscription_id         = "/subscriptions/<sub-guid>"
      policy_assignment_id    = "/subscriptions/<sub-guid>/providers/Microsoft.Authorization/policyAssignments/deploy-law-vms"
      resource_discovery_mode = "ExistingNonCompliant" # default
      parallel_deployments    = 20
      failure_percentage      = 0.05 # 5% failure threshold
    }

    "remediate-initiative-member-prod-rg" = {
      resource_group_id              = "/subscriptions/<sub-guid>/resourceGroups/rg-workload"
      policy_assignment_id           = "/subscriptions/<sub-guid>/resourceGroups/rg-workload/providers/Microsoft.Authorization/policyAssignments/asb-baseline"
      policy_definition_reference_id = "deploySqlTdeAuditing" # specific member of ASB initiative
    }
  }
}
```

### Composition with `../PolicyAssignment` (CANONICAL pattern)

```hcl
module "pa" {
  source      = "../PolicyAssignment"
  assignments = { ... }
}

module "remediation" {
  source     = "../PolicyRemediation"
  depends_on = [module.pa] # CRITICAL: waits for PolicyAssignment's 60s time_sleep on RBAC propagation

  remediations = {
    "remediate-deploy-law" = {
      subscription_id      = "/subscriptions/<guid>" # scope must be re-specified (not in PolicyAssignment outputs)
      policy_assignment_id = module.pa.assignment_ids["deploy-law"]
    }
  }
}
```

**Without `depends_on = [module.pa]`**, first-apply race conditions cause remediation tasks to fail silently with 403 Forbidden errors when the managed identity's role assignments have not yet propagated through Entra ID (~30-120s).

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PolicyRemediation"
}

inputs = {
  remediations = { ... }
}
```

## Scope dispatch

Each remediation entry MUST specify EXACTLY ONE of:
- `management_group_id` — MG-scoped remediation. **Constraint: `resource_discovery_mode` is not supported at MG scope by the Azure API (the provider omits this argument entirely for `azurerm_management_group_policy_remediation`). Only `ExistingNonCompliant` behaviour applies. The `ReEvaluateCompliance` value is blocked by validator.**
- `subscription_id` — Subscription-scoped remediation.
- `resource_group_id` — RG-scoped remediation.
- `resource_id` — Single-resource remediation (full ARM ID).

The module validates this via `length(compact([...])) == 1` and dispatches to the appropriate `azurerm_*_policy_remediation` resource.

## `location_filters` semantics (gotcha)

`location_filters` is a **POSITIVE allowlist** — only resources IN the listed locations are remediated. It is NOT an exclude filter. Passing `["germanywestcentral"]` remediates ONLY resources in that region. Empty list (default) means all locations.

## `resource_discovery_mode`

- `"ExistingNonCompliant"` (default) — remediate only resources currently marked non-compliant by the latest evaluation.
- `"ReEvaluateCompliance"` — re-evaluate compliance immediately, then remediate. **Not valid at MG scope (blocked by validator and absent from provider schema).**

## Initiative member targeting

When the parent policy assignment refers to an **initiative** (PolicySetDefinition) and you want to remediate a specific member definition, set `policy_definition_reference_id` to the `policyDefinitionReferenceId` of the member (NOT the policyDefinitionId).

**One remediation task per member**: to remediate multiple members of the same initiative, create multiple entries in `var.remediations`, each with a different `policy_definition_reference_id`.

The reference IDs must be looked up from the initiative definition (Azure portal or `az policy set-definition show`). They are NOT exposed in PolicyAssignment v0.2.12 outputs — this is a known gap tracked in the backlog.

## Tuning knobs

| Variable | Default | Range | Use case |
|---|---|---|---|
| `resource_count` | 500 | 1-50000 | Max resources to remediate per task |
| `parallel_deployments` | 10 | 1-30 | Concurrent deployments (higher = faster, more load) |
| `failure_percentage` | 0.1 | 0-1 | Halt task if this fraction of remediations fails |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Required |
|---|---|---|
| `remediations` | Map of remediation tasks (see Usage). | Yes |

## Outputs

| Name | Description |
|---|---|
| `remediation_ids` | Map of remediation task name => Azure resource ID (across all 4 scopes). |
| `remediation_names` | Map of remediation task name => Azure-side resource name. |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_management_group_policy_remediation.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_remediation) | resource |
| [azurerm_resource_group_policy_remediation.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_remediation) | resource |
| [azurerm_resource_policy_remediation.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_policy_remediation) | resource |
| [azurerm_subscription_policy_remediation.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_remediation) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| remediations | Map of policy remediation tasks. Key = remediation task name (used as Azure-side resource name; semantic logical key, not convention-named).<br><br>Exactly ONE of these scope IDs must be set per entry:<br>  - management\_group\_id : full MG resource ID<br>  - subscription\_id     : full subscription path (/subscriptions/<guid>)<br>  - resource\_group\_id   : full RG resource ID<br>  - resource\_id         : full ARM resource ID (for resource-level remediation)<br><br>Other fields:<br>  - policy\_assignment\_id             : (Required) Full ARM resource ID of the policy assignment to remediate. Typically `module.policy_assignments.assignment_ids[<key>]` when composing.<br>  - policy\_definition\_reference\_id   : (Optional) For initiatives — the policyDefinitionReferenceId of the member definition to remediate (one task per member). Look up from the initiative definition; not in PolicyAssignment outputs.<br>  - resource\_discovery\_mode          : (Optional, default "ExistingNonCompliant") Either "ExistingNonCompliant" (only existing non-compliant resources) or "ReEvaluateCompliance" (re-evaluate compliance before remediating). NOTE: "ReEvaluateCompliance" is NOT valid for management-group-scoped remediations (Azure API restriction — MG scope does not support resource\_discovery\_mode at all).<br>  - location\_filters                 : (Optional, default []) POSITIVE allowlist — restrict remediation to resources IN these locations only. NOT an exclude filter. Empty list means all locations.<br>  - resource\_count                   : (Optional, default 500) Max resources to remediate per task. Range 1-50000.<br>  - parallel\_deployments             : (Optional, default 10) Concurrent deployments. Range 1-30.<br>  - failure\_percentage               : (Optional, default 0.1) Failure threshold (0-1 = 0%-100%). Task halts if exceeded.<br><br>RBAC propagation: Remediation tasks require the policy assignment's managed identity to have its role assignments propagated through Entra ID (~30-120s). When composing with `../PolicyAssignment`, use `depends_on = [module.pa]` to ensure the PolicyAssignment time\_sleep completes first. Without it, first-apply race conditions cause silent task failures.<br><br>Schema note: `resource_discovery_mode` is NOT a valid argument for management-group-scoped remediations (azurerm provider schema omits it from azurerm\_management\_group\_policy\_remediation). This module ignores that field for MG-scope entries; only "ExistingNonCompliant" behaviour applies at MG scope per Azure API. | <pre>map(object({<br>    # Scope — EXACTLY ONE of these must be set per entry<br>    management_group_id = optional(string)<br>    subscription_id     = optional(string)<br>    resource_group_id   = optional(string)<br>    resource_id         = optional(string) # for azurerm_resource_policy_remediation<br><br>    # Required<br>    policy_assignment_id = string<br><br>    # Optional — initiative member targeting<br>    policy_definition_reference_id = optional(string)<br><br>    # Optional — behavior tuning (defaults per Azure API)<br>    resource_discovery_mode = optional(string, "ExistingNonCompliant")<br>    location_filters        = optional(list(string), [])<br>    resource_count          = optional(number, 500)<br>    parallel_deployments    = optional(number, 10)<br>    failure_percentage      = optional(number, 0.1)<br>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| remediation\_ids | Map of remediation task name => resource ID (across all 4 scopes — MG, Subscription, RG, Resource). |
| remediation\_names | Map of remediation task name => Azure-side resource name (passthrough of map keys for parity with sibling outputs). |
<!-- END_TF_DOCS -->
