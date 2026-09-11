# PolicyDefinition

Map-shape module managing custom Azure Policy Definitions. Supports both subscription-scoped and Management Group-scoped definitions in a single deployment. Designed as the upstream anchor of the full Policy* lifecycle.

## Composition flow

```
PolicyDefinition → PolicySetDefinition → PolicyAssignment → PolicyRemediation
```

Use `definition_ids` output as input to `PolicySetDefinition.set_definitions[].policy_definition_references[].policy_definition_id`, or directly to `PolicyAssignment.assignments[].policy_definition_id` for single-definition assignments.

## Usage

### Standalone

```hcl
module "defs" {
  source = "./modules/PolicyDefinition"

  definitions = {
    "deny-public-storage" = {
      display_name = "Deny public storage accounts"
      description  = "Prevents creation of storage accounts with public network access enabled."
      metadata     = { category = "Storage" }
      policy_rule = {
        if = {
          allOf = [
            { field = "type", equals = "Microsoft.Storage/storageAccounts" },
            { field = "Microsoft.Storage/storageAccounts/publicNetworkAccess", equals = "Enabled" }
          ]
        }
        then = { effect = "deny" }
      }
    }

    "audit-untagged-resources" = {
      display_name        = "Audit untagged resources"
      management_group_id = "/providers/Microsoft.Management/managementGroups/platform"
      policy_rule = {
        if   = { field = "tags", exists = "false" }
        then = { effect = "audit" }
      }
    }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "git::https://github.com/John6810/landing-zone//modules/PolicyDefinition?ref=v0.2.14"
}

inputs = {
  definitions = {
    "deny-public-storage" = {
      display_name = "Deny public storage accounts"
      policy_rule  = { ... }
    }
  }
}
```

## policy_rule / parameters encoding

Pass `policy_rule` and `parameters` as native Terraform objects (maps/objects). The module calls `jsonencode()` before passing to the provider — exactly the same pattern as `PolicyAssignment.assignments[].parameters`.

Example `parameters` object:

```hcl
parameters = {
  tagName = {
    type     = "String"
    metadata = { displayName = "Tag Name", description = "Name of the tag to audit" }
    defaultValue = "Environment"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `definitions` | Map of custom policy definitions. Key = Azure-side resource name (max 64 chars). | `map(object(...))` | — | yes |
| `definitions[*].display_name` | Human-readable name visible in the portal (max 128 chars). | `string` | — | yes |
| `definitions[*].policy_rule` | Policy rule as Terraform object — module jsonencodes. | `any` | — | yes |
| `definitions[*].management_group_id` | When set, definition is MG-scoped. Omit for subscription scope. | `string` | `null` | no |
| `definitions[*].description` | Description visible in the portal. | `string` | `null` | no |
| `definitions[*].mode` | Evaluation mode. One of: All, Indexed, Microsoft.Kubernetes.Data, Microsoft.KeyVault.Data, Microsoft.Network.Data. | `string` | `"All"` | no |
| `definitions[*].metadata` | Free-form key-value metadata — module jsonencodes. | `map(string)` | `null` | no |
| `definitions[*].parameters` | Parameter definitions as Terraform object — module jsonencodes. | `any` | `null` | no |
| `definitions[*].policy_type` | One of: Custom, BuiltIn, NotSpecified, Static. | `string` | `"Custom"` | no |

## Outputs

| Name | Description |
|------|-------------|
| `definition_ids` | Map of definition name => Azure resource ID. Pass to `PolicySetDefinition` or `PolicyAssignment`. |
| `definition_names` | Map of definition name => Azure-side resource name (map key passthrough). |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
