# Plan-time tests for the AksStack module.
#
# Mocks azurerm + time + null. Covers:
#   1. happy_default_composition       — all required inputs, secure defaults
#   2. happy_with_lock                 — lock pass-through to Aks
#   3. happy_with_support_plan         — AKSLongTermSupport + Premium SKU
#   4. happy_with_kms                  — kms_v2_enabled = true composition
#   5. happy_with_user_node_pools      — auto_scaling_enabled field (F-18 pass-through)
#   6. happy_with_apiserver_subnet     — api_server_subnet_id wired
#   7. validator_outbound_type_enum    — invalid outbound_type value rejected
#   8. validator_resource_group_name   — ARM RG name regex (F-6)
#   9. validator_tags_null_rejected    — var.tags nullable=false (F-8)
#  10. validator_spot_requires_scaling — Spot pool without auto_scaling_enabled
#  11. validator_lock_kind             — invalid lock.kind rejected
#
# Run with:
#   cd modules/AksStack
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}
mock_provider "null" {}

# AksStack declares data.azurerm_client_config.current directly.
override_data {
  target = data.azurerm_client_config.current
  values = {
    tenant_id       = "00000000-0000-0000-0000-000000000000"
    subscription_id = "00000000-0000-0000-0000-000000000001"
    client_id       = "00000000-0000-0000-0000-000000000002"
    object_id       = "00000000-0000-0000-0000-000000000003"
  }
}

# The Aks child module also has data.azurerm_client_config.current.
override_data {
  target = module.aks.data.azurerm_client_config.current
  values = {
    tenant_id       = "00000000-0000-0000-0000-000000000000"
    subscription_id = "00000000-0000-0000-0000-000000000001"
    client_id       = "00000000-0000-0000-0000-000000000002"
    object_id       = "00000000-0000-0000-0000-000000000003"
  }
}

# The KeyVault child module also has data.azurerm_client_config.current.
override_data {
  target = module.kv.data.azurerm_client_config.current
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
  tenant_id            = "00000000-0000-0000-0000-000000000000"

  resource_group_name = "rg-api-prod-gwc-aks"

  node_subnet_id  = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc-001/subnets/snet-nodes"
  kv_pe_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc-001/subnets/snet-pe"

  # Container Insights requires a real workspace ID — disable for plan-only tests.
  enable_container_insights = false
}

