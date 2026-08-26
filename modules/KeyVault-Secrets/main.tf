###############################################################
# MODULE: KeyVaultSecrets - Main
# Description: Push secrets to a Key Vault. Supports random generation.
###############################################################

locals {
  # nonsensitive() is required because var.secrets is sensitive=true.
  # The map keys are secret names (resource identifiers, not secret values)
  # and must be visible to Terraform's for_each machinery. The sensitive
  # payloads (value, generate.*) remain protected inside each.value.
  generated_secrets   = { for k, v in nonsensitive(var.secrets) : k => v if v.generate != null }
  time_offset_secrets = { for k, v in nonsensitive(var.secrets) : k => v if v.expiration_days != null }
}

###############################################################
# RESOURCE: Module-level timestamp (frozen at first apply)
###############################################################
resource "time_static" "time" {}

###############################################################
# RESOURCE: Random Passwords
###############################################################
resource "random_password" "this" {
  for_each = nonsensitive(local.generated_secrets)

  length           = each.value.generate.length
  special          = each.value.generate.special
  override_special = each.value.generate.override_special
}

###############################################################
# RESOURCE: Expiration Timestamps (stable across applies)
###############################################################
resource "time_offset" "expiration" {
  for_each = nonsensitive(local.time_offset_secrets)

  offset_days = each.value.expiration_days
}

###############################################################
# RESOURCE: Key Vault Secrets
###############################################################
resource "azurerm_key_vault_secret" "this" {
  for_each = nonsensitive(var.secrets)

  name  = each.value.name
  value = coalesce(each.value.value, try(random_password.this[each.key].result, null))

  key_vault_id    = var.key_vault_id
  content_type    = each.value.content_type
  expiration_date = try(time_offset.expiration[each.key].rfc3339, each.value.expiration_date)
  not_before_date = each.value.not_before_date
  tags = merge(
    var.tags,
    each.value.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # Ignore value drift so we can rotate out-of-band without Terraform reverting.
  lifecycle {
    ignore_changes = [value]
  }
}
