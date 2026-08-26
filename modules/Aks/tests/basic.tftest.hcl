# Plan-time tests for the Aks module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming       — convention naming, all secure defaults
#   2. happy_name_override        — explicit var.name (XOR escape hatch)
#   3. happy_with_lock            — var.lock = { kind = "CanNotDelete" }
#   4. happy_lts_premium          — AKSLongTermSupport + Premium SKU
#   5. validator_lts_requires_premium — LTS + Standard → F-7 precondition
#   6. validator_invalid_support_plan — bad enum → F-7 validator
#   7. validator_kms_missing_kv_id    — kms_key_id + api_server_subnet_id but no kms_key_vault_id → F-13
#   8. validator_invalid_lock_kind    — lock.kind = "Bogus" → F-9 validator
#
# Run with:
#   cd modules/Aks
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Override the data source used inside the module (and inside ../Naming child).
# mock_provider returns a non-UUID tenant_id which breaks azurerm validators.
override_data {
  target = data.azurerm_client_config.current
  values = {
    tenant_id       = "00000000-0000-0000-0000-000000000000"
    subscription_id = "00000000-0000-0000-0000-000000000001"
    client_id       = "00000000-0000-0000-0000-000000000002"
    object_id       = "00000000-0000-0000-0000-000000000003"
  }
}

# Shared required inputs reused across all runs.
variables {
  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "001"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-aks"

  node_subnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-nodes"
  cluster_identity_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-api-prod-gwc-aks-cp"
  kubelet_identity_id        = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-api-prod-gwc-aks-kubelet"
  kubelet_identity_client_id = "00000000-0000-0000-0000-000000000004"
  kubelet_identity_object_id = "00000000-0000-0000-0000-000000000005"
  tenant_id                  = "00000000-0000-0000-0000-000000000000"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, all secure defaults.
# Verifies local_account_disabled = true is hardcoded (F-3).
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.name == "aks-api-prod-gwc-001"
    error_message = "Cluster name must follow the aks-{sub}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled == true
    error_message = "local_account_disabled must be hardcoded true (F-3 SECURITY)."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.support_plan == "KubernetesOfficial"
    error_message = "Default support_plan must be KubernetesOfficial."
  }

  # CKV_AZURE_227 — host encryption is exposed but kept OPT-IN (default false),
  # because enabling requires Microsoft.Compute/EncryptionAtHost registered +
  # supported VM sizes/regions. Secure path covered in happy_host_encryption_on.
  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].host_encryption_enabled == false
    error_message = "system_pool_host_encryption_enabled must default to false (opt-in)."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name (XOR escape hatch).
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "aks-custom-override"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.name == "aks-custom-override"
    error_message = "Cluster name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_lock — var.lock = { kind = "CanNotDelete" } (F-9).
# -----------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan 1 lock entry when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_lts_premium — AKSLongTermSupport + Premium SKU (F-7).
# -----------------------------------------------------------------------
run "happy_lts_premium" {
  command = plan

  variables {
    support_plan = "AKSLongTermSupport"
    sku_tier     = "Premium"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.support_plan == "AKSLongTermSupport"
    error_message = "support_plan must be AKSLongTermSupport when explicitly set with Premium SKU."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Premium"
    error_message = "sku_tier must be Premium when AKSLongTermSupport is selected."
  }
}

# -----------------------------------------------------------------------
# Test 5: validator_lts_requires_premium — LTS + Standard → F-7 precondition.
# -----------------------------------------------------------------------
run "validator_lts_requires_premium" {
  command = plan

  variables {
    support_plan = "AKSLongTermSupport"
    sku_tier     = "Standard"
  }

  expect_failures = [azurerm_kubernetes_cluster.this]
}

# -----------------------------------------------------------------------
# Test 6: validator_invalid_support_plan — bad enum → F-7 validator.
# -----------------------------------------------------------------------
run "validator_invalid_support_plan" {
  command = plan

  variables {
    support_plan = "Bogus"
  }

  expect_failures = [var.support_plan]
}

# -----------------------------------------------------------------------
# Test 7: validator_kms_missing_kv_id — kms_key_id + api_server_subnet_id
# without kms_key_vault_id → F-13 cross-var validation failure.
# -----------------------------------------------------------------------
run "validator_kms_missing_kv_id" {
  command = plan

  variables {
    kms_key_id           = "https://kv-api-prod-gwc-kms.vault.azure.net/keys/aks-kms"
    api_server_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-apiserver"
    kms_key_vault_id     = null
  }

  expect_failures = [var.kms_key_vault_id]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_lock_kind — lock.kind = "Bogus" → F-9 validator.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 9: validator_name_too_long — var.name > 54 chars → F-6 validator.
# -----------------------------------------------------------------------
run "validator_name_too_long" {
  command = plan

  variables {
    # 55 characters — exceeds the 54-char dns_prefix limit
    name = "aks-this-name-is-way-too-long-for-a-kubernetes-cluster-x"
  }

  expect_failures = [var.name]
}

# -----------------------------------------------------------------------
# Test 10: validator_name_at_limit — var.name exactly 54 chars → OK (F-6).
# -----------------------------------------------------------------------
run "validator_name_at_limit" {
  command = plan

  variables {
    # exactly 54 characters — must pass
    name = "aks-this-name-is-exactly-54-chars-long-for-aks-cluster"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.name) == 54
    error_message = "54-character name must be accepted by the validator."
  }
}

