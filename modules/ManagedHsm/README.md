# ManagedHsm

Deploys an **Azure Key Vault Managed HSM** (`Microsoft.KeyVault/managedHSMs`) — a fully-managed, single-tenant, **FIPS 140-3 Level 3** validated HSM pool. One Managed HSM + optional Resource Lock. Hardened, secure-by-default posture.

## Security posture (baked in)

Grounded in [Secure your Managed HSM](https://learn.microsoft.com/azure/key-vault/managed-hsm/secure-managed-hsm) and [soft-delete & purge protection](https://learn.microsoft.com/azure/key-vault/managed-hsm/recovery):

- **Purge protection FORCED `true`** — mandatory for production and **irreversible** (no one, including Microsoft, can disable it). Not exposed as a variable.
- **Soft-delete always on**, 7–90 days (default 90), **immutable once set**. A soft-deleted HSM keeps billing until purged, and its globally-unique name can't be reused until purged.
- **Public network access OFF** by default (reach it via Private Endpoint).
- **Network ACLs deny-by-default** (`default_action = "Deny"`, `bypass = "AzureServices"`).
- **`prevent_destroy = true`** on the resource + optional `lock`.

## Local RBAC (data-plane) — `role_assignments`

Managed HSM has its **own local RBAC** at the data plane, **separate from Azure RBAC**, and it stores **only keys** (no secrets/certs) — so roles are key-centric. Assign them via `role_assignments`:

```hcl
role_assignments = {
  soc_crypto_user = {
    principal_id         = azuread_group.soc.object_id
    role_definition_name = "Managed HSM Crypto User"   # built-in
    scope                = "/keys"                       # "/" | "/keys" | "/keys/<key-name>"
  }
}
```

Built-in roles (name → what it grants): **Administrator** (security domain, backup/restore, role mgmt — *not* key ops), **Crypto Officer** (role mgmt + purge/recover/export keys), **Crypto User** (all key ops except purge/recover/export), **Policy Administrator** (role assignments), **Crypto Auditor** (read key attributes), **Crypto Service Encryption User** (use a key for service encryption, e.g. CMK), **Crypto Service Release User**, **Backup**, **Restore**. Set `role_definition_id` instead of `role_definition_name` for a custom role.

> ⚠️ **Activation required.** Local-RBAC assignments (and the role-definition lookup) are **data-plane** operations — they need the HSM to be **activated** (security domain downloaded). On a fresh HSM they **fail at create time**. Apply them in a **second stage/apply** after activation, or via CLI. Default `{}` = none.

## Out of scope (post-deploy, data plane)

- **Security domain activation** — a new Managed HSM is created but **not activated**. Activate it with 3–10 Key Vault certificates + a quorum ([activate](https://learn.microsoft.com/azure/key-vault/managed-hsm/quick-create-cli#activate-your-managed-hsm)); store the security-domain keys offline. Not managed here.
- **Data-plane RBAC & keys** — Crypto Officer/User role assignments and key creation/rotation happen at the HSM data plane after activation.
- **Purge-on-destroy** — to actually purge (not soft-delete) on `terraform destroy`, set the provider feature toggle:
  ```hcl
  provider "azurerm" {
    features { key_vault { purge_soft_deleted_hardware_security_modules_on_destroy = true } }
  }
  ```

## Naming

`mhsm-{acronym}-{env}-{region}[-{workload}]` → e.g. **`mhsm-idt-prod-gwc`**. `workload` is **optional** (omitted by default). Set `name` to override. Composed manually (not via `../Naming`) because that submodule requires a mandatory `workload` segment, which the mHSM convention leaves optional. Name must be 3–24 chars, alphanumeric + hyphens, start with a letter.

## Usage

```hcl
module "hsm" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/ManagedHsm?ref=v0.3.0"

  subscription_acronym = "idt"
  environment          = "prod"
  region_code          = "gwc"
  # workload           = "keys"   # optional → mhsm-idt-prod-gwc-keys

  location            = "germanywestcentral"
  resource_group_name = azurerm_resource_group.hsm.name

  admin_object_ids = [data.azurerm_client_config.current.object_id]
  # tenant_id       = "..."   # null = current tenant

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | `null` | Explicit name (3-24 chars). Null = derived. |
| `subscription_acronym` | `string` | `null` | Naming component (required unless `name` set). |
| `environment` | `string` | `null` | Environment (`prod`/`nprd`). |
| `region_code` | `string` | `null` | Region short code (e.g. `gwc`). |
| `workload` | `string` | `null` | **Optional** naming suffix segment. |
| `location` | `string` | — (required) | Azure region. |
| `resource_group_name` | `string` | — (required) | RG hosting the HSM. |
| `admin_object_ids` | `list(string)` | — (required) | Entra object IDs of initial HSM admins (≥ 1). ForceNew. |
| `tenant_id` | `string` | `null` | Tenant ID. Null = current tenant. |
| `sku_name` | `string` | `"Standard_B1"` | Only `Standard_B1`. |
| `soft_delete_retention_days` | `number` | `90` | 7-90. Immutable once set. |
| `public_network_access_enabled` | `bool` | `false` | Allow public networks. |
| `network_acls` | `object({ bypass, default_action })` | `{ AzureServices, Deny }` | Network ACLs. |
| `role_assignments` | `map(object(...))` | `{}` | Local-RBAC (data-plane) role assignments — see below. |
| `lock` | `object({ kind, name })` | `null` | Optional CanNotDelete/ReadOnly lock. |
| `tags` | `map(string)` | `{}` | Tags. |

`purge_protection_enabled` is **not** an input — forced `true`.

## Outputs

| Name | Description |
|------|-------------|
| `id` | Managed HSM resource ID. |
| `name` | Managed HSM name. |
| `hsm_uri` | HSM URI for data-plane key operations. |
| `role_assignment_ids` | Map of `role_assignments` key → local-RBAC assignment ID. |
| `lock_ids` | Map of lock IDs (empty when `lock` is null). |

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: derived naming, name override, optional workload suffix, hardened defaults (purge protection forced, public access off, deny-by-default ACLs, retention 90), optional lock, and validators (empty admins, retention < 7, bad sku, bad ACL action, name too long). Run: `terraform init -backend=false && terraform test`.

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

## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault_managed_hardware_security_module.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_managed_hardware_security_module) | resource |
| [azurerm_key_vault_managed_hardware_security_module_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_managed_hardware_security_module_role_assignment) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_key_vault_managed_hardware_security_module_role_definition.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault_managed_hardware_security_module_role_definition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| admin\_object\_ids | Entra ID object IDs of the initial Managed HSM administrators (Crypto Officer/User at the data plane). At least one required. Changing this forces a new resource. | `list(string)` | n/a | yes |
| location | Azure region where the Managed HSM is deployed. | `string` | n/a | yes |
| resource\_group\_name | Resource group hosting the Managed HSM. | `string` | n/a | yes |
| environment | Environment (e.g. prod, nprd). | `string` | `null` | no |
| lock | Optional Resource Lock. The resource also carries an unconditional<br>`lifecycle.prevent_destroy` guard at the Terraform level — this variable<br>adds a second, Azure-side guard that survives state loss/refresh.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional explicit name (3-24 chars). If null, computed as mhsm-{acronym}-{env}-{region}[-{workload}]. | `string` | `null` | no |
| network\_acls | Network ACLs. bypass: AzureServices \| None. default\_action: Allow \| Deny (default Deny — deny-by-default posture). | <pre>object({<br>    bypass         = optional(string, "AzureServices")<br>    default_action = optional(string, "Deny")<br>  })</pre> | `{}` | no |
| public\_network\_access\_enabled | Allow traffic from public networks. Default false (secure — reach it via Private Endpoint). | `bool` | `false` | no |
| region\_code | Region code (e.g. gwc, weu). | `string` | `null` | no |
| role\_assignments | Managed HSM LOCAL RBAC (data-plane) role assignments, keyed by an arbitrary<br>stable key. Each entry sets EXACTLY ONE of role\_definition\_name (built-in)<br>or role\_definition\_id (custom). Built-in role names:<br>  Managed HSM Administrator \| Managed HSM Crypto Officer \|<br>  Managed HSM Crypto User \| Managed HSM Policy Administrator \|<br>  Managed HSM Crypto Auditor \| Managed HSM Crypto Service Encryption User \|<br>  Managed HSM Crypto Service Release User \| Managed HSM Backup \| Managed HSM Restore<br>scope: "/" (HSM-wide), "/keys" (all keys, default), or "/keys/<key-name>".<br>REQUIRES the HSM to be activated (security domain) — typically a second apply. | <pre>map(object({<br>    principal_id         = string<br>    scope                = optional(string, "/keys") # "/" | "/keys" | "/keys/<key-name>"<br>    role_definition_name = optional(string)          # built-in role name (see below)<br>    role_definition_id   = optional(string)          # OR explicit role definition resource id (custom roles)<br>    name                 = optional(string)          # GUID; auto-generated (uuidv5) when null<br>  }))</pre> | `{}` | no |
| sku\_name | Managed HSM SKU. Only Standard\_B1 is available. | `string` | `"Standard_B1"` | no |
| soft\_delete\_retention\_days | Soft-delete retention window in days (7-90, default 90). Immutable once set. Soft-delete is always on for Managed HSM. | `number` | `90` | no |
| subscription\_acronym | Subscription acronym (e.g. idt, con, sec). | `string` | `null` | no |
| tags | Tags to apply to the Managed HSM. | `map(string)` | `{}` | no |
| tenant\_id | Entra ID tenant ID for authenticating requests. Null = current tenant (data.azurerm\_client\_config). | `string` | `null` | no |
| workload | Optional workload suffix segment. Null = omitted from the name (mhsm-{acr}-{env}-{region}). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| hsm\_uri | The URI of the Managed HSM, used for data-plane key operations. |
| id | The ID of the Managed HSM. |
| lock\_ids | Map of management lock IDs (empty when var.lock is null). |
| name | The name of the Managed HSM. |
| role\_assignment\_ids | Map of role\_assignments key => local-RBAC role assignment ID (empty when none). |
<!-- END_TF_DOCS -->
