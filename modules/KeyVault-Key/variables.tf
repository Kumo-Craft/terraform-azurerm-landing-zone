###############################################################
# MODULE: KeyVault-Key - Variables
###############################################################

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Module-level tags merged with per-key tags + CreatedOn. Per-key tags win on conflict."
}

variable "keys" {
  description = <<-EOT
  Map of Key Vault keys to create. The map key is used as the resource identifier.

  - `name`            - (Required) Key name. Must start with a letter and contain only alphanumerics and hyphens (1-127 chars).
  - `key_vault_id`    - (Required) Full Key Vault resource ID.
  - `key_type`        - (Required) RSA, EC, RSA-HSM, or EC-HSM.
                        **HSM types (RSA-HSM, EC-HSM) require the target Key Vault to have `sku_name = "premium"` (FIPS 140-2 Level 3).** Setting RSA-HSM/EC-HSM against a Standard tier KV results in an ARM error at apply.
  - `key_size`        - (Optional) 2048, 3072, or 4096 (required for RSA).
  - `curve`           - (Optional) P-256, P-384, P-521, or P-256K (required for EC).
  - `key_opts`        - (Optional) Key operations. Must be a subset of: encrypt, decrypt, sign, verify, wrapKey, unwrapKey. Defaults to all operations.
  - `not_before_date` - (Optional) Key not usable before this UTC datetime (Y-m-d'T'H:M:S'Z').
  - `expiration_date` - (Optional) Key expiration UTC datetime. Defaults to +2 years from the module's first apply timestamp (via a module-level `time_static`). **Important**: This timestamp is FROZEN at first creation. If you add a NEW key to `var.keys` long after the initial deploy (e.g. 18 months later), that new key will inherit the OLD base — expiring sooner than 2y from its actual creation. **For new keys added to an existing deployment, ALWAYS set `expiration_date` explicitly.**
  - `tags`            - (Optional) Key-specific tags. Merged with module-level `var.tags`; per-key tags win on conflict.
  - `rotation_policy` - (Optional) Automatic rotation configuration (ISO 8601 durations). `automatic` requires EXACTLY ONE of `time_after_creation` or `time_before_expiry` (mutually exclusive per Azure rotation policy API).
  EOT
  type = map(object({
    name            = string
    key_vault_id    = string
    key_type        = string
    key_size        = optional(number)
    curve           = optional(string)
    key_opts        = optional(list(string), ["encrypt", "decrypt", "wrapKey", "unwrapKey", "sign", "verify"])
    not_before_date = optional(string)
    expiration_date = optional(string)
    tags            = optional(map(string), {})
    rotation_policy = optional(object({
      expire_after         = optional(string)
      notify_before_expiry = optional(string)
      automatic = optional(object({
        time_after_creation = optional(string)
        time_before_expiry  = optional(string)
      }))
    }))
  }))
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.keys :
      contains(["RSA", "EC", "RSA-HSM", "EC-HSM"], v.key_type)
    ])
    error_message = "key_type must be one of: RSA, EC, RSA-HSM, EC-HSM."
  }

  validation {
    condition = alltrue([
      for k, v in var.keys :
      !contains(["RSA", "RSA-HSM"], v.key_type) || (
        v.key_size == null || contains([2048, 3072, 4096], v.key_size)
      )
    ])
    error_message = "For RSA keys, key_size must be 2048, 3072, or 4096 (or null to default to 2048)."
  }

  validation {
    condition = alltrue([
      for k, v in var.keys :
      v.rotation_policy == null ||
      v.rotation_policy.automatic == null ||
      (v.rotation_policy.automatic.time_after_creation != null) !=
      (v.rotation_policy.automatic.time_before_expiry != null)
    ])
    error_message = "rotation_policy.automatic requires EXACTLY ONE of time_after_creation or time_before_expiry (mutually exclusive per Azure rotation policy API)."
  }

  validation {
    condition = alltrue([
      for k, v in var.keys :
      !contains(["EC", "EC-HSM"], v.key_type) || (
        v.curve != null && contains(["P-256", "P-384", "P-521", "P-256K"], v.curve)
      )
    ])
    error_message = "For EC keys, curve must be one of: P-256, P-384, P-521, P-256K."
  }

  validation {
    condition = alltrue([
      for k, v in var.keys :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", v.key_vault_id))
    ])
    error_message = "key_vault_id must be a full Azure Key Vault resource ID."
  }

  validation {
    condition = alltrue([
      for k, v in var.keys :
      v.expiration_date == null || can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", v.expiration_date))
    ])
    error_message = "expiration_date must be in UTC datetime format: Y-m-dTH:M:SZ."
  }

  validation {
    condition = alltrue([
      for k, v in var.keys :
      v.not_before_date == null || can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", v.not_before_date))
    ])
    error_message = "not_before_date must be in UTC datetime format: Y-m-dTH:M:SZ."
  }

  validation {
    condition = alltrue([
      for k, v in var.keys : alltrue([
        for op in v.key_opts : contains(["encrypt", "decrypt", "sign", "verify", "wrapKey", "unwrapKey"], op)
      ])
    ])
    error_message = "key_opts must be a subset of: encrypt, decrypt, sign, verify, wrapKey, unwrapKey."
  }

  validation {
    condition = alltrue([
      for k, v in var.keys :
      can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,126}$", v.name))
    ])
    error_message = "Key name must start with a letter and contain only alphanumerics and hyphens (1-127 chars)."
  }
}
