# PolicyExemption

Map-shape module dispatching Azure Policy exemptions to one of three scopes (Management Group, Subscription, Resource Group) per entry. Canonical reference implementation for the 3-scope dispatch pattern (PolicyAssignment v0.2.10 mirrored from this).

## Usage

### Standalone

```hcl
module "policy_exemptions" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/PolicyExemption?ref=v0.2.11"

  exemptions = {
    "waiver-sandbox-rg-from-deny-public-ip" = {
      policy_assignment_id = "/subscriptions/<guid>/providers/Microsoft.Authorization/policyAssignments/<assignment-name>"
      resource_group_id    = "/subscriptions/<guid>/resourceGroups/<rg-name>"
      exemption_category   = "Waiver"
      display_name         = "Sandbox RG waiver for deny-public-ip"
      description          = "Sandbox RG temporarily exempt while migration completes"
      expires_on           = "2027-12-31T23:59:00Z"
      metadata = {
        ticket = "INC-12345"
        owner  = "platform@example.com"
      }
    }

    "mitigated-corporate-sub-from-tag-policy" = {
      policy_assignment_id = "/providers/Microsoft.Management/managementGroups/<mg-id>/providers/Microsoft.Authorization/policyAssignments/<assignment-name>"
      subscription_id      = "/subscriptions/<guid>"
      exemption_category   = "Mitigated"
      display_name         = "Corp sub exemption — mitigated via SCM"
      description          = "Tag compliance managed via separate SCM pipeline"
    }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PolicyExemption"
}

inputs = {
  exemptions = {
    # same shape as above
  }
}
```

## Scope dispatch

Each exemption entry MUST specify EXACTLY ONE of:
- `management_group_id` — exemption from an MG-scoped assignment
- `subscription_id` — exemption from a Subscription-scoped assignment
- `resource_group_id` — exemption from an RG-scoped assignment

The module validates this via `length(compact([...])) == 1` and dispatches to the appropriate `azurerm_*_policy_exemption` resource. This is the canonical reference for the 3-scope dispatch pattern across the repo (PolicyAssignment v0.2.10 mirrored from this).

## Exemption category

`exemption_category` defaults to `"Waiver"`. Allowed values:
- **`Waiver`** — temporary tolerance of non-compliance (e.g. legacy resource pending refactor). Most common.
- **`Mitigated`** — non-compliance is acceptable because mitigated by another control (e.g. compensating SCM pipeline, alternate detection mechanism).

## Targeted exemption for initiatives

When the policy assignment refers to an initiative (PolicySetDefinition) and you want to exempt only specific referenced definitions, set:

```hcl
policy_definition_reference_ids = ["definition-ref-id-1", "definition-ref-id-2"]
```

Without this list, the exemption applies to ALL definitions referenced by the assignment.

## Expiry

`expires_on` is OPTIONAL. When set, must be a UTC ISO 8601 datetime string:
`yyyy-MM-ddTHH:mm:ss[.fffffff]Z` (mandatory `Z` suffix, optional fractional seconds).

Example: `"2027-12-31T23:59:00Z"`.

The module validates the format at plan time.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

`var.exemptions` — `map(object({...}))`, required. Key = exemption name (max 64 chars, must be unique within scope).

### Exemption Object Fields

| Field | Type | Default | Required | Description |
|-------|------|---------|----------|-------------|
| `resource_group_id` | `string` | null | One scope required | Full Azure RG resource ID: `/subscriptions/<sub-guid>/resourceGroups/<rg-name>` |
| `subscription_id` | `string` | null | One scope required | Full subscription path: `/subscriptions/<sub-guid>` |
| `management_group_id` | `string` | null | One scope required | Full MG resource ID: `/providers/Microsoft.Management/managementGroups/<id>` |
| `policy_assignment_id` | `string` | — | Yes | Full resource ID of the policy assignment to exempt from. |
| `exemption_category` | `string` | `"Waiver"` | No | `"Waiver"` (accept risk) or `"Mitigated"` (compensating control). |
| `display_name` | `string` | — | Yes | Human-readable name shown in the portal. |
| `description` | `string` | null | No | Justification — recommended for audit trail. |
| `expires_on` | `string` | null | No | UTC ISO 8601 datetime string. Without it, exemption is permanent. Module validates format at plan time. |
| `policy_definition_reference_ids` | `list(string)` | null | No | For initiative-scoped assignments, list of specific child policies to exempt. Empty/null = exempt all child policies. |
| `metadata` | `map(string)` | null | No | Free-form key/value tags (owner, ticket ID, etc.). Module JSON-encodes before passing to the API. |

## Outputs

| Name | Description |
|------|-------------|
| `ids` | Map of exemption name => resource ID (merged across all scopes). |
| `names` | Map of exemption name => resource name (merged across all scopes). |