# -----------------------------------------------------------------------
# Test 11: happy_user_pool_auto_scaling — auto_scaling_enabled field (F-18).
# Verifies the renamed field is wired correctly and the pool plans without error.
# -----------------------------------------------------------------------
run "happy_user_pool_auto_scaling" {
  command = plan

  variables {
    user_node_pools = {
      app = {
        name                 = "app"
        vm_size              = "Standard_D4s_v5"
        min_count            = 2
        max_count            = 10
        auto_scaling_enabled = true
      }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["app"].auto_scaling_enabled == true
    error_message = "user_node_pools[app].auto_scaling_enabled must wire through to the resource."
  }

  # CKV_AZURE_227 — additional node pools default host encryption OFF (opt-in).
  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["app"].host_encryption_enabled == false
    error_message = "user_node_pools[*].host_encryption_enabled must default to false (opt-in)."
  }
}

# -----------------------------------------------------------------------
# Test: happy_host_encryption_on — secure path coverage for CKV_AZURE_227.
# Opting host encryption ON (system pool + an additional pool) must wire
# host_encryption_enabled = true onto both resources.
# -----------------------------------------------------------------------
run "happy_host_encryption_on" {
  command = plan

  variables {
    system_pool_host_encryption_enabled = true
    user_node_pools = {
      app = {
        name                    = "app"
        vm_size                 = "Standard_D4s_v5"
        min_count               = 2
        max_count               = 10
        auto_scaling_enabled    = true
        host_encryption_enabled = true
      }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].host_encryption_enabled == true
    error_message = "system_pool_host_encryption_enabled = true must wire host_encryption_enabled onto the system pool (CKV_AZURE_227 secure path)."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["app"].host_encryption_enabled == true
    error_message = "user_node_pools[app].host_encryption_enabled = true must wire onto the pool (CKV_AZURE_227 secure path)."
  }
}

# -----------------------------------------------------------------------
# Test 12: validator_spot_requires_autoscaling — Spot pool without
# auto_scaling_enabled = true → validator (F-18 Spot validator updated).
# -----------------------------------------------------------------------
run "validator_spot_requires_autoscaling" {
  command = plan

  variables {
    user_node_pools = {
      spot = {
        name                 = "spot"
        vm_size              = "Standard_D4s_v5"
        min_count            = 1
        max_count            = 5
        priority             = "Spot"
        auto_scaling_enabled = false
      }
    }
  }

  expect_failures = [var.user_node_pools]
}

# -----------------------------------------------------------------------
# Test 13: happy_monitor_metrics_config — non-null var.monitor_metrics
# with annotations_allowed set → block emitted (F-4).
# -----------------------------------------------------------------------
run "happy_monitor_metrics_config" {
  command = plan

  variables {
    monitor_metrics = {
      annotations_allowed = "kubernetes.io/app,kubernetes.io/component"
      labels_allowed      = "app,tier"
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.monitor_metrics[0].annotations_allowed == "kubernetes.io/app,kubernetes.io/component"
    error_message = "monitor_metrics.annotations_allowed must be wired through."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.monitor_metrics[0].labels_allowed == "app,tier"
    error_message = "monitor_metrics.labels_allowed must be wired through."
  }
}

# -----------------------------------------------------------------------
# Test 14: happy_monitor_metrics_null — null var.monitor_metrics → block
# omitted entirely (F-4).
# -----------------------------------------------------------------------
run "happy_monitor_metrics_null" {
  command = plan

  variables {
    monitor_metrics = null
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.monitor_metrics) == 0
    error_message = "monitor_metrics block must be omitted when var.monitor_metrics = null."
  }
}

# -----------------------------------------------------------------------
# Test 15: happy_disk_encryption_set — var.disk_encryption_set_id wired
# through to the cluster (CKV_AZURE_117 BYOK escape hatch).
# -----------------------------------------------------------------------
run "happy_disk_encryption_set" {
  command = plan

  variables {
    disk_encryption_set_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.Compute/diskEncryptionSets/des-api-prod-gwc-aks"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.disk_encryption_set_id == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.Compute/diskEncryptionSets/des-api-prod-gwc-aks"
    error_message = "var.disk_encryption_set_id must wire through to the cluster (CKV_AZURE_117)."
  }
}

