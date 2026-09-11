# ManagedHsmStack

Batteries-included **Managed HSM + Private Endpoint** — composes the canonical [`../ManagedHsm`](../ManagedHsm/) and [`../PrivateEndpoint`](../PrivateEndpoint/) leaf modules. The **Stack** counterpart to the `ManagedHsm` leaf, mirroring [`KeyVaultStack`](../KeyVaultStack/) (which composes `KeyVault` + `PrivateEndpoint`).

Use this when you want a private-by-default Managed HSM in one module call. Use the bare `../ManagedHsm` leaf if you compose the Private Endpoint yourself.

## What it creates

- **`../ManagedHsm`** — the HSM (hardened: purge protection forced, deny-by-default ACLs, public access off, `prevent_destroy`). All HSM inputs are forwarded; the leaf owns their validation.
- **`../PrivateEndpoint`** — a single Private Endpoint targeting the HSM, sub-resource **`managedhsm`**, wired to the `privatelink.managedhsm.azure.net` DNS zone.

The Resource Group is **caller-provided** (`resource_group_name`) — repo convention. Wire it from a `../ResourceGroup` module instance upstream.

## Naming

- HSM: `mhsm-{acr}-{env}-{region}[-{workload}]` (workload optional) → `mhsm-idt-prod-gwc`.
- Private Endpoint: `pep-{hsm_name}` → `pep-mhsm-idt-prod-gwc`.

## Managed HSM vs Key Vault private link

| | sub-resource | private DNS zone |
|---|---|---|
| Key Vault | `vault` | `privatelink.vaultcore.azure.net` |
| **Managed HSM** | `managedhsm` | `privatelink.managedhsm.azure.net` |

## Usage

