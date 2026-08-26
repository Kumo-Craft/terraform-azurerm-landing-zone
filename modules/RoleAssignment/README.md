# RoleAssignment

Thin wrapper around `azurerm_role_assignment` for single RBAC grants. The caller supplies a pre-known `principal_id` (UAMI, service principal, Entra group, or user), a role (by name or definition ID), and a scope — the module issues exactly one grant with no `azuread` dependency. Scopes may span management groups, subscriptions, resource groups, and individual resources, making it well-suited for cross-subscription grants in Terragrunt stacks. For bulk assignments tied to a single policy identity, prefer `PolicyAssignment`'s built-in `role_assignments` input instead.

## When to use this module vs `RbacAssignments`

| | `RoleAssignment` | `RbacAssignments` |
|---|---|---|
| Grants per call | 1 | N (map-driven) |
| Principal ID source | caller supplies it directly | caller supplies per-entry |
| ABAC conditions | yes (`condition` + `condition_version`) | yes (per-entry in the map shape) |
| Cross-sub / cross-MG | yes | yes |
| Best for | single targeted grant (e.g. AKS UAMI on DNS zone) | bulk assignments in one stack |

## Usage

### Standalone (Terraform)

Grant a managed identity `Storage Blob Data Reader` on a specific storage account:

```hcl
module "role_assignment" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/RoleAssignment?ref=main"

  scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-app-prod-gwc-data/providers/Microsoft.Storage/storageAccounts/stappprodgwcdata"
  principal_id         = "11111111-1111-1111-1111-111111111111"
  principal_type       = "ServicePrincipal"
  role_definition_name = "Storage Blob Data Reader"
  description          = "Allow the app UAMI to read blobs from the data storage account."
}
```

### Terragrunt (cross-subscription example)

Grant the AKS App Routing UAMI `DNS Zone Contributor` on a Private DNS zone that lives in a separate (hub) subscription:

```hcl
# stacks/spoke/aks-dns-grant/terragrunt.hcl
terraform {
  source = "${get_repo_root()}/modules/RoleAssignment"
}

dependency "aks_stack" {
  config_path = "../aks"
}

dependency "dns_zone" {
  config_path = "../../hub/private-dns"
}

inputs = {
  scope                = dependency.dns_zone.outputs.id
  principal_id         = dependency.aks_stack.outputs.web_app_routing_identity_principal_id
  principal_type       = "ServicePrincipal"
  role_definition_name = "Private DNS Zone Contributor"
  description          = "AKS App Routing UAMI — manage DNS records in hub zone."
}
```

## Notes

The role assignment's ARM resource name is auto-generated as a GUID by Azure on create. The module does not expose the `name` argument of the underlying `azurerm_role_assignment` resource — single grants don't need a deterministic name. Use the `id` / `name` outputs to reference the created assignment post-apply.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `scope` | `string` | Yes | — | Full Azure resource ID at which the role is granted (subscription, RG, resource, or management group). |
| `principal_id` | `string` | Yes | — | Object ID (GUID) of the principal receiving the role. |
| `principal_type` | `string` | No | `"ServicePrincipal"` | `User`, `Group`, or `ServicePrincipal`. Explicit value avoids AAD lookup races on first apply. |
| `role_definition_name` | `string` | No | `null` | Built-in or custom role display name. Mutually exclusive with `role_definition_id`. Exactly one must be set. |
| `role_definition_id` | `string` | No | `null` | Role definition GUID or full resource ID. Mutually exclusive with `role_definition_name`. Exactly one must be set. |
| `description` | `string` | No | `null` | Free-text description shown in the Azure portal. |
| `skip_service_principal_aad_check` | `bool` | No | `false` | Skip AAD existence check for the principal. Useful when the principal was just created. |
| `condition` | `string` | No | `null` | ABAC condition expression. Must be set together with `condition_version`. |
| `condition_version` | `string` | No | `null` | ABAC condition version. Allowed values: `"1.0"` or `"2.0"`. Must be set together with `condition`. |
| `delegated_managed_identity_resource_id` | `string` | No | `null` | Resource ID of the delegated managed identity for cross-tenant role assignments. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Resource ID of the role assignment. |
| `name` | Name (GUID) of the role assignment. |

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
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| principal\_id | Object ID of the principal receiving the role (UAMI principal\_id, SP object\_id, Entra group object\_id, user object\_id). | `string` | n/a | yes |
| scope | Full Azure resource ID at which the role is granted (subscription, RG, or specific resource). | `string` | n/a | yes |
| condition | Optional ABAC condition expression. Requires condition\_version to be set. | `string` | `null` | no |
| condition\_version | Version of the ABAC condition. Required when condition is set. Allowed: "1.0" or "2.0". | `string` | `null` | no |
| delegated\_managed\_identity\_resource\_id | Optional. Resource ID of the delegated managed identity for cross-tenant role assignments. | `string` | `null` | no |
| description | Free-text description of the role assignment (visible in the Azure portal). Useful to document why a grant exists. | `string` | `null` | no |
| principal\_type | Type of the principal: User, Group, or ServicePrincipal. Setting this explicitly avoids AAD lookup races on first apply. Pass null to let Azure auto-detect (legacy behavior, may race on first apply). | `string` | `"ServicePrincipal"` | no |
| role\_definition\_id | Role definition GUID or full resource ID. Use this when the role name is ambiguous OR when targeting a custom role. Mutually exclusive with role\_definition\_name and role\_definition\_id\_or\_name. | `string` | `null` | no |
| role\_definition\_id\_or\_name | Convenience: pass a role identifier in EITHER form — a built-in role display name<br>(e.g. "Contributor") OR a full role definition path<br>("/providers/Microsoft.Authorization/roleDefinitions/<guid>") — the module dispatches<br>to role\_definition\_id or role\_definition\_name automatically.<br><br>Used by wrapper modules (KeyVault, StorageAccount, etc.) that expose a unified<br>`role_definition_id_or_name` field per role-assignment map entry and forward it here<br>without re-implementing the dispatch logic. Mutually exclusive with role\_definition\_name<br>and role\_definition\_id. | `string` | `null` | no |
| role\_definition\_name | Built-in or custom role display name (e.g. "Private DNS Zone Contributor"). Mutually exclusive with role\_definition\_id and role\_definition\_id\_or\_name. | `string` | `null` | no |
| skip\_service\_principal\_aad\_check | Skip the AAD existence check for the principal. Useful when the principal was just created (race on first apply). | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | Resource ID of the role assignment. |
| name | Name (GUID) of the role assignment. |
| principal\_id | Principal object ID receiving the role. |
| principal\_type | Resolved principal type (User, Group, ServicePrincipal, …) of the assignment. |
| role\_definition\_id | Resolved role\_definition\_id passed to azurerm\_role\_assignment (null if the assignment uses role\_definition\_name). |
| role\_definition\_name | Resolved role\_definition\_name passed to azurerm\_role\_assignment (null if the assignment uses role\_definition\_id). |
| scope | Scope at which the role is granted. |
<!-- END_TF_DOCS -->