# -----------------------------------------------------------------------
# Test 16: happy_disk_encryption_set_default — null default → no CMK DES.
# -----------------------------------------------------------------------
run "happy_disk_encryption_set_default" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.disk_encryption_set_id == null
    error_message = "disk_encryption_set_id must default to null (platform-managed keys)."
  }
}

# -----------------------------------------------------------------------
# Test 17: federated_login_supports_wif — the shared az login helper used by
# the 3 post-create null_resource provisioners must support Workload Identity
# Federation (OIDC): pick `--federated-token $env:ARM_OIDC_TOKEN` when
# ARM_OIDC_TOKEN is present, and still fall back to `--password
# $env:ARM_CLIENT_SECRET` for classic SPN auth. Asserted on the factored
# local so the 3 copies can never diverge.
# -----------------------------------------------------------------------
run "federated_login_supports_wif" {
  command = plan

  # WIF branch present (bug fix: OIDC pipelines have no ARM_CLIENT_SECRET).
  assert {
    condition     = strcontains(local.az_federated_login, "--federated-token $env:ARM_OIDC_TOKEN")
    error_message = "az login must use --federated-token $env:ARM_OIDC_TOKEN for WIF/OIDC runners."
  }

  # WIF branch is gated on ARM_OIDC_TOKEN being set.
  assert {
    condition     = strcontains(local.az_federated_login, "if ($env:ARM_OIDC_TOKEN)")
    error_message = "The federated login must be selected only when ARM_OIDC_TOKEN is set."
  }

  # Classic secret auth still works (no regression for existing consumers).
  assert {
    condition     = strcontains(local.az_federated_login, "--password $env:ARM_CLIENT_SECRET")
    error_message = "az login must still fall back to --password $env:ARM_CLIENT_SECRET."
  }

  # Guard accepts either credential form (not ARM_CLIENT_SECRET-only anymore).
  assert {
    condition     = strcontains(local.az_federated_login, "-not $env:ARM_CLIENT_SECRET -and -not $env:ARM_OIDC_TOKEN")
    error_message = "The guard must accept ARM_CLIENT_SECRET OR ARM_OIDC_TOKEN."
  }
}

# -----------------------------------------------------------------------
# Test 18: local_exec_uses_pwsh — the 3 post-create local-exec provisioners
# must use `pwsh` (PowerShell 7+, cross-platform) and NOT `powershell`
# (Windows-only), so they run on Linux pipeline agents (bug: "powershell":
# executable file not found in $PATH on Ubuntu Managed DevOps Pool agents).
# Asserted on the factored local so the 3 provisioners can never diverge.
# -----------------------------------------------------------------------
run "local_exec_uses_pwsh" {
  command = plan

  assert {
    condition     = local.local_exec_interpreter[0] == "pwsh"
    error_message = "local-exec interpreter must be pwsh (cross-platform), not powershell (Windows-only)."
  }

  assert {
    condition     = local.local_exec_interpreter == ["pwsh", "-NoProfile", "-Command"]
    error_message = "local-exec interpreter must be exactly [pwsh, -NoProfile, -Command]."
  }
}

# -----------------------------------------------------------------------
# Test 19: upgrade_override_omitted_by_default — greenfield-safe. The block
# must NOT be emitted by default, otherwise azurerm sends effectiveUntil=""
# and the AKS API rejects cluster CREATION (400 UnmarshalError).
# -----------------------------------------------------------------------
run "upgrade_override_omitted_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.upgrade_override) == 0
    error_message = "upgrade_override block must be omitted by default so new clusters can be created."
  }
}

# -----------------------------------------------------------------------
# Test 20: upgrade_override_enabled — opt-in for existing clusters that
# already carry upgradeSettings.overrideSettings (cannot be unset). The
# block is emitted and force_upgrade_enabled / effective_until wire through.
# -----------------------------------------------------------------------
run "upgrade_override_enabled" {
  command = plan

  variables {
    upgrade_override_enabled         = true
    upgrade_override_force_upgrade   = true
    upgrade_override_effective_until = "2027-01-01T00:00:00Z"
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.upgrade_override) == 1
    error_message = "upgrade_override block must be emitted when upgrade_override_enabled = true."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.upgrade_override[0].force_upgrade_enabled == true
    error_message = "upgrade_override_force_upgrade must wire force_upgrade_enabled."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.upgrade_override[0].effective_until == "2027-01-01T00:00:00Z"
    error_message = "upgrade_override_effective_until must wire effective_until."
  }
}

# -----------------------------------------------------------------------
# Test 21: upgrade_override_enabled_default_until_null — when enabled but no
# effective_until is given, the block is emitted with effective_until unset.
# -----------------------------------------------------------------------
run "upgrade_override_enabled_default_until_null" {
  command = plan

  variables {
    upgrade_override_enabled = true
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.upgrade_override) == 1
    error_message = "upgrade_override block must be emitted when upgrade_override_enabled = true."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.upgrade_override[0].force_upgrade_enabled == false
    error_message = "force_upgrade_enabled must default to false when enabled without force."
  }
}
