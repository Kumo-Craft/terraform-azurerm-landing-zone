# Plan-time tests for the KubernetesClusterExtension module.
#
# Mocks azurerm only (no time provider — extensions are not taggable).
# Covers:
#   1. happy_minimal                          — name + cluster_id + extension_type only
#   2. happy_with_namespaces                  — release_namespace + target_namespace
#   3. happy_with_protected_settings          — configuration_protected_settings passed
#   4. happy_with_plan                        — plan block wired correctly
#   5. happy_with_lock                        — var.lock = { kind = "CanNotDelete" }
#   6. happy_no_lock                          — lock module has 0 entries when var.lock = null
#   7. happy_with_role_assignments_self_scope — scope=null → default to extension resource
#   8. happy_with_role_assignments_ext_scope  — scope set to external ACR resource ID
#   9. validator_name                         — invalid name → expect_failures
#  10. validator_cluster_id_arc_rejected      — Arc resource ID → expect_failures
#  11. validator_principal_type               — invalid principal_type → expect_failures
#  12. validator_lock_kind                    — invalid lock kind → expect_failures
#
# Run with:
#   cd modules/KubernetesClusterExtension
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

# Shared required inputs reused across runs.
variables {
  name           = "flux"
  cluster_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-aks/providers/Microsoft.ContainerService/managedClusters/aks-api-prod-gwc"
  extension_type = "microsoft.flux"
}

# -----------------------------------------------------------------------
# Test 1: happy_minimal — minimal required vars only.
# -----------------------------------------------------------------------
run "happy_minimal" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster_extension.this.name == "flux"
    error_message = "Extension name must match var.name."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_extension.this.extension_type == "microsoft.flux"
    error_message = "Extension type must match var.extension_type."
  }

  assert {
    condition     = length(module.lock.ids) == 0
    error_message = "No lock must be planned when var.lock is null."
  }

  assert {
    condition     = length(module.role_assignments) == 0
    error_message = "No role assignments must be planned when var.role_assignments is empty."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_with_namespaces — release_namespace + target_namespace.
# -----------------------------------------------------------------------
run "happy_with_namespaces" {
  command = plan

  variables {
    release_namespace = "flux-system"
    target_namespace  = null
  }

  assert {
    condition     = azurerm_kubernetes_cluster_extension.this.release_namespace == "flux-system"
    error_message = "release_namespace must be passed through to the resource."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_with_protected_settings — configuration_protected_settings passed.
# -----------------------------------------------------------------------
run "happy_with_protected_settings" {
  command = plan

  variables {
    configuration_protected_settings = {
      "sshPrivateKey" = "dGVzdC1rZXk="
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster_extension.this.name == "flux"
    error_message = "Extension must plan successfully with protected settings."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_plan — plan block wired correctly.
# -----------------------------------------------------------------------
run "happy_with_plan" {
  command = plan

  variables {
    extension_type = "Microsoft.AzureDefender.Kubernetes"
    plan = {
      name      = "azure-defender-k8s"
      product   = "azure-defender-k8s"
      publisher = "microsoft"
    }
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_extension.this.plan) == 1
    error_message = "plan block must be present when var.plan is set."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_with_lock — var.lock = { kind = "CanNotDelete" }.
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
# Test 6: happy_no_lock — module.lock.ids is empty when var.lock = null.
# -----------------------------------------------------------------------
run "happy_no_lock" {
  command = plan

  variables {
    lock = null
  }

  assert {
    condition     = length(module.lock.ids) == 0
    error_message = "Lock module must plan 0 entries when var.lock is null."
  }
}

# -----------------------------------------------------------------------
# Test 7: happy_with_role_assignments_self_scope — scope=null uses extension id.
# -----------------------------------------------------------------------
run "happy_with_role_assignments_self_scope" {
  command = plan

  variables {
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        scope                      = null
      }
    }
  }

  assert {
    condition     = length(module.role_assignments) == 1
    error_message = "role_assignments module must be instantiated once per entry."
  }
}

# -----------------------------------------------------------------------
# Test 8: happy_with_role_assignments_ext_scope — scope set to external ACR id.
# -----------------------------------------------------------------------
run "happy_with_role_assignments_ext_scope" {
  command = plan

  variables {
    role_assignments = {
      acr_pull = {
        role_definition_id_or_name = "AcrPull"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-acr/providers/Microsoft.ContainerRegistry/registries/acrapiprodgwc"
      }
    }
  }

  assert {
    condition     = length(module.role_assignments) == 1
    error_message = "role_assignments module must be instantiated for external scope entry."
  }
}

# -----------------------------------------------------------------------
# Test 9: validator_name — invalid name (starts with digit) → expect_failures.
# -----------------------------------------------------------------------
run "validator_name" {
  command = plan

  variables {
    name = "1invalid-name"
  }

  expect_failures = [var.name]
}

# -----------------------------------------------------------------------
# Test 10: validator_cluster_id_arc_rejected — Arc resource ID → expect_failures.
# -----------------------------------------------------------------------
run "validator_cluster_id_arc_rejected" {
  command = plan

  variables {
    cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-arc/providers/Microsoft.Kubernetes/connectedClusters/arc-cluster"
  }

  expect_failures = [var.cluster_id]
}

# -----------------------------------------------------------------------
# Test 11: validator_principal_type — invalid principal_type → expect_failures.
# -----------------------------------------------------------------------
run "validator_principal_type" {
  command = plan

  variables {
    role_assignments = {
      bad_type = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "InvalidType"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

# -----------------------------------------------------------------------
# Test 12: validator_lock_kind — invalid lock kind → expect_failures.
# -----------------------------------------------------------------------
run "validator_lock_kind" {
  command = plan

  variables {
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}
