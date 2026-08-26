# Plan-time tests for the TlsSelfSignedCert module.
#
# Mocks azurerm + tls. Covers:
#   1.  happy_default_naming              — slug computed when naming vars set, cert_name null
#   2.  happy_cert_name_override          — var.cert_name bypasses naming module
#   3.  happy_min_key_size                — RSA 2048 plans cleanly
#   4.  happy_max_validity                — validity_days = 3650 plans cleanly
#   5.  validator_cert_name_xor_naming    — both null → fails (cross-var)
#   6.  validator_invalid_key_size        — key_size = 1024 rejected
#   7.  validator_invalid_validity_low    — validity_days = 0 rejected
#   8.  validator_invalid_validity_high   — validity_days = 3651 rejected
#   9.  validator_invalid_cert_name_regex — cert_name with special char rejected
#   10. validator_invalid_subscription_acronym — too long → fails
#   11. happy_legacy_5year_validity       — explicit validity_days = 1825 accepted (F-6 SOFT BREAKING migration)
#   12. happy_early_renewal_set           — non-zero early_renewal_hours accepted (F-7)
#   13. happy_with_lock                   — var.lock = CanNotDelete plans cleanly (F-9)
#   14. validator_invalid_lock_kind       — invalid lock kind rejected (F-9)
#   15. happy_with_role_assignments       — single role assignment entry plans cleanly (F-10)
#   16. validator_invalid_principal_type  — invalid principal_type rejected (F-10)
#
# Run with:
#   cd modules/TlsSelfSignedCert
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "tls" {}

