# ManagedIdentity

Creates a User Assigned Managed Identity with optional Federated Identity Credentials (for AKS Workload Identity), RBAC role assignments, and management lock.

## Usage

### Standalone

```hcl
module "managed_identity" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/ManagedIdentity?ref=v0.2.38"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "aks-cp"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-identity"

  role_assignments = {
    network_contributor = {
      role_definition_id_or_name = "Network Contributor"
      scope                      = "/subscriptions/xxx/resourceGroups/rg-api-prod-gwc-network"
    }
  }

  federated_identity_credentials = {
    kv_access = {
      name    = "fic-kv-access"
      issuer  = "https://oidcissuer.example.com"
      subject = "system:serviceaccount:default:kv-sa"
    }
  }

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/ManagedIdentity"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "aks-cp"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name

  role_assignments = {
    network_contributor_nodes = {
      role_definition_id_or_name = "Network Contributor"
      scope                      = dependency.subnet.outputs.subnet_ids["snet-api-prod-gwc-nodes"]
    }
    kv_crypto_user = {
      role_definition_id_or_name = "Key Vault Crypto User"
      scope                      = dependency.kv.outputs.key_vault_id
    }
  }

  tags = include.root.inputs.common_tags
}
```

## Federated Identity Credential patterns

The `subject` field format depends on the issuing system. Common patterns are listed below. The `audience` field should always be `["api://AzureADTokenExchange"]` for standard Entra ID workload identity federation (already the default).

| System | Issuer | Subject pattern |
|--------|--------|-----------------|
| AKS workload identity | `azurerm_kubernetes_cluster.oidc_issuer_url` | `system:serviceaccount:{namespace}:{service-account-name}` |
| GitHub Actions OIDC | `https://token.actions.githubusercontent.com` | `repo:{owner}/{repo}:ref:refs/heads/{branch}` OR `repo:{owner}/{repo}:environment:{name}` OR `repo:{owner}/{repo}:pull_request` |
| Azure DevOps | `https://vstoken.dev.azure.com/{org-guid}` | Varies by pipeline configuration |
| GitLab CI/CD | `https://gitlab.com` (or self-hosted URL) | `project_path:{group}/{project}:ref_type:branch:ref:{branch}` |

Reference: https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Explicit identity name. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. api, mgm) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name (e.g. aks, kubelet, wi-kv) | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| federated_identity_credentials | Map of Federated Identity Credentials for Workload Identity. Key is arbitrary. | `map(object({ name = string, audience = optional(list(string)), issuer = string, subject = string }))` | `{}` | No |
| role_assignments | Map of role assignments for this identity. Key is arbitrary. | `map(object({ role_definition_id_or_name = string, scope = string, ... }))` | `{}` | No |
| lock | Management lock configuration (CanNotDelete or ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| tags | Tags | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Managed identity ID |
| name | Managed identity name |
| principal_id | Identity principal ID (object ID) |
| client_id | Identity client ID (application ID) |
| tenant_id | Tenant ID |
| resource | Complete identity resource object |
| lock_id | Management lock ID (null if var.lock is null) |
| federated_credential_ids | Map of federated credential logical key => resource ID |
| role_assignment_ids | Map of role assignment logical key => role assignment ID |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| role\_assignments | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_federated_identity_credential.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_user_assigned_identity.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| federated\_identity\_credentials | A map of federated identity credentials to create. The map key is deliberately<br>arbitrary to avoid issues where map keys may be unknown at plan time.<br><br>- `name`     - (Required) Name of the federated identity credential.<br>- `audience` - (Optional) Token audiences. Defaults to ["api://AzureADTokenExchange"].<br>- `issuer`   - (Required) The issuer URL (e.g. AKS OIDC issuer).<br>- `subject`  - (Required) The subject identifier (e.g. system:serviceaccount:ns:sa). | <pre>map(object({<br>    name     = string<br>    audience = optional(list(string), ["api://AzureADTokenExchange"])<br>    issuer   = string<br>    subject  = string<br>  }))</pre> | `{}` | no |
| lock | Controls the Resource Lock configuration for this resource.<br><br>- `kind` - (Required) The type of lock. Possible values are "CanNotDelete" and "ReadOnly".<br>- `name` - (Optional) The name of the lock. If not specified, generated from the kind value. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Explicit identity name. If null, computed from naming components. | `string` | `null` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | A map of role assignments to create on this identity. The map key is deliberately<br>arbitrary to avoid issues where map keys may be unknown at plan time.<br><br>- `role_definition_id_or_name`             - (Required) The ID or name of the role definition.<br>- `scope`                                  - (Required) The scope to assign the role to.<br>- `condition`                              - (Optional) ABAC condition for the role assignment.<br>- `condition_version`                      - (Optional) Condition version. Valid values: "2.0".<br>- `delegated_managed_identity_resource_id` - (Optional) Delegated managed identity for cross-tenant scenarios.<br>- `description`                            - (Optional) Description of the role assignment.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check for the service principal. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    scope                                  = string<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    delegated_managed_identity_resource_id = optional(string)<br>    description                            = optional(string)<br>    # Defaults to true so the first apply does not race against AAD propagation<br>    # of the freshly-created UAMI principal_id. Override to false once the<br>    # identity is stable (subsequent applies have no propagation delay).<br>    skip_service_principal_aad_check = optional(bool, true)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym (e.g. api, lfr, mgm) | `string` | `null` | no |
| tags | Tags | `map(string)` | `{}` | no |
| workload | Workload name (e.g. aks, kubelet, wi-kv) | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| client\_id | Identity client ID (application ID) |
| federated\_credential\_ids | Map of federated credential logical key => resource ID |
| id | Managed identity ID |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | Managed identity name |
| principal\_id | Identity principal ID (object ID) |
| resource | The complete User Assigned Identity resource object |
| role\_assignment\_ids | Map of role assignment logical key => role assignment ID |
| tenant\_id | Tenant ID |
<!-- END_TF_DOCS -->
