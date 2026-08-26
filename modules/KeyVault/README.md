# KeyVault

Deploys an Azure Key Vault with RBAC authorization, network ACLs, soft delete, purge protection, optional management lock, and role assignments. Does not include a Private Endpoint -- use the separate `PrivateEndpoint` module for that.

## Prerequisites

**RBAC on the deployer identity.** Because this module enables RBAC authorization (`rbac_authorization_enabled = true`), the identity running `terraform apply` needs Key Vault data-plane permissions on the KV in order to:

- create child resources (`azurerm_key_vault_key`, `azurerm_key_vault_secret`, `azurerm_key_vault_certificate`) in the same plan,
- and refresh their state on subsequent plans (Terraform reads the data plane during refresh).

**Recommended setup** — grant the Terraform service principal `Key Vault Administrator` (or more granular: `Key Vault Crypto Officer` + `Key Vault Secrets Officer`) **inherited from a Management Group or Subscription scope**, ONCE, so it propagates to every Key Vault deployed under that hierarchy. Example:

```bash
az role assignment create \
  --assignee <SPN-Terraform-objectId> \
  --role "Key Vault Administrator" \
  --scope "/providers/Microsoft.Management/managementGroups/LandingZones"
```

This is the Azure-native pattern documented under [Key Vault RBAC guide](https://learn.microsoft.com/azure/key-vault/general/rbac-guide). It avoids per-KV role assignments cluttering the Terraform state.

**Fallback** — if MG/Sub-level RBAC is forbidden by your least-privilege policy, set `assign_rbac_to_current_user = true` on this module. Each deployed KV will then automatically grant the deployer `Key Vault Administrator` as a state-tracked role assignment. Trade-off: that role assignment is permanent and audit-visible per KV.

## Usage

### Standalone

```hcl
module "key_vault" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/KeyVault?ref=KeyVault/v1.0.0"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "apim"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-kv"

  sku_name                      = "premium"
  enable_rbac                   = true
  public_network_access_enabled = false
  purge_protection_enabled      = true

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  role_assignments = {
    aks_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = "00000000-0000-0000-0000-000000000000"
    }
  }

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/KeyVault"
}

inputs = {
  subscription_acronym          = include.sub.locals.subscription_acronym
  environment                   = include.root.inputs.environment
  region_code                   = include.root.inputs.region_code
  workload                      = "apim"
  location                      = include.root.inputs.location
  resource_group_name           = dependency.rg.outputs.name
  public_network_access_enabled = false

  role_assignments = {
    kubelet_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = dependency.id_kubelet.outputs.principal_id
    }
  }

  tags = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Explicit Key Vault name (3-24 chars). If null, computed. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, api) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name. Keep short (max 24 chars total name). | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| tenant_id | Azure AD tenant ID (auto-detected if null) | `string` | `null` | No |
| sku_name | SKU: standard or premium (HSM-backed) | `string` | `"premium"` | No |
| enable_rbac | Enable RBAC authorization (recommended) | `bool` | `true` | No |
| assign_rbac_to_current_user | Assign Key Vault Administrator to current deployer | `bool` | `true` | No |
| role_assignments | Map of role assignments on the Key Vault. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| lock | Management lock configuration (CanNotDelete or ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| enabled_for_disk_encryption | Enable Azure Disk Encryption | `bool` | `false` | No |
| enabled_for_deployment | Enable VMs to retrieve certificates | `bool` | `false` | No |
| enabled_for_template_deployment | Enable ARM templates to retrieve secrets | `bool` | `false` | No |
| soft_delete_retention_days | Soft delete retention (7-90 days) | `number` | `90` | No |
| purge_protection_enabled | Enable purge protection (IRREVERSIBLE) | `bool` | `true` | No |
| public_network_access_enabled | Enable public network access | `bool` | `false` | No |
| network_acls | Network ACLs configuration | `object({...})` | `null` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The Key Vault resource ID |
| name | The Key Vault name |
| vault_uri | The Key Vault URI (e.g. `https://<name>.vault.azure.net/`). Preferred — mirrors `azurerm_key_vault.vault_uri` |
| uri | **DEPRECATED** — alias for `vault_uri`. Will be removed in a future major version |
| tenant_id | The Key Vault tenant ID |
| resource | Curated Key Vault attributes (`id`, `name`, `vault_uri`, `tenant_id`, `location`, `resource_group_name`). Explicit list — omits the provider-deprecated `contact` block a raw resource-object output would surface. |

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
| deployer\_rbac | ../RoleAssignment | n/a |
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| role\_assignments | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region where the Key Vault will be deployed | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| assign\_rbac\_to\_current\_user | Automatically assign `Key Vault Administrator` to the current deployer (the identity<br>running `terraform apply`).<br><br>**Default: false.** The recommended Azure-native pattern for a Landing Zone is to grant<br>the Terraform service principal `Key Vault Administrator` inherited from the Management<br>Group (or Subscription) scope ONCE, so it applies to every Key Vault deployed under that<br>hierarchy without per-KV state pollution. See README "Prerequisites" section.<br><br>Set to `true` only when:<br>- The deployer cannot be granted inherited MG/Sub-level RBAC (least-privilege policy), AND<br>- You need the deployer to manage child resources (keys, secrets, certs) in the same plan.<br><br>Trade-off when `true`: every KV deployed by this module records an explicit role<br>assignment for the deployer identity in state — auditability cost, and that identity<br>remains admin on the KV permanently unless explicitly revoked. | `bool` | `false` | no |
| enable\_rbac | Enable RBAC authorization (recommended over access policies) | `bool` | `true` | no |
| enabled\_for\_deployment | Enable VMs to retrieve certificates stored as secrets | `bool` | `false` | no |
| enabled\_for\_disk\_encryption | Enable Azure Disk Encryption to retrieve secrets and unwrap keys | `bool` | `false` | no |
| enabled\_for\_template\_deployment | Enable ARM templates to retrieve secrets | `bool` | `false` | no |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| lock | Controls the Resource Lock configuration for this resource.<br><br>- `kind` - (Required) The type of lock. Possible values are "CanNotDelete" and "ReadOnly".<br>- `name` - (Optional) The name of the lock. If not specified, generated from the kind value. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit Key Vault name (3-24 chars). If null, computed from naming components. | `string` | `null` | no |
| network\_acls | Network ACLs configuration for Key Vault firewall | <pre>object({<br>    default_action = string<br>    bypass         = string<br>    ip_rules       = optional(list(string), [])<br>    subnet_ids     = optional(list(string), [])<br>  })</pre> | `null` | no |
| public\_network\_access\_enabled | Enable public network access (disable in production) | `bool` | `false` | no |
| purge\_protection\_enabled | Enable purge protection (IRREVERSIBLE once enabled) | `bool` | `true` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | A map of role assignments to create on this Key Vault. The map key is deliberately<br>arbitrary to avoid issues where map keys may be unknown at plan time.<br><br>- `role_definition_id_or_name`             - (Required) The ID or name of the role definition.<br>- `principal_id`                           - (Required) The ID of the principal to assign the role to.<br>- `principal_type`                         - (Optional) The type of principal. Values: User, Group, ServicePrincipal.<br>- `condition`                              - (Optional) ABAC condition for the role assignment.<br>- `condition_version`                      - (Optional) Condition version ("1.0" or "2.0").<br>- `description`                            - (Optional) Description of the role assignment.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check for the service principal.<br>- `delegated_managed_identity_resource_id` - (Optional) Delegated managed identity for cross-tenant scenarios. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    principal_id                           = string<br>    principal_type                         = optional(string)<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    description                            = optional(string)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string)<br>  }))</pre> | `{}` | no |
| sku\_name | SKU name: 'standard' or 'premium' (HSM-backed) | `string` | `"premium"` | no |
| soft\_delete\_retention\_days | Number of days to retain soft-deleted Key Vault (7-90) | `number` | `90` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, con, api) | `string` | `null` | no |
| tags | Tags to apply to the Key Vault | `map(string)` | `{}` | no |
| tenant\_id | Azure AD tenant ID for the Key Vault (auto-detected if null) | `string` | `null` | no |
| workload | Workload name for naming convention. Keep short (max 24 chars total name). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The Key Vault resource ID |
| name | The Key Vault name |
| resource | Curated Key Vault attributes for downstream composition/inspection. Explicit field list (not the raw resource object) to avoid surfacing the provider-deprecated `contact` block — moved to the azurerm\_key\_vault\_certificate\_contacts resource. Same pattern as FlowLogs #10939. |
| tenant\_id | The Key Vault tenant ID |
| uri | DEPRECATED — use `vault_uri` instead. Kept for backwards compatibility with existing callers; will be removed in a future major version. |
| vault\_uri | The Key Vault URI (e.g., https://kv-name.vault.azure.net/). Mirrors azurerm\_key\_vault.vault\_uri — preferred over the legacy `uri` output. |
<!-- END_TF_DOCS -->