# Shared required inputs reused across all runs.
variables {
  common_name  = "*.internal.example.com"
  key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-mgm-prod-gwc-security/providers/Microsoft.KeyVault/vaults/kv-mgm-prod-gwc-sec"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — slug computed when all naming vars set.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ingress"
    location             = "germanywestcentral"
  }

  assert {
    condition     = azurerm_key_vault_certificate.this.name == "cert-mgm-nprd-gwc-ingress"
    error_message = "Cert name must follow the cert-{acr}-{env}-{region}-{workload} convention."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_cert_name_override — var.cert_name bypasses naming.
# -----------------------------------------------------------------------
run "happy_cert_name_override" {
  command = plan

  variables {
    cert_name = "lb-internal-mtls"
  }

  assert {
    condition     = azurerm_key_vault_certificate.this.name == "lb-internal-mtls"
    error_message = "Cert name must match the explicit var.cert_name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_min_key_size — RSA 2048 plans cleanly.
# -----------------------------------------------------------------------
run "happy_min_key_size" {
  command = plan

  variables {
    cert_name = "test-cert-2048"
    key_size  = 2048
  }

  assert {
    condition     = azurerm_key_vault_certificate.this.certificate_policy[0].key_properties[0].key_size == 2048
    error_message = "key_size 2048 must be wired through to the certificate_policy."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_max_validity — validity_days = 3650 plans cleanly.
# -----------------------------------------------------------------------
run "happy_max_validity" {
  command = plan

  variables {
    cert_name     = "test-cert-10yr"
    validity_days = 3650
  }

  assert {
    condition     = tls_self_signed_cert.this.validity_period_hours == 3650 * 24
    error_message = "validity_period_hours must be validity_days * 24."
  }
}

# -----------------------------------------------------------------------
# Test 5: validator_cert_name_xor_naming — both null fails (cross-var).
# -----------------------------------------------------------------------
run "validator_cert_name_xor_naming" {
  command = plan

  variables {
    cert_name            = null
    subscription_acronym = null
    environment          = null
    region_code          = null
    workload             = null
  }

  expect_failures = [var.cert_name]
}

# -----------------------------------------------------------------------
# Test 6: validator_invalid_key_size — key_size = 1024 rejected.
# -----------------------------------------------------------------------
run "validator_invalid_key_size" {
  command = plan

  variables {
    cert_name = "test-cert"
    key_size  = 1024
  }

  expect_failures = [var.key_size]
}

# -----------------------------------------------------------------------
# Test 7: validator_invalid_validity_low — validity_days = 0 rejected.
# -----------------------------------------------------------------------
run "validator_invalid_validity_low" {
  command = plan

  variables {
    cert_name     = "test-cert"
    validity_days = 0
  }

  expect_failures = [var.validity_days]
}

# -----------------------------------------------------------------------
# Test 8: validator_invalid_validity_high — validity_days = 3651 rejected.
# -----------------------------------------------------------------------
run "validator_invalid_validity_high" {
  command = plan

  variables {
    cert_name     = "test-cert"
    validity_days = 3651
  }

  expect_failures = [var.validity_days]
}

# -----------------------------------------------------------------------
# Test 9: validator_invalid_cert_name_regex — special char rejected.
# -----------------------------------------------------------------------
run "validator_invalid_cert_name_regex" {
  command = plan

  variables {
    cert_name = "lb_internal_mtls"
  }

  expect_failures = [var.cert_name]
}

# -----------------------------------------------------------------------
# Test 10: validator_invalid_subscription_acronym — too long fails.
# -----------------------------------------------------------------------
run "validator_invalid_subscription_acronym" {
  command = plan

  variables {
    subscription_acronym = "toolong"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "ingress"
  }

  expect_failures = [var.subscription_acronym]
}

# -----------------------------------------------------------------------
# Test 11: happy_legacy_5year_validity — explicit 1825 days accepted (F-6).
# Callers preserving legacy 5-year validity must set this explicitly after
# upgrading to v0.2.70 (SOFT BREAKING — default changed 1825 → 365).
# -----------------------------------------------------------------------
run "happy_legacy_5year_validity" {
  command = plan

  variables {
    cert_name     = "legacy-5yr-cert"
    validity_days = 1825
  }

  assert {
    condition     = tls_self_signed_cert.this.validity_period_hours == 1825 * 24
    error_message = "validity_period_hours must be validity_days * 24 (1825 * 24 = 43800)."
  }
}

# -----------------------------------------------------------------------
# Test 12: happy_early_renewal_set — non-zero early_renewal_hours accepted (F-7).
# -----------------------------------------------------------------------
run "happy_early_renewal_set" {
  command = plan

  variables {
    cert_name           = "cert-with-early-renewal"
    validity_days       = 90
    early_renewal_hours = 168
  }

  assert {
    condition     = tls_self_signed_cert.this.early_renewal_hours == 168
    error_message = "early_renewal_hours must be wired through to the tls_self_signed_cert resource."
  }
}

# -----------------------------------------------------------------------
# Test 13: happy_with_lock — CanNotDelete lock plans cleanly (F-9).
# -----------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    cert_name = "cert-with-lock"
    lock = {
      kind = "CanNotDelete"
    }
  }
}

# -----------------------------------------------------------------------
# Test 14: validator_invalid_lock_kind — invalid lock kind rejected (F-9).
# -----------------------------------------------------------------------
run "validator_invalid_lock_kind" {
  command = plan

  variables {
    cert_name = "cert-bad-lock"
    lock = {
      kind = "Delete"
    }
  }

  expect_failures = [var.lock]
}

# -----------------------------------------------------------------------
# Test 15: happy_with_role_assignments — single entry plans cleanly (F-10).
# -----------------------------------------------------------------------
run "happy_with_role_assignments" {
  command = plan

  variables {
    cert_name = "cert-with-rbac"
    role_assignments = {
      app_routing = {
        role_definition_id_or_name = "Key Vault Secrets User"
        principal_id               = "00000000-0000-0000-0000-000000000002"
      }
    }
  }
}

# -----------------------------------------------------------------------
# Test 16: validator_invalid_principal_type — invalid type rejected (F-10).
# -----------------------------------------------------------------------
run "validator_invalid_principal_type" {
  command = plan

  variables {
    cert_name = "cert-bad-rbac"
    role_assignments = {
      bad_entry = {
        role_definition_id_or_name = "Key Vault Secrets User"
        principal_id               = "00000000-0000-0000-0000-000000000003"
        principal_type             = "Machine"
      }
    }
  }

  expect_failures = [var.role_assignments]
}
