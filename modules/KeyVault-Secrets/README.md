# KeyVault-Secrets

Pushes one or more secrets to an existing Azure Key Vault. Supports caller-provided values OR auto-generated random passwords. Designed for caller-rotated secrets (the `ignore_changes = [value]` lifecycle preserves out-of-band rotations).

## Usage

### Standalone

```hcl
module "kv_secrets" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/KeyVault-Secrets?ref=v0.2.28"

  key_vault_id = "/subscriptions/<guid>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>"

  secrets = {
    "admin-password" = {
      name     = "admin-password"
      generate = { length = 32 }
    }
    "external-api-key" = {
      name            = "external-api-key"
      value           = var.api_key   # caller-supplied sensitive value
      content_type    = "application/json"
      expiration_date = "2027-12-31T23:59:00Z"
    }
  }

  tags = {
    Environment = "Production"
  }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/KeyVault-Secrets"
}

inputs = {
  key_vault_id = dependency.kv.outputs.id
  secrets = {
    "external-api-key" = {
      name  = "external-api-key"
      value = get_env("EXTERNAL_API_KEY")  # never lands in state
    }
  }
}
```

## Caller-rotated secrets: `ignore_changes = [value]`

The module hardcodes `lifecycle { ignore_changes = [value] }` on every secret. Once a secret is created, **Terraform will NOT overwrite the value on subsequent applies** even if `var.secrets[*].value` changes. This is the canonical pattern for caller-rotated secrets — once written, the secret can be rotated out-of-band (Azure CLI, Azure Portal, automation, Key Vault rotation policy) without Terraform fighting back.

**Trade-off**: Callers who want to manage rotations exclusively through Terraform have no opt-out today. If this becomes a need, a per-secret `force_rotate` bool toggle can be added.

## State-safe alternative: `value_wo` (Terraform 1.11+)

For callers who want the secret value to **never touch state**, Terraform 1.11+ supports `value_wo` (write-only attribute) on `azurerm_key_vault_secret`. This module does NOT yet expose `value_wo` — it is on the roadmap as an additive enhancement. Until then, callers requiring state-free secrets should:

- Use auto-generated passwords (`generate = { length = 32 }`) where possible — only the version metadata lands in state, not the password.
- Pass values via `value = var.external_secret` where `var.external_secret` is itself `sensitive = true` in the caller's root config.

## Provider dependencies

| Provider | Version | Purpose |
|---|---|---|
| azurerm | `~> 4.0` | Resource provisioning |
| time | `>= 0.9.0` | `time_static` for CreatedOn tag + `time_offset` for `expiration_days` |
| random | `>= 3.5.0` | `random_password` for auto-generated secrets (`generate` block) |

The `random` provider is required because the module supports auto-generation via the `generate` block. Callers using Terragrunt with provider caching must ensure `random` is in scope.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |
| random | >= 3.5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| key_vault_id | Full Azure Key Vault resource ID | `string` | -- | Yes |
| secrets | Map of secrets to create (see Secret Object below) | `map(object({...}))` | -- | Yes |
| tags | Module-level tags merged with per-secret tags + CreatedOn | `map(string)` | `{}` | No |

### Secret Object

| Field | Type | Required | Description |
|---|---|---|---|
| name | `string` | Yes | Secret name. Must start with a letter, alphanumerics and hyphens only, max 127 chars. |
| value | `string` | Required if generate not set | The secret value. `var.secrets` is `sensitive = true` — value never appears in plan output. |
| generate | `object` | Required if value not set | Auto-generate via `random_password`. Mutually exclusive with `value`. |
| generate.length | `number` | No | Length of generated password. Default: `32`. |
| generate.special | `bool` | No | Include special characters. Default: `true`. |
| generate.override_special | `string` | No | Restrict special chars to this set. |
| content_type | `string` | No | MIME-style hint (e.g. `"application/json"`, `"password"`). |
| expiration_date | `string` | No | UTC RFC3339 datetime (e.g. `"2027-12-31T23:59:00Z"`). Mutually exclusive with `expiration_days`. |
| not_before_date | `string` | No | UTC RFC3339 datetime — secret is not active before this date. |
| expiration_days | `number` | No | Relative expiration in days from module first-apply timestamp. See limitation below. |
| tags | `map(string)` | No | Per-secret tags. Merged with `var.tags` (module-level) + `CreatedOn`. Per-secret tags win on conflict. |

## Outputs

| Name | Description |
|---|---|
| secret_ids | Map of secret map-key => Key Vault secret resource ID |
| secret_versionless_ids | Map of secret map-key => versionless ID (useful for consumers that pull latest) |

## Notes

### Default expiration limitation

When `expiration_date` is omitted AND `expiration_days` is set, the module computes the absolute expiration relative to `time_static.time` — a module-level singleton frozen at first apply. **If you add a NEW secret to `var.secrets` long after the initial deploy (e.g. 18 months later)**, that new secret inherits the OLD base timestamp — expiring sooner than `+expiration_days` from its actual creation date.

For new secrets added to an existing deployment, **always set `expiration_date` explicitly**.

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| random | >= 3.5.0 |
| time | >= 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |
| random | >= 3.5.0 |
| time | >= 0.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault_secret.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [random_password.this](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [time_offset.expiration](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/offset) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| key\_vault\_id | Key Vault resource ID to push secrets to. | `string` | n/a | yes |
| secrets | Map of secrets to create in the Key Vault.<br>Either `value` OR `generate` must be set (mutually exclusive).<br><br>- `name`            - (Required) Secret name.<br>- `value`           - (Optional) Explicit secret value.<br>- `generate`        - (Optional) If set, random password generated by the module:<br>  - `length`         - (Optional) Password length. Defaults to 32.<br>  - `special`        - (Optional) Include special chars. Defaults to true.<br>  - `override_special` - (Optional) Restrict special chars to this set.<br>- `content_type`    - (Optional) Metadata describing the secret (e.g. "password", "key").<br>- `expiration_date` - (Optional) Explicit ISO 8601 expiration (e.g. "2027-01-01T00:00:00Z").<br>                      Mutually exclusive with expiration\_days.<br>- `expiration_days` - (Optional) Days from creation; rendered via time\_offset for stability.<br>                      Required by ALZ policy "Secrets should have max validity period".<br>- `tags`            - (Optional) Tags on the secret. | <pre>map(object({<br>    name  = string<br>    value = optional(string)<br>    generate = optional(object({<br>      length           = optional(number, 32)<br>      special          = optional(bool, true)<br>      override_special = optional(string)<br>    }))<br>    content_type    = optional(string)<br>    expiration_date = optional(string)<br>    not_before_date = optional(string)<br>    expiration_days = optional(number)<br>    tags            = optional(map(string), {})<br>  }))</pre> | n/a | yes |
| tags | Module-level tags merged with per-secret tags + CreatedOn. Per-secret tags win on conflict. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| secret\_ids | Map of secret key => Key Vault secret resource ID |
| secret\_versionless\_ids | Map of secret key => versionless ID (useful for VM CSE to pull latest) |
<!-- END_TF_DOCS -->
