# KeyVault-Key

Creates one or more Azure Key Vault keys (RSA, EC, RSA-HSM, EC-HSM) with support for automatic rotation policies, custom expiration dates (default +2 years), and configurable key operations.

## Usage

### Standalone

```hcl
module "key_vault_key" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/KeyVault-Key?ref=v0.2.27"

  keys = {
    cmk_disk = {
      name         = "cmk-disk-encryption"
      key_type     = "RSA"
      key_vault_id = "/subscriptions/.../vaults/kv-api-prod-gwc-apim"
      key_size     = 4096
      key_opts     = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]

      rotation_policy = {
        expire_after         = "P2Y"
        notify_before_expiry = "P30D"
        automatic = {
          time_after_creation = "P1Y"
        }
      }
    }
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/KeyVault-Key"
}

inputs = {
  keys = {
    etcd = {
      name         = "aks-etcd-key"
      key_vault_id = dependency.kv.outputs.key_vault_id
      key_type     = "RSA"
      key_size     = 2048
      key_opts     = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]

      rotation_policy = {
        expire_after         = "P2Y"
        notify_before_expiry = "P30D"
        automatic = {
          time_after_creation = "P1Y"
        }
      }
    }
  }
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
| keys | Map of Key Vault keys to create with their configuration | `map(object({...}))` | -- | Yes |

### Key Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | `string` | Yes | Key name |
| key_vault_id | `string` | Yes | Full Key Vault resource ID |
| key_type | `string` | Yes | `RSA`, `EC`, `RSA-HSM`, or `EC-HSM`. **HSM types (RSA-HSM, EC-HSM) require the target Key Vault to have `sku_name = "premium"` (FIPS 140-2 Level 3).** Setting RSA-HSM/EC-HSM against a Standard tier KV results in an ARM error at apply. |
| key_size | `number` | RSA only | `2048`, `3072`, or `4096` |
| curve | `string` | EC only | `P-256`, `P-384`, `P-521`, or `P-256K` |
| key_opts | `list(string)` | No | Key operations (default: all) |
| not_before_date | `string` | No | UTC datetime `Y-m-dTH:M:SZ` |
| expiration_date | `string` | No | UTC datetime (default: +2 years from module's first apply timestamp). **Important**: timestamp is FROZEN at first creation. For new keys added to an existing deployment, ALWAYS set this explicitly. |
| tags | `map(string)` | No | Key-specific tags |
| rotation_policy | `object` | No | Rotation config (ISO 8601 durations) |

### Rotation Policy Object

| Field | Type | Description |
|-------|------|-------------|
| expire_after | `string` | ISO 8601 duration (e.g. `P2Y`) |
| notify_before_expiry | `string` | ISO 8601 duration (e.g. `P30D`) |
| automatic.time_after_creation | `string` | Auto-rotate after creation (e.g. `P1Y`) |
| automatic.time_before_expiry | `string` | Auto-rotate before expiry |

## Notes

### Default expiration and time_static singleton

When `expiration_date` is omitted, the module computes a default of `+2 years from the module's first apply timestamp` (via a module-level `time_static`). This timestamp is FROZEN at first creation. If you add a NEW key to `var.keys` long after the initial deploy (e.g. 18 months later), that new key will inherit the OLD base — expiring sooner than 2y from its actual creation.

**For new keys added to an existing deployment, ALWAYS set `expiration_date` explicitly.**

## Outputs

| Name | Description |
|------|-------------|
| keys | Full azurerm_key_vault_key resources by map key |
| ids | Versioned Key IDs |
| versionless_ids | Versionless Key IDs (for CMK auto-rotation consumers) |
| names | Map of key names |

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

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault_key.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_key) | resource |
| [time_offset.expiry_plus_2y](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/offset) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| keys | Map of Key Vault keys to create. The map key is used as the resource identifier.<br><br>- `name`            - (Required) Key name. Must start with a letter and contain only alphanumerics and hyphens (1-127 chars).<br>- `key_vault_id`    - (Required) Full Key Vault resource ID.<br>- `key_type`        - (Required) RSA, EC, RSA-HSM, or EC-HSM.<br>                      **HSM types (RSA-HSM, EC-HSM) require the target Key Vault to have `sku_name = "premium"` (FIPS 140-2 Level 3).** Setting RSA-HSM/EC-HSM against a Standard tier KV results in an ARM error at apply.<br>- `key_size`        - (Optional) 2048, 3072, or 4096 (required for RSA).<br>- `curve`           - (Optional) P-256, P-384, P-521, or P-256K (required for EC).<br>- `key_opts`        - (Optional) Key operations. Must be a subset of: encrypt, decrypt, sign, verify, wrapKey, unwrapKey. Defaults to all operations.<br>- `not_before_date` - (Optional) Key not usable before this UTC datetime (Y-m-d'T'H:M:S'Z').<br>- `expiration_date` - (Optional) Key expiration UTC datetime. Defaults to +2 years from the module's first apply timestamp (via a module-level `time_static`). **Important**: This timestamp is FROZEN at first creation. If you add a NEW key to `var.keys` long after the initial deploy (e.g. 18 months later), that new key will inherit the OLD base — expiring sooner than 2y from its actual creation. **For new keys added to an existing deployment, ALWAYS set `expiration_date` explicitly.**<br>- `tags`            - (Optional) Key-specific tags. Merged with module-level `var.tags`; per-key tags win on conflict.<br>- `rotation_policy` - (Optional) Automatic rotation configuration (ISO 8601 durations). `automatic` requires EXACTLY ONE of `time_after_creation` or `time_before_expiry` (mutually exclusive per Azure rotation policy API). | <pre>map(object({<br>    name            = string<br>    key_vault_id    = string<br>    key_type        = string<br>    key_size        = optional(number)<br>    curve           = optional(string)<br>    key_opts        = optional(list(string), ["encrypt", "decrypt", "wrapKey", "unwrapKey", "sign", "verify"])<br>    not_before_date = optional(string)<br>    expiration_date = optional(string)<br>    tags            = optional(map(string), {})<br>    rotation_policy = optional(object({<br>      expire_after         = optional(string)<br>      notify_before_expiry = optional(string)<br>      automatic = optional(object({<br>        time_after_creation = optional(string)<br>        time_before_expiry  = optional(string)<br>      }))<br>    }))<br>  }))</pre> | n/a | yes |
| tags | Module-level tags merged with per-key tags + CreatedOn. Per-key tags win on conflict. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of key map key => versioned Key ID |
| keys | Full azurerm\_key\_vault\_key resources by map key |
| names | Map of key map key => key name |
| versionless\_ids | Map of key map key => versionless Key ID (for CMK auto-rotation consumers) |
<!-- END_TF_DOCS -->