```hcl
module "hsm_stack" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/ManagedHsmStack?ref=v0.3.0"

  subscription_acronym = "idt"
  environment          = "prod"
  region_code          = "gwc"
  # workload           = "keys"   # optional

  location            = "germanywestcentral"
  resource_group_name = azurerm_resource_group.hsm.name

  admin_object_ids = [data.azurerm_client_config.current.object_id]

  subnet_id            = module.network.subnet_ids["snet-pe"]
  private_dns_zone_ids = [module.dns.zone_ids["privatelink.managedhsm.azure.net"]]

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

## Inputs

Naming + HSM inputs are forwarded to `../ManagedHsm` (see its README for full semantics — `purge_protection_enabled` is forced `true` there).

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | `null` | Explicit HSM name (3-24). Null = derived. |
| `subscription_acronym` / `environment` / `region_code` | `string` | `null` | Naming components. |
| `workload` | `string` | `null` | **Optional** naming suffix. |
| `location` | `string` | — (required) | Azure region. |
| `resource_group_name` | `string` | — (required) | RG for HSM + PE. |
| `subnet_id` | `string` | — (required) | Subnet for the Private Endpoint. |
| `admin_object_ids` | `list(string)` | — (required) | Initial HSM admins (≥ 1). |
| `tenant_id` | `string` | `null` | Tenant ID (null = current). |
| `sku_name` | `string` | `"Standard_B1"` | HSM SKU. |
| `soft_delete_retention_days` | `number` | `90` | 7-90. |
| `public_network_access_enabled` | `bool` | `false` | Public access (default off). |
| `network_acls` | `object({ bypass, default_action })` | `{ AzureServices, Deny }` | HSM firewall. |
| `lock` | `object({ kind, name })` | `null` | Optional lock on the HSM. |
| `role_assignments` | `map(object(...))` | `{}` | Local-RBAC (data-plane) role assignments, forwarded to `../ManagedHsm` (requires HSM activation — see its README). |
| `enable_backup_identity` | `bool` | `false` | Create a user-assigned MI for HSM backup/restore (see below). |
| `backup_identity_name` | `string` | `null` | Override for the backup UAMI name (null = `id-{hsm_name}-backup`). |
| `backup_storage_scope_id` | `string` | `null` | Storage account/container id to grant the UAMI `Storage Blob Data Contributor`. |
| `private_dns_zone_ids` | `list(string)` | `null` | DNS zone IDs for the PE (use `privatelink.managedhsm.azure.net`). |
| `pe_private_ip_address` | `string` | `null` | Optional static PE IP. |
| `pe_custom_network_interface_name` | `string` | `null` | Optional PE NIC name. |
| `tags` | `map(string)` | `{}` | Tags. |

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | RG name (passthrough). |
| `hsm_id` / `hsm_name` / `hsm_uri` | Managed HSM identifiers. |
| `hsm_lock_ids` | HSM lock IDs (empty when no lock). |
| `hsm_role_assignment_ids` | Local-RBAC role assignment IDs (empty when none). |
| `backup_identity_id` / `backup_identity_principal_id` / `backup_identity_client_id` | Backup UAMI identifiers (null when `enable_backup_identity = false`). |
| `private_endpoint_id` / `private_endpoint_name` / `private_endpoint_ip` | Private Endpoint identifiers. |

## Backup identity (`enable_backup_identity`)

Managed HSM **full backup/restore** authenticates to the backup storage account via a **user-assigned managed identity** holding `Storage Blob Data Contributor` on the container ([backup/restore](https://learn.microsoft.com/azure/key-vault/managed-hsm/backup-restore)). Set `enable_backup_identity = true` and the Stack composes `../ManagedIdentity` to create that UAMI; pass `backup_storage_scope_id` to also grant the storage role.

```hcl
enable_backup_identity  = true
backup_storage_scope_id = azurerm_storage_container.mhsm_backup.resource_manager_id
```

> ⚠️ **Two out-of-band steps remain** (the azurerm Managed HSM resource has **no `identity` block**, so Terraform can't associate the UAMI to the HSM):
> 1. Associate the UAMI to the HSM:
>    `az keyvault update-hsm --hsm-name <name> --mi-user-assigned <backup_identity_id>`
> 2. Run the backup (after the HSM is activated):
>    `az keyvault backup start --use-managed-identity true --hsm-name <name> --storage-account-name <sa> --blob-container-name <container>`
>
> The `backup_identity_id` output gives you the value for step 1.

## Out of scope

Same as the `../ManagedHsm` leaf: **security-domain activation** (3-10 KV certs + quorum), data-plane RBAC/keys, and the provider `purge_soft_deleted_hardware_security_modules_on_destroy` toggle. The private DNS **zone** itself is caller-provided (pass its id via `private_dns_zone_ids`).

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: HSM+PE composition, name wiring (HSM + PE, incl. optional workload), `managedhsm` sub-resource, and Stack-specific validators (subnet id, PE IP). Run: `terraform init -backend=false && terraform test`.

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
| backup\_identity | ../ManagedIdentity | n/a |
| hsm | ../ManagedHsm | n/a |
| pe | ../PrivateEndpoint | n/a |

## Resources

| Name | Type |
|------|------|
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| admin\_object\_ids | Entra object IDs of the initial Managed HSM administrators (>= 1). Forwarded to ../ManagedHsm. | `list(string)` | n/a | yes |
| location | Azure region where the Managed HSM and Private Endpoint are deployed. | `string` | n/a | yes |
| resource\_group\_name | Resource group hosting the Managed HSM and Private Endpoint (caller-provided, typically from a ../ResourceGroup module instance). | `string` | n/a | yes |
| subnet\_id | Subnet ID for the Managed HSM Private Endpoint. | `string` | n/a | yes |
| backup\_identity\_name | Optional name override for the backup UAMI. Null = id-{hsm\_name}-backup. | `string` | `null` | no |
| backup\_storage\_scope\_id | Optional resource ID of the backup storage account (or blob container) to grant the backup UAMI 'Storage Blob Data Contributor'. Null = no role assignment (grant it out-of-band). Ignored when enable\_backup\_identity = false. | `string` | `null` | no |
| enable\_backup\_identity | Create a user-assigned managed identity (via ../ManagedIdentity) for Managed HSM full backup/restore. Default false. | `bool` | `false` | no |
| environment | Environment (e.g. prod, nprd). Forwarded to ../ManagedHsm. | `string` | `null` | no |
| lock | Optional Resource Lock on the Managed HSM. Forwarded to ../ManagedHsm (on top of its prevent\_destroy). | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional explicit Managed HSM name (3-24 chars). Null = derived by ../ManagedHsm as mhsm-{acr}-{env}-{region}[-{workload}]. | `string` | `null` | no |
| network\_acls | Network ACLs (bypass: AzureServices\|None, default\_action: Allow\|Deny). Forwarded to ../ManagedHsm. | <pre>object({<br>    bypass         = optional(string, "AzureServices")<br>    default_action = optional(string, "Deny")<br>  })</pre> | `{}` | no |
| pe\_custom\_network\_interface\_name | Optional custom network interface name for the Private Endpoint. | `string` | `null` | no |
| pe\_private\_ip\_address | Optional static private IP for the Private Endpoint. | `string` | `null` | no |
| private\_dns\_zone\_ids | Private DNS Zone IDs for the Private Endpoint (use the privatelink.managedhsm.azure.net zone). Null = no DNS zone group (wire DNS elsewhere). | `list(string)` | `null` | no |
| public\_network\_access\_enabled | Allow public network access. Default false (reach via the composed Private Endpoint). Forwarded to ../ManagedHsm. | `bool` | `false` | no |
| region\_code | Region code (e.g. gwc, weu). Forwarded to ../ManagedHsm. | `string` | `null` | no |
| role\_assignments | Managed HSM LOCAL RBAC (data-plane) role assignments. Forwarded to ../ManagedHsm — see its README. NOTE: requires the HSM to be activated (security domain) first; typically a second apply. | <pre>map(object({<br>    principal_id         = string<br>    scope                = optional(string, "/keys")<br>    role_definition_name = optional(string)<br>    role_definition_id   = optional(string)<br>    name                 = optional(string)<br>  }))</pre> | `{}` | no |
| sku\_name | Managed HSM SKU (only Standard\_B1). Forwarded to ../ManagedHsm. | `string` | `"Standard_B1"` | no |
| soft\_delete\_retention\_days | Soft-delete retention (7-90, default 90). Forwarded to ../ManagedHsm. | `number` | `90` | no |
| subscription\_acronym | Subscription acronym (e.g. idt, con, sec). Forwarded to ../ManagedHsm. | `string` | `null` | no |
| tags | Tags applied to the Managed HSM and Private Endpoint. | `map(string)` | `{}` | no |
| tenant\_id | Tenant ID. Null = current tenant (resolved by ../ManagedHsm). | `string` | `null` | no |
| workload | Optional workload suffix segment. Forwarded to ../ManagedHsm. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| backup\_identity\_client\_id | Client ID of the backup UAMI (null when disabled). |
| backup\_identity\_id | Resource ID of the backup UAMI (null when disabled). Associate it to the HSM via `az keyvault update-hsm --mi-user-assigned <this>`. |
| backup\_identity\_principal\_id | Principal (object) ID of the backup UAMI (null when disabled). |
| hsm\_id | The Managed HSM resource ID. |
| hsm\_lock\_ids | Map of Managed HSM management lock IDs (empty when lock is null). |
| hsm\_name | The Managed HSM name. |
| hsm\_role\_assignment\_ids | Map of role\_assignments key => local-RBAC role assignment ID (empty when none). |
| hsm\_uri | The Managed HSM URI, used for data-plane key operations. |
| private\_endpoint\_id | The Private Endpoint resource ID. |
| private\_endpoint\_ip | The private IP address of the Private Endpoint. |
| private\_endpoint\_name | The Private Endpoint name. |
| resource\_group\_name | The name of the resource group (caller-provided). |
<!-- END_TF_DOCS -->
