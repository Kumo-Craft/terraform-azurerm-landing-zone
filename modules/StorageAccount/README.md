# StorageAccount

Creates an Azure Storage Account with configurable replication, network access, identity, blob/container retention, optional containers, management lock, and RBAC role assignments. Names follow `st{subscription_acronym}{environment}{region_code}{workload}` (lowercase alphanumeric only).

## Usage

### Standalone

```hcl
module "storage_account" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/StorageAccount?ref=v0.2.30"

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
