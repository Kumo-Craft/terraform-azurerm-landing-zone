###############################################################
# MODULE: DiskEncryptionSet - Main
#
# A Disk Encryption Set (DES) is the object that binds managed disks to
# a customer-managed key in Key Vault. It is what turns
# `EncryptionAtRestWithPlatformKey` into `EncryptionAtRestWithCustomerKey`
# — the state the ALZ guardrail `deny-osanddatadisk-cmk` (initiative
# Enforce-Guardrails-Encrypt-CMK) requires.
#
# The Key Vault and the key are INPUTS — compose ../KeyVaultStack and
# ../KeyVault-Key. This module never creates either: a DES is disposable,
# a key is not, and losing the key makes every disk bound to it
# unreadable.
#
# ⚠️ KEY VAULT PREREQUISITES (Azure refuses the DES otherwise):
#   - purge protection ENABLED — non-negotiable and IRREVERSIBLE on the
#     vault. Azure will not let a DES point at a vault that can be purged.
#   - soft delete enabled (implicit on any vault created since 2021).
#
# ⚠️ ORDER OF OPERATIONS. The DES gets a managed identity, and that
# identity must be able to read the key. The module wires this itself
# (see the role assignment below) — but the grant necessarily happens
# AFTER the DES exists, because the principal id doesn't exist before
# then. A disk referencing this DES must therefore depend on
# `role_assignment_id`, not just on `id`. Attaching a disk to a DES whose
# identity has no key access fails at the disk, not at the DES.
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming — delegated to ../Naming, giving
# des-{acr}-{env}-{region}-{workload}. The for_each guard keeps the
# module out of the graph when var.name is set.
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  name = coalesce(var.name, try(module.naming["this"].result.disk_encryption_set.name, null))

  # UserAssigned needs ids; SystemAssigned must not carry them.
  identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
}

###############################################################
# RESOURCE: Disk Encryption Set
###############################################################
resource "azurerm_disk_encryption_set" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # ⚠️ auto_key_rotation_enabled = true REQUIRES a versionless key id
  # (.../keys/<name>, no trailing version). Passing a versioned id with
  # rotation on pins the DES to that version forever and Azure silently
  # stops following the rotation policy. The validation on
  # var.key_vault_key_id enforces the pairing at plan time rather than
  # letting it fail quietly at runtime.
  key_vault_key_id          = var.key_vault_key_id
  auto_key_rotation_enabled = var.auto_key_rotation_enabled

  # EncryptionAtRestWithCustomerKey  — CMK on the data, platform key on
  #                                    the VM guest state. What
  #                                    deny-osanddatadisk-cmk asks for.
  # EncryptionAtRestWithPlatformAndCustomerKeys — double encryption.
  # ConfidentialVmEncryptedWithCustomerKey      — Confidential VMs only,
  #                                    NOT Trusted Launch. Picking it for
  #                                    a Trusted Launch host makes the VM
  #                                    unbootable.
  encryption_type = var.encryption_type

  federated_client_id = var.federated_client_id

  identity {
    type         = var.identity_type
    identity_ids = local.identity_ids
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )
}

###############################################################
# RBAC: let the DES identity read the key.
#
# "Key Vault Crypto Service Encryption User" is the least-privilege role
# for this: wrap/unwrap/get on keys, nothing else. Do NOT substitute
# "Key Vault Crypto Officer" — it can delete keys, and the identity that
# encrypts your disks has no business being able to destroy the key that
# decrypts them.
#
# Skipped when key_vault_id is null: some tenants grant this out-of-band
# (a platform pipeline owning all vault RBAC). Leaving it null is a
# deliberate opt-out, not a default — the disk will fail to attach until
# someone else grants it.
###############################################################
module "key_access" {
  source   = "../RoleAssignment"
  for_each = var.key_vault_id == null ? toset([]) : toset(["this"])

  scope                            = var.key_vault_id
  role_definition_id_or_name       = "Key Vault Crypto Service Encryption User"
  principal_id                     = azurerm_disk_encryption_set.this.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  description                      = "Disk Encryption Set ${local.name} unwraps the CMK protecting its managed disks"
}
