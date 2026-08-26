# KeyVault-Key

Creates one or more Azure Key Vault keys (RSA, EC, RSA-HSM, EC-HSM) with support for automatic rotation policies, custom expiration dates (default +2 years), and configurable key operations.

## Usage

### Standalone

```hcl
module "key_vault_key" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/KeyVault-Key?ref=v0.2.27"

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
