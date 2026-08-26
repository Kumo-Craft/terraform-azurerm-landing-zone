# Plan-time tests for the DomainServices module.
#
# Mocks azurerm + time; the Naming submodule's random provider runs for real.
#
# Covers:
#   1. happy_default   — derived slug name + hardened security defaults
#   2. name_override   — var.name wins, Naming module not instantiated
#   3. secure_ldap_on  — optional LDAPS block rendered
#   4. with_lock       — optional lock scoped to the managed domain
#   5. validator_domain_label_too_long — leading label > 15 chars → fail
#   6. validator_bad_domain_fqdn        — single-label domain → fail
#   7. validator_bad_sku                — invalid sku → fail
#   8. validator_bad_subnet_id          — not a subnet ARM id → fail
#
# Run with:
#   cd modules/DomainServices
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# Shared required inputs.
variables {
  subscription_acronym = "idt"
  environment          = "prod"
  region_code          = "gwc"
  location             = "germanywestcentral"
  resource_group_name  = "rg-idt-prod-gwc-domain"
  domain_name          = "aadds.contoso.com"
  replica_subnet_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-idt-prod-gwc-domain/providers/Microsoft.Network/virtualNetworks/vnet-idt/subnets/snet-aadds"
}

# -----------------------------------------------------------------------
# Test 1: happy_default — slug naming + hardened security posture.
# -----------------------------------------------------------------------
run "happy_default" {
  command = plan

  assert {
    condition     = azurerm_active_directory_domain_service.this.name == "aadds-idt-prod-gwc-domain"
    error_message = "Name must derive as aadds-{acronym}-{env}-{region}-{workload}."
  }

  assert {
    condition     = azurerm_active_directory_domain_service.this.security[0].kerberos_armoring_enabled == true
    error_message = "Kerberos armoring must be ON by default (hardened)."
  }

  assert {
    condition     = azurerm_active_directory_domain_service.this.security[0].ntlm_v1_enabled == false && azurerm_active_directory_domain_service.this.security[0].tls_v1_enabled == false && azurerm_active_directory_domain_service.this.security[0].kerberos_rc4_encryption_enabled == false
    error_message = "NTLM v1, TLS 1.0 and Kerberos RC4 must be OFF by default (hardened)."
  }

  assert {
    condition     = length(azurerm_active_directory_domain_service.this.secure_ldap) == 0
    error_message = "Secure LDAP must be off by default (var.secure_ldap null)."
  }
}

# -----------------------------------------------------------------------
# Test 2: name_override — escape hatch wins.
# -----------------------------------------------------------------------
run "name_override" {
  command = plan

  variables {
    name = "aadds-legacy-name"
  }

  assert {
    condition     = azurerm_active_directory_domain_service.this.name == "aadds-legacy-name"
    error_message = "var.name must override the derived name."
  }
}

# -----------------------------------------------------------------------
# Test 3: secure_ldap_on — optional LDAPS block rendered.
# -----------------------------------------------------------------------
run "secure_ldap_on" {
  command = plan

  variables {
    secure_ldap = {
      # Valid base64 (provider validates encoding at plan time; not a real PFX).
      pfx_certificate          = "ZHVtbXktcGZ4LWJ1bmRsZQ=="
      pfx_certificate_password = "s3cr3t-pfx-password"
    }
  }

  assert {
    condition     = length(azurerm_active_directory_domain_service.this.secure_ldap) == 1
    error_message = "Secure LDAP block must be planned when var.secure_ldap is set."
  }
}

# -----------------------------------------------------------------------
# Test 4: with_lock — optional lock scoped to the managed domain.
# -----------------------------------------------------------------------
run "with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "One lock must be planned when var.lock is set."
  }
}

# -----------------------------------------------------------------------
# Test 5: validator_domain_label_too_long — NetBIOS label > 15 chars.
# -----------------------------------------------------------------------
run "validator_domain_label_too_long" {
  command = plan

  variables {
    domain_name = "sixteencharacter.contoso.com"
  }

  expect_failures = [var.domain_name]
}

# -----------------------------------------------------------------------
# Test 6: validator_bad_domain_fqdn — single-label domain.
# -----------------------------------------------------------------------
run "validator_bad_domain_fqdn" {
  command = plan

  variables {
    domain_name = "contoso"
  }

  expect_failures = [var.domain_name]
}

# -----------------------------------------------------------------------
# Test 7: validator_bad_sku — invalid sku enum.
# -----------------------------------------------------------------------
run "validator_bad_sku" {
  command = plan

  variables {
    sku = "Basic"
  }

  expect_failures = [var.sku]
}

# -----------------------------------------------------------------------
# Test 8: validator_bad_subnet_id — not a subnet ARM id.
# -----------------------------------------------------------------------
run "validator_bad_subnet_id" {
  command = plan

  variables {
    replica_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.replica_subnet_id]
}