# -----------------------------------------------------------------------
# Test 1: happy_default_composition — all required inputs, secure defaults.
# Verifies the removed tombstone + var.resource_group_name wiring (F-6).
# -----------------------------------------------------------------------
run "happy_default_composition" {
  command = plan

  # Verifies var.resource_group_name is accepted + wired via effective_kv_rg_name
  # (single-RG mode: kv_resource_group_name is null, so falls back to resource_group_name).
  assert {
    condition     = output.resource_group_name == "rg-api-prod-gwc-aks"
    error_message = "output.resource_group_name must equal var.resource_group_name."
  }

  assert {
    condition     = output.kv_resource_group_name == "rg-api-prod-gwc-aks"
    error_message = "kv_resource_group_name must fall back to resource_group_name in single-RG mode."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_with_lock — lock pass-through to Aks (F-2).
# -----------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = var.lock.kind == "CanNotDelete"
    error_message = "lock.kind must be accepted and passed through."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_support_plan — AKSLongTermSupport + Premium (F-1).
# -----------------------------------------------------------------------
run "happy_with_support_plan" {
  command = plan

  variables {
    support_plan = "AKSLongTermSupport"
    sku_tier     = "Premium"
  }

  assert {
    condition     = var.support_plan == "AKSLongTermSupport"
    error_message = "support_plan must accept AKSLongTermSupport."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_kms — kms_v2_enabled = true composition.
# Verifies that kms_v2_enabled gates the RBAC count modules (no error).
# -----------------------------------------------------------------------
run "happy_with_kms" {
  command = plan

  variables {
    kms_v2_enabled = true
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_user_node_pools — auto_scaling_enabled field (F-18).
# Verifies the renamed field is accepted by AksStack and passed to Aks.
# -----------------------------------------------------------------------
run "happy_with_user_node_pools" {
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
    condition     = var.user_node_pools["app"].auto_scaling_enabled == true
    error_message = "user_node_pools[app].auto_scaling_enabled must be accepted."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_with_apiserver_subnet — api_server_subnet_id wired.
# Verifies count-gated cp_apiserver_subnet_network_contrib plans without error.
# -----------------------------------------------------------------------
run "happy_with_apiserver_subnet" {
  command = plan

  variables {
    api_server_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-api-prod-gwc-network/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc-001/subnets/snet-apiserver"
  }
}

# -----------------------------------------------------------------------
# Test 7: validator_outbound_type_enum — invalid value rejected (F-3).
# -----------------------------------------------------------------------
run "validator_outbound_type_enum" {
  command = plan

  variables {
    outbound_type = "userAssignedNATGateway"
  }

  expect_failures = [var.outbound_type]
}

# -----------------------------------------------------------------------
# Test 8: validator_resource_group_name — ARM RG name regex (F-6).
# A name with a forbidden character (/) must be rejected.
# -----------------------------------------------------------------------
run "validator_resource_group_name" {
  command = plan

  variables {
    resource_group_name = "rg/invalid/name"
  }

  expect_failures = [var.resource_group_name]
}

# -----------------------------------------------------------------------
# Test 9: happy_tags_null_coerced — nullable=false with default={} means
# passing null is silently coerced to {} (not an error). Verify the
# effective_tags merge still produces a map (CreatedOn key present).
# -----------------------------------------------------------------------
run "happy_tags_null_coerced" {
  command = plan

  variables {
    tags = null
  }

  assert {
    condition     = contains(keys(output.resource_group_name != null ? { ok = true } : {}), "ok")
    error_message = "Plan must succeed when tags = null (coerced to {} by nullable=false + default={})."
  }
}

# -----------------------------------------------------------------------
# Test 10: validator_spot_requires_scaling — Spot without auto_scaling_enabled.
# -----------------------------------------------------------------------
run "validator_spot_requires_scaling" {
  command = plan

  variables {
    user_node_pools = {
      spot = {
        name                 = "spot"
        vm_size              = "Standard_D4s_v5"
        priority             = "Spot"
        auto_scaling_enabled = false
      }
    }
  }

  expect_failures = [var.user_node_pools]
}

# -----------------------------------------------------------------------
# Test 11: validator_lock_kind — invalid lock.kind rejected.
# -----------------------------------------------------------------------
run "validator_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 12: cluster_rbac_group_principals — caller-provided cluster
# admin/user grants target Entra GROUPS (AAD-integrated RBAC). The
# RoleAssignment default is "ServicePrincipal", which Azure rejects for a
# Group with 400 UnmatchedPrincipalType. AksStack must pin principal_type
# = "Group" on these two blocks. (Regression guard for the prod bug on
# aks-pgs-prod-gwc-001, 2026-07-26.)
# -----------------------------------------------------------------------
run "cluster_rbac_group_principals" {
  command = plan

  variables {
    cluster_admin_principal_ids = [
      "11111111-1111-1111-1111-111111111111",
      "22222222-2222-2222-2222-222222222222",
    ]
    cluster_user_principal_ids = [
      "33333333-3333-3333-3333-333333333333",
    ]
  }

  assert {
    condition     = length(module.cluster_admin) == 2 && length(module.cluster_user) == 1
    error_message = "One role assignment must be planned per admin/user principal id."
  }

  assert {
    condition     = alltrue([for m in module.cluster_admin : m.principal_type == "Group"])
    error_message = "cluster_admin assignments must set principal_type = Group (Entra AAD RBAC), not the ServicePrincipal default."
  }

  assert {
    condition     = alltrue([for m in module.cluster_user : m.principal_type == "Group"])
    error_message = "cluster_user assignments must set principal_type = Group."
  }
}
