# StorageAccount

Creates an Azure Storage Account with configurable replication, network access, identity, blob/container retention, optional containers, management lock, and RBAC role assignments. Names follow `st{subscription_acronym}{environment}{region_code}{workload}` (lowercase alphanumeric only).

## Usage

### Standalone

```hcl
module "storage_account" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/StorageAccount?ref=v0.2.30"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "diag"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-storage"

  account_replication_type      = "ZRS"
  public_network_access_enabled = false

  role_assignments = {
    blob_contributor = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
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
  source = "${get_repo_root()}/modules/StorageAccount"
}

inputs = {
  subscription_acronym          = include.sub.locals.subscription_acronym
  environment                   = include.root.inputs.environment
  region_code                   = include.root.inputs.region_code
  workload                      = "diag"
  location                      = include.root.inputs.location
  resource_group_name           = dependency.rg.outputs.name
  public_network_access_enabled = false
  tags                          = include.root.inputs.common_tags
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
| name | Explicit name (3-24 lowercase alphanumeric). If null, computed. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, api) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload suffix. Lowercase alphanumeric only. | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| account_tier | Standard or Premium | `string` | `"Standard"` | No |
| account_replication_type | LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS | `string` | `"ZRS"` | No |
| account_kind | StorageV2, BlobStorage, BlockBlobStorage, FileStorage | `string` | `"StorageV2"` | No |
| public_network_access_enabled | Enable public network access | `bool` | `false` | No |
| shared_access_key_enabled | Enable shared access keys | `bool` | `false` | No |
| default_to_oauth_authentication | Default to AAD/OAuth auth in portal/CLI. CAF recommendation — nudges admins away from shared-key auth. | `bool` | `true` | No |
| cross_tenant_replication_enabled | Block cross-tenant object replication. Default false — keeps data inside the tenant. | `bool` | `false` | No |
| infrastructure_encryption_enabled | **BREAKING (v0.2.30)** — second platform-managed encryption layer (CAF defense-in-depth). Immutable post-creation. Pin `false` before upgrading if existing SA used the old default. | `bool` | `true` | No |
| local_user_enabled | Enable local users for SFTP/NFS. Default false (CAF) — set true when SFTP/NFS is explicitly required. | `bool` | `false` | No |
| customer_managed_key | CMK config: `{ key_vault_key_id, user_assigned_identity_id }`. Requires identity_type to include UserAssigned. | `object({...})` | `null` | No |
| identity_type | SystemAssigned, UserAssigned, or both | `string` | `null` | No |
| identity_ids | Set of UAMI resource IDs. CMK UAMI is auto-merged — no need to repeat it here. | `set(string)` | `[]` | No |
| blob_delete_retention_days | Retention days for deleted blobs (1-365) | `number` | `30` | No |
| container_delete_retention_days | Retention days for deleted containers (1-365) | `number` | `30` | No |
| blob_versioning_enabled | Enable blob versioning for soft-delete and ransomware protection. | `bool` | `false` | No |
| blob_change_feed_enabled | Enable blob change feed (audit log of all blob changes). | `bool` | `false` | No |
| blob_last_access_time_enabled | Track last access time on blobs for lifecycle management policies. | `bool` | `false` | No |
| containers | Map of containers to create. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| file_shares | Map of file shares. Each entry: `{ name, quota_gb, access_tier (optional) }`. | `map(object({...}))` | `{}` | No |
| azure_files_authentication | AD/AAD-DS/Entra Kerberos auth for SMB. `active_directory` sub-object required when `directory_type = "AD"`. | `object({...})` | `null` | No |
| network_rules | Network ACLs. `{ default_action, bypass, virtual_network_subnet_ids, ip_rules }`. | `object({...})` | `null` | No |
| sas_policy | SAS token expiration policy. `{ expiration_period (ISO 8601 d.HH:mm:ss), expiration_action ("Log"\|"Block") }`. | `object({...})` | `null` | No |
| role_assignments | Map of role assignments on the Storage Account. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| lock | Management lock (CanNotDelete or ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| tags | Tags | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Storage Account ID |
| name | Storage Account name |
| primary_blob_endpoint | Primary blob endpoint URL |
| primary_file_endpoint | Primary Azure Files endpoint URL |
| primary_access_key | Primary access key (`sensitive = true`) |
| file_shares | Map of file share key => `{ id, name, url }` |
| containers | Map of container key => `{ id, name }` |

## Breaking changes (v0.2.30)

### `infrastructure_encryption_enabled` default flipped to `true`

CAF defense-in-depth guidance recommends infrastructure encryption (a second platform-managed encryption layer) for sensitive workloads. v0.2.30 flips the default from `false` to `true` to align with CAF.

**Impact for callers**: If your existing deployment relied on the legacy default (`infrastructure_encryption_enabled = false`), upgrading will trigger Storage Account destroy+recreate on next apply — **`infrastructure_encryption_enabled` is immutable post-creation per Azure**.

**Migration recipe**:

1. **Before upgrading**: pin the legacy value explicitly in your caller config:
   ```hcl
   module "storage" {
     source                            = "..."
     infrastructure_encryption_enabled = false   # pin legacy default
     # other args...
   }
   ```
2. Upgrade to v0.2.30. The pin overrides the new default — no destroy/recreate.
3. **For NEW deployments**: omit the variable to get the secure default `true`.

### Other default flips (non-breaking)

- `default_to_oauth_authentication` default `false → true` (CAF — nudges portal/CLI to AAD auth; Terraform behavior unchanged).
- `local_user_enabled` default `true → false` (CAF — set `true` explicitly if SFTP/NFS is needed).

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
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_storage_share.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_share) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| account\_kind | Kind: StorageV2, BlobStorage, BlockBlobStorage, FileStorage | `string` | `"StorageV2"` | no |
| account\_replication\_type | Replication type: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS | `string` | `"ZRS"` | no |
| account\_tier | Tier: Standard or Premium | `string` | `"Standard"` | no |
| azure\_files\_authentication | Identity-based authentication for Azure Files shares.<br><br>- `directory_type`                 - (Required) "AADDS", "AD", or "AADKERB" (Entra Kerberos).<br>- `default_share_level_permission` - (Optional) Default RBAC at share level: None, StorageFileDataSmbShareReader,<br>                                     StorageFileDataSmbShareContributor, StorageFileDataSmbShareElevatedContributor.<br>- `active_directory`               - (Required when directory\_type = "AD") On-premises AD DS details.<br>  - `domain_guid`         - (Required) Domain GUID.<br>  - `domain_name`         - (Required) FQDN of the AD domain.<br>  - `domain_sid`          - (Optional) Domain SID.<br>  - `forest_name`         - (Optional) AD forest name.<br>  - `netbios_domain_name` - (Optional) NetBIOS domain name.<br>  - `storage_sid`         - (Optional) SID of the Storage Account in AD. | <pre>object({<br>    directory_type                 = string<br>    default_share_level_permission = optional(string)<br>    active_directory = optional(object({<br>      domain_guid         = string<br>      domain_name         = string<br>      domain_sid          = optional(string)<br>      forest_name         = optional(string)<br>      netbios_domain_name = optional(string)<br>      storage_sid         = optional(string)<br>    }))<br>  })</pre> | `null` | no |
| blob\_change\_feed\_enabled | Enable the blob change feed (audit log of all blob changes). Pre-requisite for some replication and governance scenarios. Default false. | `bool` | `false` | no |
| blob\_delete\_retention\_days | Retention days for deleted blobs | `number` | `30` | no |
| blob\_last\_access\_time\_enabled | Track last-access time on blobs. Required for lifecycle management policies that move/delete based on access patterns. Adds ingestion cost — opt-in. | `bool` | `false` | no |
| blob\_versioning\_enabled | Enable blob versioning. Required for tfstate backends (F-STOR-3) and for point-in-time restore. Default false (Azure default) — opt-in. | `bool` | `false` | no |
| container\_delete\_retention\_days | Retention days for deleted containers | `number` | `30` | no |
| containers | A map of containers to create in the Storage Account. The map key is arbitrary.<br><br>- `name`        - (Required) Container name.<br>- `access_type` - (Optional) Access type: private, blob, or container. Defaults to private. | <pre>map(object({<br>    name        = string<br>    access_type = optional(string, "private")<br>  }))</pre> | `{}` | no |
| cross\_tenant\_replication\_enabled | Allow object replication across Azure AD tenants. Default false (Azure v4 default) — keeps data inside the tenant. | `bool` | `false` | no |
| customer\_managed\_key | Customer-Managed Key (CMK) configuration backed by Azure Key Vault. When set,<br>the storage account encrypts all data with this CMK instead of the<br>Microsoft-managed key.<br><br>- `key_vault_key_id`           - (Required) Versioned or versionless key URL<br>                                  (e.g. https://kv-...vault.azure.net/keys/foo<br>                                  or .../keys/foo/<version>).<br>- `user_assigned_identity_id`  - (Required) UAMI that has Key Vault Crypto<br>                                  Service Encryption User on the KV.<br><br>Prerequisites:<br>- identity\_type must include "UserAssigned" and reference the same UAMI.<br>- The UAMI needs Key Vault Crypto Service Encryption User on the KV.<br>- The KV must have purge protection enabled. | <pre>object({<br>    key_vault_key_id          = string<br>    user_assigned_identity_id = string<br>  })</pre> | `null` | no |
| default\_to\_oauth\_authentication | When true, the portal/CLI default to AAD OAuth instead of access keys for data plane operations. CAF recommendation — nudges admins away from shared-key auth. Default true. | `bool` | `true` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| file\_shares | A map of file shares to create on the Storage Account (requires account\_kind = FileStorage for Premium).<br><br>- `name`        - (Required) File share name (3-63 chars, lowercase, numbers, hyphens).<br>- `quota_gb`    - (Required) Provisioned capacity in GiB (Premium min 100, max 102400).<br>- `access_tier` - (Optional) "Premium" for FileStorage, or Hot/Cool/TransactionOptimized for Standard. | <pre>map(object({<br>    name        = string<br>    quota_gb    = number<br>    access_tier = optional(string)<br>  }))</pre> | `{}` | no |
| identity\_ids | Set of UAMI resource IDs to attach when identity\_type contains 'UserAssigned'. The CMK UAMI (var.customer\_managed\_key.user\_assigned\_identity\_id) is auto-merged with these — no need to repeat it here. | `set(string)` | `[]` | no |
| identity\_type | Identity type: SystemAssigned, UserAssigned, or SystemAssigned,UserAssigned | `string` | `null` | no |
| infrastructure\_encryption\_enabled | Enable infrastructure-level AES-256 encryption (double encryption). Adds a second encryption layer below the service-level encryption. Cannot be changed after creation. **BREAKING (v0.2.30)**: default flipped from false to true (CAF defense-in-depth). Existing accounts with the old default will be destroyed and recreated on next apply — pin `infrastructure_encryption_enabled = false` before upgrading to preserve current behavior. | `bool` | `true` | no |
| local\_user\_enabled | Enable local users for SFTP/NFS. Default false (CAF) — set true when SFTP/NFS is explicitly required. | `bool` | `false` | no |
| lock | Controls the Resource Lock configuration.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Explicit name. If null, computed automatically. | `string` | `null` | no |
| network\_rules | Storage Account firewall rules.<br><br>**BREAKING (secure-by-default)**: the default is now a locked-down rule set<br>(`default_action = "Deny"`, `bypass = ["AzureServices"]`) instead of `null`.<br>This satisfies CKV\_AZURE\_35 (default network access = Deny) and CKV\_AZURE\_36<br>(Trusted Microsoft Services bypass enabled). With this default the account is<br>reachable only via Private Endpoint and trusted first-party Azure services —<br>public traffic from arbitrary IPs/subnets is denied. Consumers who need<br>public reachability must supply `ip_rules` / `virtual_network_subnet_ids`, or<br>set `network_rules = null` to remove the firewall block entirely (reverts to<br>the Azure "Allow all networks" default).<br><br>- `default_action`             - (Required) "Allow" or "Deny".<br>- `bypass`                     - (Optional) Services allowed to bypass: list of AzureServices, Logging, Metrics, None. Defaults to ["AzureServices"].<br>- `virtual_network_subnet_ids` - (Optional) Subnet IDs with service endpoint to Microsoft.Storage.<br>- `ip_rules`                   - (Optional) IPv4 CIDR ranges allowed. | <pre>object({<br>    default_action             = string<br>    bypass                     = optional(list(string), ["AzureServices"])<br>    virtual_network_subnet_ids = optional(list(string), [])<br>    ip_rules                   = optional(list(string), [])<br>  })</pre> | <pre>{<br>  "bypass": [<br>    "AzureServices"<br>  ],<br>  "default_action": "Deny"<br>}</pre> | no |
| public\_network\_access\_enabled | Enable public network access | `bool` | `false` | no |
| queue\_logging\_enabled | Enable Storage Analytics logging (read/write/delete) for the Queue service.<br>Secure-by-default true (CKV\_AZURE\_33). The setting is automatically ignored<br>for account kinds/tiers that do not offer a queue endpoint (Premium tier,<br>FileStorage, BlockBlobStorage, BlobStorage) — queue\_properties cannot be set<br>on those accounts, so no block is emitted regardless of this value. | `bool` | `true` | no |
| queue\_logging\_retention\_days | Retention period (days) for Queue service Analytics logs when queue\_logging\_enabled is true. Between 1 and 365. | `number` | `10` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | A map of role assignments to create on this Storage Account. The map key is arbitrary.<br><br>- `role_definition_id_or_name`             - (Required) The ID or name of the role definition.<br>- `principal_id`                           - (Required) The ID of the principal.<br>- `principal_type`                         - (Optional) User, Group, or ServicePrincipal.<br>- `condition`                              - (Optional) ABAC condition.<br>- `condition_version`                      - (Optional) Condition version ("2.0").<br>- `description`                            - (Optional) Description.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check.<br>- `delegated_managed_identity_resource_id` - (Optional) Cross-tenant. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    principal_id                           = string<br>    principal_type                         = optional(string)<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    description                            = optional(string)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string)<br>  }))</pre> | `{}` | no |
| sas\_policy | Optional SAS token expiration policy. CAF + Azure Security Benchmark recommend enforcing SAS expiry governance.<br><br>- expiration\_period: ISO 8601 duration format `d.HH:mm:ss` (e.g. "01.00:00:00" = 1 day, "07.00:00:00" = 1 week).<br>- expiration\_action: "Log" (warn but allow) or "Block" (reject SAS tokens exceeding the expiry policy).<br><br>Source: https://learn.microsoft.com/en-us/azure/storage/common/sas-expiration-policy | <pre>object({<br>    expiration_period = string<br>    expiration_action = optional(string, "Log")<br>  })</pre> | `null` | no |
| shared\_access\_key\_enabled | Enable shared access keys (account keys / connection strings). Disable to force AAD-only auth — required by some compliance baselines (MCSB, F-STOR-2). | `bool` | `false` | no |
| subscription\_acronym | Subscription acronym (e.g. api, mgm) | `string` | `null` | no |
| tags | Tags | `map(string)` | `{}` | no |
| workload | Workload suffix. Lowercase alphanumeric only (no hyphens). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| containers | Map of container key => { id, name } for callers needing container references downstream (e.g. PaloCluster bootstrap container, ALZ DINE remediation targets). |
| file\_shares | Map of file share key => { id, name, url } |
| id | Storage Account ID |
| name | Storage Account name |
| primary\_access\_key | Primary access key |
| primary\_blob\_endpoint | Primary blob endpoint URL |
| primary\_file\_endpoint | Primary Azure Files endpoint URL |
<!-- END_TF_DOCS -->
