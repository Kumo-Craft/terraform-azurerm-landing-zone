###############################################################
# Disk Encryption — Key Vault + Key + UAI + DES (1 per cluster)
###############################################################
# When enable_disk_encryption = true, creates:
#   1. Key Vault (composed via ../KeyVault — v0.2.26+)
#   2. RBAC deployer -> Key Vault Administrator  (via module.kv_admin)
#   3. RSA 2048 key (auto-rotation 2 years)
#   4. User Assigned Identity
#   5. RBAC UAI -> Key Vault Crypto Service Encryption User
#   6. Disk Encryption Set (double encryption, auto-rotation)
#
# v0.2.26 migration: the inline azurerm_key_vault.this resource has been
# replaced by a module "kv" composition via ../KeyVault. A moved{} block
# ensures zero Azure-side rename for existing callers (state migration only).
###############################################################

locals {
  # KV name max 24 chars — strip "palo-" from workload to shorten
  # palo-obew -> obew -> kv-con-prod-gwc-obew (20 chars)
  # palo-in   -> in   -> kv-con-prod-gwc-in   (18 chars)
  kv_workload = replace(var.workload, "palo-", "")
  kv_name     = "kv-${local.prefix}-${local.kv_workload}"
}

###############################################################
# Key Vault — composed via ../KeyVault
###############################################################
module "kv" {
  count  = var.enable_disk_encryption ? 1 : 0
  source = "../KeyVault"

  # Pass the locally-computed name so the workload-stripping logic that
  # protects the 24-char KV name limit is preserved (palo-obew → obew).
  name = local.kv_name

  resource_group_name = var.resource_group_name
  location            = var.location

  sku_name                    = "standard"
  enable_rbac                 = true
  enabled_for_disk_encryption = true
  purge_protection_enabled    = true
  soft_delete_retention_days  = 90

  # Must be true so the DES UAI can reach KV via the AzureServices bypass to
  # unwrap the disk encryption key. With false + no PE, VM boot fails.
  public_network_access_enabled = true

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.kv_allowed_ips
  }

  tags = local.common_tags
}

###############################################################
# State migration: inline azurerm_key_vault.this → composed via ../KeyVault.
# Existing callers see no Azure-side rename; Terraform migrates state only.
###############################################################
moved {
  from = azurerm_key_vault.this[0]
  to   = module.kv[0].azurerm_key_vault.this
}

###############################################################
# RBAC — Admins -> Key Vault Administrator
#
# Historically this assigned to data.azurerm_client_config.current.object_id
# which caused ping-pong between pipeline SPN and interactive user (forces
# replacement on each apply by a different identity). Replaced by an
# explicit list so pipeline SPN + platform admins are all granted at once.
#
# For prod, point this at an Entra ID group (GRP_AZ_PIM_*) and keep a
# single principal_id in the list (the group OID). This enables PIM JIT.
###############################################################
module "kv_admin" {
  source   = "../RoleAssignment"
  for_each = var.enable_disk_encryption ? toset(var.kv_admin_principal_ids) : toset([])

  scope                = module.kv[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value
  principal_type       = null # mixte users/groupes/SPN — auto-détection assumée
}

# BREAKING (v0.2.73): This moved block was removed because module.kv_admin is
# for_each-keyed by dynamic principal OIDs supplied by the caller. A static
# moved block cannot enumerate caller-controlled keys.
#
# Migration recipe for callers with existing state:
#   terraform state mv \
#     'azurerm_role_assignment.kv_admin' \
#     'module.kv_admin["<oid>"].azurerm_role_assignment.this'
#
# Run one command per principal OID in var.kv_admin_principal_ids.
# See README.md — "v0.2.73 Breaking Changes" for full details.

###############################################################
# Expiration anchors (CKV_AZURE_40 / CKV_AZURE_41)
#
# time_offset freezes its base at the apply that first introduces it (no
# base_rfc3339), so expiration_date = upgrade_time + N days — always a FUTURE
# date and stable across plans. Seeding from the module-level time_static.time
# (frozen at the cluster's ORIGINAL apply) is deliberately AVOIDED: for a
# cluster older than N days that would compute a past/expired date.
###############################################################
resource "time_offset" "des_key_expiry" {
  count = var.enable_disk_encryption ? 1 : 0

  offset_days = var.disk_encryption_key_expiration_days
}

resource "time_offset" "vwan_secret_expiry" {
  count = var.enable_disk_encryption && (var.vwan_bgp_peer_ips != null || var.vwan_bgp_peer_asn != null) ? 1 : 0

  offset_days = var.kv_secret_expiration_days
}

###############################################################
# RSA 2048 Key (auto-rotation)
###############################################################
resource "azurerm_key_vault_key" "des" {
  count = var.enable_disk_encryption ? 1 : 0

  name         = "key-${var.workload}-disk-encryption"
  key_vault_id = module.kv[0].id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]

