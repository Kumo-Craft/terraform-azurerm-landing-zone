# StorageAccountStack

Composes a **Storage Account** + one or more **Private Endpoints** by wiring the canonical sibling modules [`../StorageAccount`](../StorageAccount) and [`../PrivateEndpoint`](../PrivateEndpoint) — the same composition pattern as [`KeyVaultStack`](../KeyVaultStack).

The Resource Group is **caller-provided** (`resource_group_name`); this Stack does not create its own RG — typically wired from a `../ResourceGroup` module instance in the consumer's Terragrunt config.

## What it deploys

| Resource | Via |
|---|---|
| Storage Account (secure-by-default: TLS 1.2, public access off, infra encryption, no shared keys) | `../StorageAccount` |
| Containers / file shares / CMK / Azure Files auth / firewall / RBAC / lock | `../StorageAccount` (forwarded inputs) |
| One Private Endpoint **per Storage sub-resource** (`blob`, `file`, `queue`, `table`, `web`, `dfs`, + `*_secondary`) | `../PrivateEndpoint` |

> Azure requires **a separate Private Endpoint per sub-resource**, each resolving via its own private DNS zone (`privatelink.blob.core.windows.net`, `privatelink.file.core.windows.net`, …). The `private_endpoints` map is therefore keyed by sub-resource. If you create a `dfs` (Data Lake) PE, also create a `blob` PE — some operations redirect between them.

## Usage

### Standalone — blob + file Private Endpoints

```hcl
module "storage_stack" {
  source = "../StorageAccountStack"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "data"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-data"

  subnet_id = "/subscriptions/.../virtualNetworks/vnet-1/subnets/snet-pe"

  account_tier             = "Standard"
  account_replication_type = "ZRS"

  containers = {
    tfstate = { name = "tfstate" }
  }

  private_endpoints = {
    blob = {
      private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.blob.core.windows.net"]
    }
    file = {
      private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.file.core.windows.net"]
    }
  }

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Single blob endpoint (default)

`private_endpoints` defaults to `{ blob = {} }` — a single blob Private Endpoint with DNS wired out-of-band (e.g. by an ALZ DINE policy). Set `private_endpoints = {}` to create **no** Private Endpoint.

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/StorageAccountStack"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "data"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
  subnet_id            = dependency.net.outputs.pe_subnet_id

  private_endpoints = {
    blob = { private_dns_zone_ids = [dependency.dns.outputs.blob_zone_id] }
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
| subscription_acronym | Subscription acronym (e.g. api, mgm) | `string` | -- | Yes |
| environment | Environment (e.g. prod, nprd) | `string` | -- | Yes |
| region_code | Region code (e.g. gwc, weu) | `string` | -- | Yes |
| workload | Workload suffix (lowercase alphanumeric, no hyphens) | `string` | -- | Yes |
| name | Explicit Storage Account name override (3-24 lowercase alphanumeric) | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name (caller-provided) | `string` | -- | Yes |
| subnet_id | Subnet ID for the Private Endpoint(s) | `string` | -- | Yes |
| private_endpoints | Map keyed by Storage sub-resource (`blob`/`file`/`queue`/`table`/`web`/`dfs` + `*_secondary`); per-entry `private_dns_zone_ids` / `private_ip_address` / `custom_network_interface_name` | `map(object({...}))` | `{ blob = {} }` | No |
| account_tier | Standard or Premium | `string` | `"Standard"` | No |
| account_replication_type | LRS/GRS/RAGRS/ZRS/GZRS/RAGZRS | `string` | `"ZRS"` | No |
| account_kind | StorageV2/BlobStorage/BlockBlobStorage/FileStorage | `string` | `"StorageV2"` | No |
| public_network_access_enabled | Allow public network access | `bool` | `false` | No |
| shared_access_key_enabled | Allow account keys / connection strings | `bool` | `false` | No |
| default_to_oauth_authentication | Default portal/CLI to AAD OAuth | `bool` | `true` | No |
| cross_tenant_replication_enabled | Allow cross-tenant object replication | `bool` | `false` | No |
| infrastructure_encryption_enabled | Double (infra-level) encryption — immutable | `bool` | `true` | No |
| local_user_enabled | Enable local users (SFTP/NFS) | `bool` | `false` | No |
| customer_managed_key | CMK (`key_vault_key_id` + `user_assigned_identity_id`) | `object` | `null` | No |
| identity_type | SystemAssigned / UserAssigned / both | `string` | `null` | No |
| identity_ids | UAMI resource IDs | `set(string)` | `[]` | No |
| blob_delete_retention_days | Deleted-blob retention (1-365) | `number` | `30` | No |
| container_delete_retention_days | Deleted-container retention (1-365) | `number` | `30` | No |
| blob_versioning_enabled | Enable blob versioning | `bool` | `false` | No |
| blob_change_feed_enabled | Enable blob change feed | `bool` | `false` | No |
| blob_last_access_time_enabled | Track blob last-access time | `bool` | `false` | No |
| containers | Map of containers to create | `map(object({...}))` | `{}` | No |
| file_shares | Map of file shares to create | `map(object({...}))` | `{}` | No |
| azure_files_authentication | Identity-based auth for Azure Files | `object` | `null` | No |
| network_rules | Storage firewall rules | `object` | `null` | No |
| sas_policy | SAS expiration policy | `object` | `null` | No |
| role_assignments | Map of role assignments on the Storage Account | `map(object({...}))` | `{}` | No |
| lock | Management lock (CanNotDelete/ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| tags | Tags applied to all resources | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Storage Account ID |
| name | Storage Account name |
| primary_blob_endpoint | Primary blob endpoint URL |
| primary_file_endpoint | Primary Azure Files endpoint URL |
| primary_access_key | Primary access key (sensitive; empty when shared keys disabled) |
| containers | Map of container key => { id, name } |
| file_shares | Map of file share key => { id, name, url } |
| private_endpoint_ids | Map of sub-resource => Private Endpoint resource ID |
| private_endpoint_ip_addresses | Map of sub-resource => Private Endpoint private IP |

## Notes

- **Connect via the public hostname.** Clients should use `<account>.blob.core.windows.net` (not the `privatelink` subdomain) — DNS resolves it to the private IP inside the VNet.
- **Coherent with KeyVaultStack.** Same shape: caller-provided RG, single `{acr}-{env}-{region}` prefix, leaf inputs forwarded, PE composed via `../PrivateEndpoint`. The one difference is `private_endpoints` is a map keyed by sub-resource (Storage exposes several; Key Vault has only `vault`).
