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
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/RoleAssignment?ref=main"

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
