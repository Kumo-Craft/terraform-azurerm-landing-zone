# RbacAssignments

Assigns Azure RBAC roles to Entra ID groups (resolved by display name) and to managed identities or service principals (by object ID). Supports both role definition IDs and names via unified `role_definition_id_or_name`.

## Usage

### Standalone

```hcl
module "rbac_assignments" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/RbacAssignments?ref=v0.2.75"

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
