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
