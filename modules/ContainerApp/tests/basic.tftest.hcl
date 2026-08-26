# Plan-time tests for the ContainerApp module.
#
# Mocks azurerm + time so plan can resolve without credentials.
#
# Run with:
#   cd modules/ContainerApp
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

variables {
  resource_group_name          = "rg-api-prod-gwc-aca"
  container_app_environment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-api-prod-gwc-aca/providers/Microsoft.App/managedEnvironments/cae-api-prod-gwc-web"
  containers = [{
    name   = "app"
    image  = "mcr.microsoft.com/k8se/quickstart:latest"
    cpu    = 0.25
    memory = "0.5Gi"
  }]
}

# ---------------------------------------------------------------------
# Test 1: Convention smoke — name + single container, default Single mode.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "web"
  }

  assert {
    condition     = output.name == "ca-api-prod-gwc-web"
    error_message = "Computed name must follow ca-{acr}-{env}-{region}-{workload}."
  }

  assert {
    condition     = azurerm_container_app.this.revision_mode == "Single"
    error_message = "revision_mode must default to Single."
  }

  assert {
    condition     = azurerm_container_app.this.template[0].container[0].image == "mcr.microsoft.com/k8se/quickstart:latest"
    error_message = "Container image must pass through."
  }
}

# ---------------------------------------------------------------------
# Test 2: Ingress with default traffic weight + probe + env secret.
# ---------------------------------------------------------------------
run "ingress_and_probe" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "web"

    containers = [{
      name   = "app"
      image  = "myacr.azurecr.io/app:1.0"
      cpu    = 0.5
      memory = "1Gi"
      env = [
        { name = "LOG_LEVEL", value = "info" },
        { name = "DB_PASSWORD", secret_name = "db-password" },
      ]
      liveness_probe = {
        port      = 8080
        transport = "HTTP"
        path      = "/healthz"
      }
    }]

    ingress = {
      target_port      = 8080
      external_enabled = true
    }

    secrets = [{
      name  = "db-password"
      value = "p@ss"
    }]

    registries = [{
      server   = "myacr.azurecr.io"
      identity = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-id/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-aca"
    }]

    identity = {
      type         = "UserAssigned"
      identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-id/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-aca"]
    }
  }

  assert {
    condition     = azurerm_container_app.this.ingress[0].target_port == 8080
    error_message = "ingress target_port must pass through."
  }

  assert {
    condition     = one(azurerm_container_app.this.ingress[0].traffic_weight).percentage == 100
    error_message = "Default traffic weight must be 100% to latest."
  }

  assert {
    condition     = azurerm_container_app.this.template[0].container[0].liveness_probe[0].path == "/healthz"
    error_message = "Liveness probe path must pass through."
  }
}

# ---------------------------------------------------------------------
# Test 3: Validator — registry with both identity and username fails.
# ---------------------------------------------------------------------
run "registry_both_auth_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "web"

    registries = [{
      server               = "myacr.azurecr.io"
      identity             = "/subscriptions/.../userAssignedIdentities/uami"
      username             = "admin"
      password_secret_name = "acr-pw"
    }]
  }

  expect_failures = [var.registries]
}

# ---------------------------------------------------------------------
# Test 4: Validator — Key Vault secret without identity fails.
# ---------------------------------------------------------------------
run "kv_secret_without_identity_fails" {
  command = plan

  variables {
    subscription_acronym = "api"
    environment          = "prod"
    region_code          = "gwc"
    workload             = "web"

    secrets = [{
      name                = "kv-secret"
      key_vault_secret_id = "https://kv.vault.azure.net/secrets/foo"
    }]
  }

  expect_failures = [var.secrets]
}

# ---------------------------------------------------------------------
# Test 5: Validator — invalid container_app_environment_id fails.
# ---------------------------------------------------------------------
run "invalid_environment_id_fails" {
  command = plan

  variables {
    subscription_acronym         = "api"
    environment                  = "prod"
    region_code                  = "gwc"
    workload                     = "web"
    container_app_environment_id = "not-an-env-id"
  }

  expect_failures = [var.container_app_environment_id]
}
