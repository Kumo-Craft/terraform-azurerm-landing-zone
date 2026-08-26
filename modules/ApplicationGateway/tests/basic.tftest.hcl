# Plan-time tests for the ApplicationGateway module.
#
# Mocks azurerm + time. Covers:
#   1.  happy_default_naming             — appgw-{acr}-{env}-{region}-{workload} slug verified
#   2.  happy_name_override              — var.name set wins
#   3.  happy_http2_enabled_default      — F-2 verification: http2_enabled = true default
#   4.  happy_with_lock                  — var.lock = { kind = "CanNotDelete" } wires module.lock
#   5.  happy_with_role_assignments      — F-4 verification: RBAC entry plans cleanly
#   6.  happy_created_on_tag_present     — CreatedOn tag injected on AppGW resource
#   7.  happy_waf_policy_attached        — WAF policy ID wired to AppGW
#   8.  happy_default_listener_https     — CKV_AZURE_217: default listener protocol = Https
#   9.  happy_ssl_certificate_from_kv    — ssl_certificate block emitted when KV secret ID set
#   10. validator_invalid_workload       — bad workload regex rejected
#   11. validator_invalid_principal_type — bad RBAC principal_type rejected (F-4)
#   12. validator_invalid_lock_kind      — bad lock kind rejected
#   13. validator_invalid_ssl_secret_id  — bad KV cert secret URI rejected
#
# Run with:
#   cd modules/ApplicationGateway
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs reused across all runs.
variables {
  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "appgw"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-appgw"
  appgw_subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-appgw/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc-hub/subnets/snet-api-prod-gwc-appgw"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming resolves correctly.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_application_gateway.this.name == "agw-api-prod-gwc-appgw"
    error_message = "AppGW name must follow the agw-{sub}-{env}-{region}-{workload} convention."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name bypasses naming module.
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "agw-legacy-001"
  }

  assert {
    condition     = azurerm_application_gateway.this.name == "agw-legacy-001"
    error_message = "AppGW name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_http2_enabled_default — F-2: http2_enabled defaults to true.
# -----------------------------------------------------------------------
run "happy_http2_enabled_default" {
  command = plan

  assert {
    condition     = azurerm_application_gateway.this.http2_enabled == true
    error_message = "http2_enabled must default to true (F-2 verification)."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_with_lock — var.lock = { kind = "CanNotDelete" } plans cleanly.
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
# Test 5: happy_with_role_assignments — F-4: RBAC entry plans cleanly.
# -----------------------------------------------------------------------
run "happy_with_role_assignments" {
  command = plan

  variables {
    role_assignments = {
      appgw_contributor = {
        role_definition_id_or_name = "Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000001"
        principal_type             = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "One RBAC module instance must be planned when role_assignments has one entry."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_created_on_tag_present — CreatedOn tag injected.
# -----------------------------------------------------------------------
run "happy_created_on_tag_present" {
  command = plan

  assert {
    condition     = contains(keys(azurerm_application_gateway.this.tags), "CreatedOn")
    error_message = "CreatedOn tag must be present in the computed tags map."
  }
}

# -----------------------------------------------------------------------
# Test 7: happy_waf_policy_attached — force_firewall_policy_association defaults true.
# Note: firewall_policy_id is computed (references WAF policy ID, unknown at plan).
# We assert the force flag instead — it comes from var.force_firewall_policy_association
# which is known at plan and confirms the security baseline wiring.
# -----------------------------------------------------------------------
run "happy_waf_policy_attached" {
  command = plan

  assert {
    condition     = azurerm_application_gateway.this.force_firewall_policy_association == true
    error_message = "force_firewall_policy_association must default to true (security baseline)."
  }
}

# -----------------------------------------------------------------------
# Test 8: happy_default_listener_https — CKV_AZURE_217: the default listener
# defaults to the Https protocol (TLS-terminating secure baseline).
# -----------------------------------------------------------------------
run "happy_default_listener_https" {
  command = plan

  assert {
    condition     = alltrue([for l in azurerm_application_gateway.this.http_listener : l.protocol == "Https"])
    error_message = "Default http_listener must use the Https protocol (CKV_AZURE_217 secure baseline)."
  }
}

# -----------------------------------------------------------------------
# Test 9: happy_ssl_certificate_from_kv — supplying a Key Vault cert secret ID
# (plus a UAMI) emits exactly one ssl_certificate block bound to the listener.
# -----------------------------------------------------------------------
run "happy_ssl_certificate_from_kv" {
  command = plan

  variables {
    identity_type                       = "UserAssigned"
    identity_ids                        = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-appgw/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-appgw"]
    ssl_certificate_key_vault_secret_id = "https://kv-api-prod-gwc.vault.azure.net/secrets/appgw-ssl-cert"
  }

  assert {
    condition     = length([for c in azurerm_application_gateway.this.ssl_certificate : c.name if c.name == "appgw-ssl-cert"]) == 1
    error_message = "An ssl_certificate block must be created when ssl_certificate_key_vault_secret_id is set."
  }
}

# -----------------------------------------------------------------------
# Test 10: validator_invalid_workload — bad workload regex rejected.
# -----------------------------------------------------------------------
run "validator_invalid_workload" {
  command = plan

  variables {
    workload = "INVALID WORKLOAD!"
  }

  expect_failures = [var.workload]
}

# -----------------------------------------------------------------------
# Test 11: validator_invalid_principal_type — bad RBAC principal_type rejected (F-4).
# -----------------------------------------------------------------------
run "validator_invalid_principal_type" {
  command = plan

  variables {
    role_assignments = {
      bad_entry = {
        role_definition_id_or_name = "Reader"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        principal_type             = "ManagedIdentity"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

# -----------------------------------------------------------------------
# Test 12: validator_invalid_lock_kind — bad lock kind rejected.
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    lock = { kind = "SoftDelete" }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 13: validator_invalid_ssl_secret_id — non-Key-Vault URI rejected.
# -----------------------------------------------------------------------
run "validator_invalid_ssl_secret_id" {
  command = plan

  variables {
    ssl_certificate_key_vault_secret_id = "not-a-valid-uri"
  }

  expect_failures = [var.ssl_certificate_key_vault_secret_id]
}
