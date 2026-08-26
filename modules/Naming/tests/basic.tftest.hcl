# Plan-time tests for the Naming module.
#
# The module composes a suffix list and delegates name generation to
# Azure/naming/azurerm. No azurerm/time/random provider needs mocking —
# every output is computed at plan time from the input variables.
#
# Run locally with:
#   cd Naming
#   terraform init -backend=false
#   terraform test

# ---------------------------------------------------------------------
# Test 1: House convention smoke — resource_group name follows the
#         {type}-{acr}-{env}-{region}-{workload} pattern.
# ---------------------------------------------------------------------
run "house_convention_resource_group" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
  }

  assert {
    condition     = output.result.resource_group.name == "rg-mgm-nprd-gwc-platform"
    error_message = "Resource Group name must follow rg-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = output.suffix == tolist(["mgm", "nprd", "gwc", "platform"])
    error_message = "Composed suffix must be [acr, env, region, workload] in order."
  }
}

# ---------------------------------------------------------------------
# Test 2: Key Vault 24-char ceiling — upstream module caps length and
#         applies the kv- prefix. With short segments we stay <= 24.
# ---------------------------------------------------------------------
run "key_vault_within_24_chars" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
  }

  assert {
    condition     = length(output.result.key_vault.name) <= 24
    error_message = "Key Vault name must be at most 24 characters."
  }

  assert {
    condition     = output.result.key_vault.name == "kv-mgm-nprd-gwc-platform"
    error_message = "Key Vault name must follow kv-{acr}-{env}-{region}-{workload}."
  }
}

# ---------------------------------------------------------------------
# Test 3: Storage Account — hyphen-free, lowercase. Upstream module
#         strips separators and lowercases per Azure rules.
# ---------------------------------------------------------------------
run "storage_account_charset" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
  }

  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", output.result.storage_account.name))
    error_message = "Storage Account name must be 3-24 chars, lowercase alphanumerics only."
  }
}

# ---------------------------------------------------------------------
# Test 4: extra_suffix appends after workload.
# ---------------------------------------------------------------------
run "extra_suffix_appended" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
    extra_suffix         = ["01"]
  }

  assert {
    condition     = output.result.resource_group.name == "rg-mgm-nprd-gwc-platform-01"
    error_message = "extra_suffix must be appended after workload in the final name."
  }

  assert {
    condition     = output.suffix == tolist(["mgm", "nprd", "gwc", "platform", "01"])
    error_message = "extra_suffix segments must come after workload in the composed suffix."
  }
}

# ---------------------------------------------------------------------
# Test 5: Default unique_seed is the joined suffix — deterministic
#         naming across applies for the same inputs.
# ---------------------------------------------------------------------
run "unique_seed_defaults_to_suffix" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
  }

  assert {
    condition     = output.unique_seed == "mgm-nprd-gwc-platform"
    error_message = "When unique_seed is null, it must default to the joined suffix."
  }
}

# ---------------------------------------------------------------------
# Test 6: Explicit unique_seed override wins.
# ---------------------------------------------------------------------
run "unique_seed_override" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
    unique_seed          = "custom-seed-value"
  }

  assert {
    condition     = output.unique_seed == "custom-seed-value"
    error_message = "Explicit unique_seed must override the default joined-suffix seed."
  }
}

# ---------------------------------------------------------------------
# Test 7: Validation — subscription_acronym regex rejects uppercase.
# ---------------------------------------------------------------------
run "invalid_subscription_acronym_fails" {
  command = plan

  variables {
    subscription_acronym = "MGM"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
  }

  expect_failures = [var.subscription_acronym]
}

# ---------------------------------------------------------------------
# Test 8: Validation — workload regex rejects uppercase / bad charset.
# ---------------------------------------------------------------------
run "invalid_workload_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "Bad_Workload!"
  }

  expect_failures = [var.workload]
}

# ---------------------------------------------------------------------
# Test 9: Validation — unique_length out of bounds fails.
# ---------------------------------------------------------------------
run "invalid_unique_length_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
    unique_length        = 99
  }

  expect_failures = [var.unique_length]
}

# ---------------------------------------------------------------------
# Test 10: virtual_machine.name 15-char cap — upstream Azure/naming/azurerm
#          enforces the Windows NetBIOS limit. Guards against future
#          upstream version bumps silently changing truncation behavior.
# ---------------------------------------------------------------------
run "virtual_machine_15_char_cap" {
  command = plan

  variables {
    subscription_acronym = "shc"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
  }

  assert {
    condition     = length(output.result.virtual_machine.name) <= 15
    error_message = "virtual_machine name must be <= 15 chars (Windows NetBIOS constraint enforced by upstream Azure/naming/azurerm)."
  }
}

# ---------------------------------------------------------------------
# Test 11: Validation — environment uppercase rejected.
# regex ^[a-z]{2,4}$ rejects any uppercase character.
# ---------------------------------------------------------------------
run "invalid_environment_uppercase_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "PROD"
    region_code          = "gwc"
    workload             = "platform"
  }

  expect_failures = [var.environment]
}

# ---------------------------------------------------------------------
# Test 12: Validation — environment too long (> 4 chars) rejected.
# regex ^[a-z]{2,4}$ rejects strings longer than 4 characters.
# ---------------------------------------------------------------------
run "invalid_environment_too_long_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "production"
    region_code          = "gwc"
    workload             = "platform"
  }

  expect_failures = [var.environment]
}

# ---------------------------------------------------------------------
# Test 13: Validation — region_code uppercase rejected.
# regex ^[a-z]{2,5}$ rejects any uppercase character.
# ---------------------------------------------------------------------
run "invalid_region_code_uppercase_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "GWC"
    workload             = "platform"
  }

  expect_failures = [var.region_code]
}

# ---------------------------------------------------------------------
# Test 14: Validation — region_code with digit rejected.
# regex ^[a-z]{2,5}$ allows only lowercase letters — no digits.
# ---------------------------------------------------------------------
run "invalid_region_code_with_digit_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc1"
    workload             = "platform"
  }

  expect_failures = [var.region_code]
}

# ---------------------------------------------------------------------
# N-7: key_vault_certificate IS exposed by upstream Azure/naming/azurerm
#      0.4.3. Guards against the Truth 10 mistake (TlsSelfSignedCert
#      v0.2.64 used an inline `cert-` slug believing the type was absent
#      upstream — it is NOT). Referencing result.key_vault_certificate
#      errors at plan if the upstream ever drops the key, failing here.
# ---------------------------------------------------------------------
run "key_vault_certificate_present_upstream" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "platform"
  }

  assert {
    condition     = length(output.result.key_vault_certificate.name) > 0
    error_message = "key_vault_certificate.name must be exposed by upstream Azure/naming/azurerm (do not reintroduce an inline cert- slug — see Truth 10 recalibration)."
  }
}
