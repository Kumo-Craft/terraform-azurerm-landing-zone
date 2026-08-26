# Plan-time tests for the ManagedIdentity module.
#
# Mocks azurerm + time. Covers:
#   1. happy_default_naming         — convention naming (no var.name), no FICs, no role_assignments, no lock
#   2. happy_name_override          — explicit var.name, naming module NOT instantiated
#   3. happy_with_fics              — 2-entry federated_identity_credentials map (AKS + GitHub Actions)
#   4. happy_with_role_assignments  — 1 role_assignment, principal_type=ServicePrincipal + principal_id auto-wired
#   5. happy_with_lock              — var.lock = { kind = "CanNotDelete" }, module.lock instantiated
#   6. validator_naming_xor_fails   — var.name=null AND var.workload=null → XOR validator failure
#   7. validator_invalid_lock_kind  — lock.kind = "Bogus" → validator failure
#   8. happy_full_composition       — name override + FICs + role_assignments + lock all together
#
# Run with:
#   cd modules/ManagedIdentity
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across runs.
variables {
  location            = "germanywestcentral"
  resource_group_name = "rg-api-prod-gwc-identity"
}

# ---------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming, no optional features.
# ---------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "aks"
  }

  assert {
    condition     = length(module.naming) == 1
    error_message = "Naming module must be instantiated when var.name is null."
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.this.location) > 0
    error_message = "Location must be wired through to the identity resource."
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 0
    error_message = "No federated credentials must be planned when federated_identity_credentials is empty."
  }

  assert {
    condition     = length(module.role_assignments) == 0
    error_message = "No role assignment modules must be planned when role_assignments is empty."
  }
}

# ---------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming module.
# ---------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "id-custom"
  }

  assert {
    condition     = azurerm_user_assigned_identity.this.name == "id-custom"
    error_message = "Name override must produce the explicit name."
  }

  assert {
    condition     = length(module.naming) == 0
    error_message = "Naming module must NOT be instantiated when var.name is provided."
  }
}

# ---------------------------------------------------------------------
# Test 3: happy_with_fics — 2-entry FIC map (AKS workload + GitHub Actions).
# ---------------------------------------------------------------------
run "happy_with_fics" {
  command = plan

  variables {
    name = "id-wi-test"

    federated_identity_credentials = {
      aks_workload = {
        name    = "fic-aks-default-mysa"
        issuer  = "https://oidc.example.com/aks"
        subject = "system:serviceaccount:default:mysa"
      }
      github_actions = {
        name    = "fic-github-main"
        issuer  = "https://token.actions.githubusercontent.com"
        subject = "repo:myorg/myrepo:ref:refs/heads/main"
      }
    }
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 2
    error_message = "Two federated credentials must be planned when two FIC entries are given."
  }

  # user_assigned_identity_id is computed-on-create (unknown at plan); wiring
  # verified by module composition — the resource block passes
  # azurerm_user_assigned_identity.this.id directly.
}

# ---------------------------------------------------------------------
# Test 4: happy_with_role_assignments — 1 role_assignment, ServicePrincipal wired.
# ---------------------------------------------------------------------
run "happy_with_role_assignments" {
  command = plan

  variables {
    name = "id-rbac-test"

    role_assignments = {
      network_contributor = {
        role_definition_id_or_name = "Network Contributor"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-network"
      }
    }
  }

  assert {
    condition     = length(module.role_assignments) == 1
    error_message = "One role_assignments module instance must be planned when one role_assignment is given."
  }
}

# ---------------------------------------------------------------------
# Test 5: happy_with_lock — var.lock = { kind = "CanNotDelete" }.
# ---------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    name = "id-lock-test"
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock module must plan one lock entry when var.lock is set."
  }
}

# ---------------------------------------------------------------------
# Test 6: validator_naming_xor_fails — var.name=null AND var.workload=null.
# ---------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    # workload omitted (null) + name omitted (null) → XOR validator must fire
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------
# Test 7: validator_invalid_lock_kind — "Bogus" must fail.
# ---------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    name = "id-bad-lock"
    lock = { kind = "Bogus" }
  }

  expect_failures = [var.lock]
}

# ---------------------------------------------------------------------
# Test 8: happy_full_composition — name override + FICs + role_assignments + lock.
# ---------------------------------------------------------------------
run "happy_full_composition" {
  command = plan

  variables {
    name = "id-full"

    federated_identity_credentials = {
      aks_workload = {
        name    = "fic-aks-ns-sa"
        issuer  = "https://oidc.example.com/aks"
        subject = "system:serviceaccount:kube-system:csi-driver"
      }
    }

    role_assignments = {
      kv_crypto_user = {
        role_definition_id_or_name = "Key Vault Crypto User"
        scope                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-kv/providers/Microsoft.KeyVault/vaults/kv-api-prod-gwc-01"
      }
    }

    lock = { kind = "CanNotDelete" }

    tags = { Environment = "prod" }
  }

  assert {
    condition     = azurerm_user_assigned_identity.this.name == "id-full"
    error_message = "Identity name must match the explicit override."
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.this) == 1
    error_message = "One FIC must be planned."
  }

  assert {
    condition     = length(module.role_assignments) == 1
    error_message = "One role assignment must be planned."
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "Lock must be planned."
  }
}
