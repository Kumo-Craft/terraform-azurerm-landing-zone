# PolicySetDefinition

Map-shape module managing Azure Policy Set Definitions (initiatives — bundles of policy definitions targeting a common compliance goal). Supports both subscription-scoped and Management Group-scoped set definitions in a single deployment.

Designed to compose downstream of `../PolicyDefinition` and upstream of `../PolicyAssignment`.

## Composition flow

```
PolicyDefinition → PolicySetDefinition → PolicyAssignment → PolicyRemediation
```

## Usage — full Policy* lifecycle composition

```hcl
module "defs" {
  source = "../PolicyDefinition"

  definitions = {
    "deny-public-storage" = {
      display_name = "Deny public storage accounts"
      policy_rule  = {
        if   = { field = "Microsoft.Storage/storageAccounts/publicNetworkAccess", equals = "Enabled" }
        then = { effect = "deny" }
      }
    }
    "audit-untagged-resources" = {
      display_name = "Audit untagged resources"
      policy_rule  = {
        if   = { field = "tags", exists = "false" }
        then = { effect = "audit" }
      }
    }
  }
}

module "sets" {
  source = "../PolicySetDefinition"

  set_definitions = {
    "platform-baseline" = {
      display_name = "Platform Baseline"
      policy_definition_references = [
        {
          policy_definition_id = module.defs.definition_ids["deny-public-storage"]
          reference_id         = "deny-public-storage"
        },
        {
          policy_definition_id = module.defs.definition_ids["audit-untagged-resources"]
          reference_id         = "audit-untagged-resources"
        }
      ]
    }
  }
}

module "assignments" {
  source = "../PolicyAssignment"

  assignments = {
    "platform-baseline-prod" = {
      policy_definition_id = module.sets.set_definition_ids["platform-baseline"]
      subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
      display_name         = "Platform Baseline — prod subscription"
    }
  }
}

module "remediation" {
  source     = "../PolicyRemediation"
  depends_on = [module.assignments]

  remediations = {
    "platform-baseline-prod" = {
      subscription_id      = "/subscriptions/00000000-0000-0000-0000-000000000000"
      policy_assignment_id = module.assignments.assignment_ids["platform-baseline-prod"]
    }
  }
}
```

### Standalone

```hcl
module "sets" {
  source = "./modules/PolicySetDefinition"

  set_definitions = {
    "platform-baseline" = {
      display_name = "Platform Baseline"
      description  = "Platform-wide baseline policies."
      metadata     = { category = "General" }
      policy_definition_references = [
        {
          policy_definition_id = "/subscriptions/<guid>/providers/Microsoft.Authorization/policyDefinitions/deny-public-storage"
          reference_id         = "deny-public-storage"
        }
      ]
    }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "git::https://github.com/John6810/landing-zone//modules/PolicySetDefinition?ref=v0.2.14"
}

inputs = {
  set_definitions = {
    "platform-baseline" = {
      display_name = "Platform Baseline"
      policy_definition_references = [...]
    }
  }
}
```

## Scope dispatch

| `management_group_id` | Resource used |
|----------------------|---------------|
| `null` (omitted) | `azurerm_policy_set_definition` |
| set | `azurerm_management_group_policy_set_definition` |

`azurerm_policy_set_definition.management_group_id` is deprecated in azurerm 4.x — this module dispatches MG-scoped entries to the dedicated resource.

## parameter_values / parameters encoding

Pass `parameter_values` (per-member overrides) and `parameters` (set-level definitions) as native Terraform objects. The module calls `jsonencode()` before passing to the provider.

## reference_id recommendation

Always set `reference_id` on each member of an initiative. `PolicyExemption` and `PolicyRemediation` use it to target a specific member definition for exemption or remediation. Without it, the provider auto-generates an opaque ID that may drift between applies.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `set_definitions` | Map of policy set definitions. Key = Azure-side resource name (max 64 chars). | `map(object(...))` | — | yes |
| `set_definitions[*].display_name` | Human-readable name visible in the portal (max 128 chars). | `string` | — | yes |
| `set_definitions[*].policy_definition_references` | List of member definitions (min 1). | `list(object(...))` | — | yes |
| `set_definitions[*].policy_definition_references[*].policy_definition_id` | Full ARM ID of the member definition. | `string` | — | yes |
| `set_definitions[*].policy_definition_references[*].reference_id` | Client-side reference ID (recommended, must be unique per set). | `string` | `null` | no |
| `set_definitions[*].policy_definition_references[*].parameter_values` | Per-member parameter overrides as Terraform object — module jsonencodes. | `any` | `null` | no |
| `set_definitions[*].policy_definition_references[*].policy_definition_group_names` | Groups this member belongs to. | `list(string)` | `null` | no |
| `set_definitions[*].policy_definition_groups` | Group definitions for organizing members in the portal. | `list(object(...))` | `[]` | no |
| `set_definitions[*].management_group_id` | When set, set definition is MG-scoped. Omit for subscription scope. | `string` | `null` | no |
| `set_definitions[*].description` | Description visible in the portal. | `string` | `null` | no |
| `set_definitions[*].metadata` | Free-form key-value metadata — module jsonencodes. | `map(string)` | `null` | no |
| `set_definitions[*].parameters` | Set-level parameter definitions as Terraform object — module jsonencodes. | `any` | `null` | no |
| `set_definitions[*].policy_type` | One of: Custom, BuiltIn, NotSpecified, Static. | `string` | `"Custom"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `set_definition_ids` | Map of set definition name => Azure resource ID. Pass to `PolicyAssignment.assignments[].policy_definition_id`. |
| `set_definition_names` | Map of set definition name => Azure-side resource name (map key passthrough). |
| `policy_definition_reference_ids` | Map of set definition name => map of member reference_id => reference object. For `PolicyExemption`/`PolicyRemediation` targeting. |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
