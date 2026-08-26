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
| time | >= 0.9.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| pe | ../PrivateEndpoint | n/a |
| storage | ../StorageAccount | n/a |

## Resources

| Name | Type |
|------|------|
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | n/a | yes |
| location | Azure region where the Storage Account and Private Endpoint(s) will be deployed. | `string` | n/a | yes |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group in which to create the Storage Account and Private Endpoint(s). Caller-provided — this Stack does not create its own RG (same convention as KeyVaultStack). | `string` | n/a | yes |
| subnet\_id | Subnet ID for the Storage Account Private Endpoint(s). | `string` | n/a | yes |
| subscription\_acronym | Subscription acronym for naming convention (e.g. api, mgm, con) | `string` | n/a | yes |
| workload | Workload suffix for naming convention. Lowercase alphanumeric only (no hyphens — Storage Account constraint). | `string` | n/a | yes |
| account\_kind | Kind: StorageV2, BlobStorage, BlockBlobStorage, FileStorage | `string` | `"StorageV2"` | no |
| account\_replication\_type | Replication type: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS | `string` | `"ZRS"` | no |
| account\_tier | Tier: Standard or Premium | `string` | `"Standard"` | no |
| azure\_files\_authentication | Identity-based authentication for Azure Files shares. See the ../StorageAccount module for the full shape. | <pre>object({<br>    directory_type                 = string<br>    default_share_level_permission = optional(string)<br>    active_directory = optional(object({<br>      domain_guid         = string<br>      domain_name         = string<br>      domain_sid          = optional(string)<br>      forest_name         = optional(string)<br>      netbios_domain_name = optional(string)<br>      storage_sid         = optional(string)<br>    }))<br>  })</pre> | `null` | no |
| blob\_change\_feed\_enabled | Enable the blob change feed. | `bool` | `false` | no |
| blob\_delete\_retention\_days | Retention days for deleted blobs | `number` | `30` | no |
| blob\_last\_access\_time\_enabled | Track last-access time on blobs. | `bool` | `false` | no |
| blob\_versioning\_enabled | Enable blob versioning. | `bool` | `false` | no |
| container\_delete\_retention\_days | Retention days for deleted containers | `number` | `30` | no |
| containers | A map of containers to create in the Storage Account (key arbitrary; name + optional access\_type). | <pre>map(object({<br>    name        = string<br>    access_type = optional(string, "private")<br>  }))</pre> | `{}` | no |
| cross\_tenant\_replication\_enabled | Allow object replication across Azure AD tenants. | `bool` | `false` | no |
| customer\_managed\_key | Customer-Managed Key (CMK) configuration backed by Azure Key Vault. See the ../StorageAccount module for prerequisites. | <pre>object({<br>    key_vault_key_id          = string<br>    user_assigned_identity_id = string<br>  })</pre> | `null` | no |
| default\_to\_oauth\_authentication | Default the portal/CLI to AAD OAuth instead of access keys for data-plane operations. | `bool` | `true` | no |
| file\_shares | A map of file shares to create (key arbitrary; name + quota\_gb + optional access\_tier). | <pre>map(object({<br>    name        = string<br>    quota_gb    = number<br>    access_tier = optional(string)<br>  }))</pre> | `{}` | no |
| identity\_ids | Set of UAMI resource IDs to attach when identity\_type contains 'UserAssigned'. | `set(string)` | `[]` | no |
| identity\_type | Identity type: SystemAssigned, UserAssigned, or SystemAssigned,UserAssigned | `string` | `null` | no |
| infrastructure\_encryption\_enabled | Enable infrastructure-level AES-256 encryption (double encryption). Immutable after creation. | `bool` | `true` | no |
| local\_user\_enabled | Enable local users for SFTP/NFS. | `bool` | `false` | no |
| lock | Management lock applied to the Storage Account (CanNotDelete or ReadOnly). | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit Storage Account name (3-24 lowercase alphanumeric). If null, computed by the canonical StorageAccount module from the naming components. | `string` | `null` | no |
| network\_rules | Storage Account firewall rules. When null, no network\_rules block is created. See the ../StorageAccount module for the full shape. | <pre>object({<br>    default_action             = string<br>    bypass                     = optional(list(string), ["AzureServices"])<br>    virtual_network_subnet_ids = optional(list(string), [])<br>    ip_rules                   = optional(list(string), [])<br>  })</pre> | `null` | no |
| private\_endpoints | A map of Private Endpoints to create, keyed by Storage **sub-resource**<br>(`blob`, `file`, `queue`, `table`, `web`, `dfs`, plus the `*_secondary`<br>variants for RA-GRS read access). Azure requires one Private Endpoint per<br>sub-resource, each resolving via its own private DNS zone<br>(e.g. `privatelink.blob.core.windows.net`).<br><br>Per-entry fields (all optional):<br>- `private_dns_zone_ids`          - Private DNS zone IDs for this sub-resource's zone. Omit when an ALZ DINE policy wires DNS (the PrivateEndpoint module ignores drift on the zone group).<br>- `private_ip_address`            - Static private IPv4 (dynamic when null).<br>- `custom_network_interface_name` - Custom NIC name.<br><br>Default `{ blob = {} }` — a single Blob Private Endpoint. Set `{}` to create no PE. | <pre>map(object({<br>    private_dns_zone_ids          = optional(list(string))<br>    private_ip_address            = optional(string)<br>    custom_network_interface_name = optional(string)<br>  }))</pre> | <pre>{<br>  "blob": {}<br>}</pre> | no |
| public\_network\_access\_enabled | Enable public network access. Secure default false — reach the account over the Private Endpoint(s). | `bool` | `false` | no |
| role\_assignments | A map of role assignments to create on the Storage Account (forwarded to the canonical StorageAccount module). The map key is arbitrary. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    principal_id                           = string<br>    principal_type                         = optional(string)<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    description                            = optional(string)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string)<br>  }))</pre> | `{}` | no |
| sas\_policy | Optional SAS token expiration policy (expiration\_period ISO 8601 `d.HH:mm:ss`; expiration\_action Log/Block). | <pre>object({<br>    expiration_period = string<br>    expiration_action = optional(string, "Log")<br>  })</pre> | `null` | no |
| shared\_access\_key\_enabled | Enable shared access keys (account keys / connection strings). Disable to force AAD-only auth. | `bool` | `false` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| containers | Map of container key => { id, name } |
| file\_shares | Map of file share key => { id, name, url } |
| id | Storage Account ID |
| name | Storage Account name |
| primary\_access\_key | Primary access key (empty when shared\_access\_key\_enabled = false) |
| primary\_blob\_endpoint | Primary blob endpoint URL |
| primary\_file\_endpoint | Primary Azure Files endpoint URL |
| private\_endpoint\_ids | Map of Storage sub-resource => Private Endpoint resource ID. |
| private\_endpoint\_ip\_addresses | Map of Storage sub-resource => Private Endpoint private IP address. |
<!-- END_TF_DOCS -->
