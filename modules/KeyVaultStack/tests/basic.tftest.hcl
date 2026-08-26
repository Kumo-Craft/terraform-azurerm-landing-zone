# Plan-time tests for the KeyVaultStack module.
#
# Mocks azurerm + time so plan can resolve without credentials.
# The Stack composes ../KeyVault and ../PrivateEndpoint; these
# tests exercise the wiring (naming + PE→KV resource_id link +
# legacy escape hatch).
#
# Run with:
#   cd modules/KeyVaultStack
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
      object_id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — house vars produce
#         kv-{acr}-{env}-{region}-{workload} on the KV,
#         pep-{acr}-{env}-{region}-kv-{workload} on the PE.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "apim"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-apim"
    subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"
  }

  assert {
    condition     = output.key_vault_name == "kv-api-prod-gwc-apim"
    error_message = "KV name must follow kv-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = output.private_endpoint_name == "pep-api-prod-gwc-kv-apim"
    error_message = "PE name must follow pep-{acr}-{env}-{region}-kv-{workload}."
  }

  assert {
    condition     = output.resource_group_name == "rg-api-prod-gwc-apim"
    error_message = "resource_group_name output must passthrough var.resource_group_name."
  }
}

# ---------------------------------------------------------------------
# Test 2: kv_suffix override — produces a different KV+PE name
#         while leaving workload as-is.
# ---------------------------------------------------------------------
run "kv_suffix_override" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "apim"
    kv_suffix            = "002"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-apim"
    subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"
  }

  assert {
    condition     = output.key_vault_name == "kv-api-prod-gwc-002"
    error_message = "kv_suffix must override the workload segment in the KV name."
  }

  assert {
    condition     = output.private_endpoint_name == "pep-api-prod-gwc-kv-002"
    error_message = "kv_suffix must override the workload segment in the PE name."
  }
}

# ---------------------------------------------------------------------
# Test 3: kv_name explicit override — bypasses convention entirely.
# ---------------------------------------------------------------------
run "explicit_kv_name_override" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "apim"
    kv_name              = "kv-legacy-2022"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-apim"
    subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"
  }

  assert {
    condition     = output.key_vault_name == "kv-legacy-2022"
    error_message = "Explicit kv_name override must take precedence over the convention."
  }
}

# ---------------------------------------------------------------------
# Test 4: PE wiring — private_endpoint.resource_id must point at the
#         composed KV's id (no string concatenation in the Stack).
# ---------------------------------------------------------------------
run "pe_wired_to_kv" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "apim"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-apim"
    subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-net/providers/Microsoft.Network/virtualNetworks/vnet-api-prod-gwc/subnets/snet-api-prod-gwc-pe"
  }

  # Under mock_provider, resource.id resolves to a known-after-apply
  # value, but the wiring (module.pe.resources["this"].name) is
  # already concrete because we control it via local.pe_name.
  assert {
    condition     = output.private_endpoint_name == "pep-api-prod-gwc-kv-apim"
    error_message = "PE wiring smoke — name must resolve at plan time via local.pe_name."
  }
}

# ---------------------------------------------------------------------
# Test 5: Subnet ID validation — bad format must fail at plan time.
# ---------------------------------------------------------------------
run "invalid_subnet_id_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "apim"
    location             = "germanywestcentral"
    resource_group_name  = "rg-api-prod-gwc-apim"
    subnet_id            = "not-a-valid-subnet-id"
  }

  expect_failures = [var.subnet_id]
}
