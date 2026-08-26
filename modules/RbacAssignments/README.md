# RbacAssignments

Assigns Azure RBAC roles to Entra ID groups (resolved by display name) and to managed identities or service principals (by object ID). Supports both role definition IDs and names via unified `role_definition_id_or_name`.

## Usage

### Standalone

```hcl
module "rbac_assignments" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/RbacAssignments?ref=v0.2.75"

  group_assignments = {
    aks_cluster_admin = {
      group_name                 = "GRP_AZ_RBAC_RG_AksApi_Prod_AKSClusterAdmin"
      scope                      = "/subscriptions/.../resourceGroups/rg-api-prod-gwc-aks"
      role_definition_id_or_name = "Azure Kubernetes Service RBAC Cluster Admin"
    }
  }

  identity_assignments = {
    kubelet_acr_pull = {
      principal_id               = "00000000-0000-0000-0000-000000000000"
      scope                      = "/subscriptions/.../registries/crapiprodgwc001"
      role_definition_id_or_name = "AcrPull"
    }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/RbacAssignments"
}

inputs = {
  group_assignments = {
    aks_cluster_admin = {
      group_name                 = "GRP_AZ_RBAC_RG_AksApi_Prod_AKSClusterAdmin"
      scope                      = dependency.rg.outputs.id
      role_definition_id_or_name = "Azure Kubernetes Service RBAC Cluster Admin"
    }
  }

  identity_assignments = {
    kubelet_acr_pull = {
      principal_id               = dependency.aks_identity.outputs.principal_id
      scope                      = dependency.acr.outputs.id
      role_definition_id_or_name = "AcrPull"
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| azuread | ~> 3.8 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| group_assignments | Map of role assignments for Entra ID groups (resolved by display_name). Key is arbitrary. | `map(object({...}))` | `{}` | No |
| identity_assignments | Map of role assignments for managed identities or SPs. Key is arbitrary. | `map(object({...}))` | `{}` | No |

### Group Assignment Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| group_name | `string` | Yes | Entra ID group display name |
| scope | `string` | Yes | Azure resource ID |
| role_definition_id_or_name | `string` | Yes | Role definition ID or name |
| condition | `string` | No | ABAC condition |
| condition_version | `string` | No | Condition version ("1.0" or "2.0") |
| description | `string` | No | Assignment description |

### Identity Assignment Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| principal_id | `string` | Yes | Object ID of the MI/SP |
| scope | `string` | Yes | Azure resource ID |
| role_definition_id_or_name | `string` | Yes | Role definition ID or name |
| condition | `string` | No | ABAC condition |
| condition_version | `string` | No | Condition version ("1.0" or "2.0") |
| description | `string` | No | Assignment description |
| skip_service_principal_aad_check | `bool` | No | Skip AAD check (default: false) |
| delegated_managed_identity_resource_id | `string` | No | Resource ID of a delegated managed identity for cross-tenant role assignments |

## Outputs

| Name | Description |
|------|-------------|
| group_assignment_ids | Map of key => role assignment ID for groups |
| identity_assignment_ids | Map of key => role assignment ID for identities |
| group_resources | Map of key => complete role assignment object for groups |
| identity_resources | Map of key => complete role assignment object for identities |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azuread | ~> 3.8 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azuread | ~> 3.8 |
| azurerm | ~> 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_role_assignment.groups](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.identities](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azuread_group.this](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/data-sources/group) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| group\_assignments | A map of role assignments for Entra ID groups (resolved by display\_name).<br>The map key is deliberately arbitrary to avoid plan-time issues.<br><br>- `group_name`                 - (Required) Entra ID group display name.<br>- `scope`                      - (Required) Azure resource ID to assign the role on.<br>- `role_definition_id_or_name` - (Required) Role definition ID or name.<br>- `condition`                  - (Optional) ABAC condition.<br>- `condition_version`          - (Optional) Condition version ("1.0" or "2.0").<br>- `description`                - (Optional) Assignment description. | <pre>map(object({<br>    group_name                 = string<br>    scope                      = string<br>    role_definition_id_or_name = string<br>    condition                  = optional(string)<br>    condition_version          = optional(string)<br>    description                = optional(string)<br>  }))</pre> | `{}` | no |
| identity\_assignments | A map of role assignments for any Entra principal (MI, SP, Group, User) — addressed by object ID.<br>The map key is deliberately arbitrary to avoid plan-time issues.<br><br>- `principal_id`                     - (Required) Object ID of the principal.<br>- `scope`                            - (Required) Azure resource ID to assign the role on.<br>- `role_definition_id_or_name`       - (Required) Role definition ID or name.<br>- `principal_type`                   - (Optional) "User" \| "Group" \| "ServicePrincipal". Required when<br>                                       assigning to a group (Azure rejects with UnmatchedPrincipalType).<br>                                       Accepted values: User, Group, ServicePrincipal.<br>                                       ForeignGroup and Device appear in Azure REST API + portal docs but are NOT<br>                                       accepted by the azurerm provider as of v4.x — intentionally excluded from<br>                                       this enum. Re-verify when next pinning provider (4.76+).<br>- `condition`                        - (Optional) ABAC condition.<br>- `condition_version`                - (Optional) Condition version ("1.0" or "2.0").<br>- `description`                      - (Optional) Assignment description.<br>- `skip_service_principal_aad_check` - (Optional) Skip AAD check. Defaults to false.<br>- `delegated_managed_identity_resource_id` - (Optional) Resource ID of a delegated managed identity for cross-tenant role assignments. | <pre>map(object({<br>    principal_id                           = string<br>    scope                                  = string<br>    role_definition_id_or_name             = string<br>    principal_type                         = optional(string)<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    description                            = optional(string)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string)<br>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| group\_assignment\_ids | Map of key => role assignment ID for Entra ID groups |
| group\_resources | Map of key => complete role assignment object for groups |
| identity\_assignment\_ids | Map of key => role assignment ID for managed identities |
| identity\_resources | Map of key => complete role assignment object for identities |
| resources | Combined map of all role assignment resources (groups + identities merged by their map keys). Pattern: post-v0.2.74 canonical. |
<!-- END_TF_DOCS -->