  # CKV_AZURE_40 — expiration_date set (secure by default).
  # Safe for a disk-encryption key: the rotation_policy below auto-rotates a
  # fresh version 30 days before this expiry and the DES has
  # auto_key_rotation_enabled = true, so Azure moves disks to the new version
  # within 1h and existing disks keep decrypting (Microsoft Learn: envelope
  # encryption re-wraps the DEK; old version stays valid until re-wrap).
  # NOTE (behavioral change): on existing deployments this adds an expiry to a
  # key that previously had none. Per the azurerm schema this is an in-place
  # UPDATE (only *removing* expiration_date forces replacement) so the
  # prevent_destroy guard is respected. Once set, expiration_date cannot be
  # unset (Azure restores the purged key). No ignore_changes: that would block
  # the expiry from ever applying to already-existing keys.
  expiration_date = time_offset.des_key_expiry[0].rfc3339

  rotation_policy {
    expire_after         = "P2Y"
    notify_before_expiry = "P30D"

    automatic {
      time_before_expiry = "P30D"
    }
  }

  depends_on = [module.kv_admin]

  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# User Assigned Identity (for the DES)
###############################################################
resource "azurerm_user_assigned_identity" "des" {
  count = var.enable_disk_encryption ? 1 : 0

  name                = "id-${local.prefix}-${var.workload}-des"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = local.common_tags
}

###############################################################
# RBAC — UAI -> Key Vault Crypto Service Encryption User
###############################################################
module "des_crypto" {
  source = "../RoleAssignment"
  count  = var.enable_disk_encryption ? 1 : 0

  scope                = module.kv[0].id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.des[0].principal_id
}

moved {
  from = azurerm_role_assignment.des_crypto
  to   = module.des_crypto[0].azurerm_role_assignment.this
}

###############################################################
# RBAC — Groups -> Key Vault Secrets User (read secrets)
###############################################################
module "kv_secrets_reader" {
  source   = "../RoleAssignment"
  for_each = var.enable_disk_encryption ? toset(var.kv_secrets_readers) : toset([])

  scope                = module.kv[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
  principal_type       = "Group" # var documentée comme group OIDs uniquement
}

# BREAKING (v0.2.73): This moved block was removed because module.kv_secrets_reader
# is for_each-keyed by dynamic principal OIDs supplied by the caller. A static
# moved block cannot enumerate caller-controlled keys.
#
# Migration recipe for callers with existing state:
#   terraform state mv \
#     'azurerm_role_assignment.kv_secrets_reader' \
#     'module.kv_secrets_reader["<oid>"].azurerm_role_assignment.this'
#
# Run one command per principal OID in var.kv_secrets_readers.
# See README.md — "v0.2.73 Breaking Changes" for full details.

###############################################################
# vwan BGP Peer Config — Key Vault Secrets
# Consumes module.vwan.virtual_hub_router_ips + virtual_hub_router_asns
# (added in vwan v0.2.17). Gated on enable_disk_encryption (KV must exist)
# and the respective var being non-null.
#
# Existing kv_admin role assignments already grant the deployer
# Key Vault Administrator — this includes Secrets Officer permissions,
# so no additional RBAC is required for secret writes.
###############################################################
resource "azurerm_key_vault_secret" "vwan_bgp_peer_ips" {
  count = var.enable_disk_encryption && var.vwan_bgp_peer_ips != null ? 1 : 0

  name         = "${var.workload}-vwan-bgp-peer-ips"
  value        = jsonencode(var.vwan_bgp_peer_ips)
  key_vault_id = module.kv[0].id
  content_type = "application/json"

  # CKV_AZURE_41 — expiration_date set (secure by default). Anchored via a
  # frozen time_offset so the value is stable across plans (no perpetual diff).
  expiration_date = time_offset.vwan_secret_expiry[0].rfc3339

  depends_on = [module.kv, module.kv_admin]
}

resource "azurerm_key_vault_secret" "vwan_bgp_peer_asn" {
  count = var.enable_disk_encryption && var.vwan_bgp_peer_asn != null ? 1 : 0

  name         = "${var.workload}-vwan-bgp-peer-asn"
  value        = tostring(var.vwan_bgp_peer_asn)
  key_vault_id = module.kv[0].id
  content_type = "text/plain"

  # CKV_AZURE_41 — expiration_date set (secure by default). Anchored via a
  # frozen time_offset so the value is stable across plans (no perpetual diff).
  expiration_date = time_offset.vwan_secret_expiry[0].rfc3339

  depends_on = [module.kv, module.kv_admin]
}

###############################################################
# Disk Encryption Set
###############################################################
resource "azurerm_disk_encryption_set" "this" {
  count = var.enable_disk_encryption ? 1 : 0

  name                      = "des-${local.prefix}-${var.workload}"
  location                  = var.location
  resource_group_name       = var.resource_group_name
  key_vault_key_id          = azurerm_key_vault_key.des[0].versionless_id
  auto_key_rotation_enabled = true
  encryption_type           = "EncryptionAtRestWithPlatformAndCustomerKeys"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.des[0].id]
  }

  depends_on = [module.des_crypto]

  tags = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}
