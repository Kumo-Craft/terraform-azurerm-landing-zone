# RoleDefinition

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

| Name | Source | Version |
|------|--------|---------|
| assignment | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_role_definition.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_definition) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Display name of the custom role (must be unique within the tenant). | `string` | n/a | yes |
| scope | CREATION scope of the role (subscription or management group ID). Must<br>encompass every entry in `assignable_scopes`. It is automatically added to<br>`assignable_scopes` if that list is empty. Changing this forces recreation. | `string` | n/a | yes |
| actions | Allowed control-plane actions (e.g. "Microsoft.Network/virtualNetworks/peer/action"). Prefer explicit actions over wildcards. | `list(string)` | `[]` | no |
| assignable\_scopes | Scopes where the role may be assigned. Empty = `[scope]`. Use MG /<br>subscription / resource-group scopes, not resource instances. Azure allows<br>AT MOST ONE management group in this list, and forbids management-group<br>entries entirely when the role has data\_actions. | `list(string)` | `[]` | no |
| assignments | Optional role assignments created alongside the definition (handy for the<br>one-shot "define + assign to this SPN" case). Each is delegated to the<br>in-repo RoleAssignment module.<br><br>- `scope`          - (Required) narrow scope to assign at (resource / RG / sub).<br>- `principal_id`   - (Required) object ID of the principal.<br>- `principal_type` - (Optional) User \| Group \| ServicePrincipal (default). For<br>                     ServicePrincipal the AAD existence pre-check is skipped to<br>                     avoid a first-apply race on freshly-created SPNs. | <pre>list(object({<br>    scope          = string<br>    principal_id   = string<br>    principal_type = optional(string, "ServicePrincipal")<br>  }))</pre> | `[]` | no |
| data\_actions | Allowed data-plane actions. NOTE: a role with data\_actions cannot be assignable at a management-group scope (Azure restriction). | `list(string)` | `[]` | no |
| description | Description of the role (shown in the portal). | `string` | `""` | no |
| not\_actions | Control-plane actions subtracted from `actions` (only meaningful when `actions` uses a wildcard). Not a deny rule. | `list(string)` | `[]` | no |
| not\_data\_actions | Data-plane actions subtracted from `data_actions`. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| assignable\_scopes | Effective assignable scopes of the role. |
| assignment\_ids | Map of the created role-assignment resource IDs, keyed by "<principal\_id>\|<scope>". |
| name | Display name of the custom role. |
| role\_definition\_id | GUID (roleDefinitionId) of the custom role. |
| role\_definition\_resource\_id | Fully-qualified Azure Resource Manager ID of the role — pass this to azurerm\_role\_assignment.role\_definition\_id. |
<!-- END_TF_DOCS -->
