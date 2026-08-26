# Plan-time tests for the ServiceBus module.
#
# Mocks azurerm. Covers:
#   1. happy_default_naming            — convention naming + secure defaults
#   2. happy_name_override             — explicit var.name (XOR escape hatch)
#   3. happy_entra_only                — local_auth_enabled = false + data role
#   4. happy_entities                  — queues + topics + subscriptions counts
#   5. happy_auth_rules                — namespace SAS rules
#   6. happy_identity_and_network      — identity + network_rule_set blocks
#   7. happy_with_lock                 — var.lock
#   8. validator_naming_xor_fails      — name=null + naming vars=null → failure
#   9. validator_invalid_sku           — bad sku → failure
#  10. validator_invalid_capacity      — capacity 3 → failure
#  11. validator_authrule_manage       — manage without listen+send → failure
#  12. validator_invalid_role_principal — principal_type = "Foo" → failure
#
# Run with:
#   cd modules/ServiceBus
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

variables {
  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "frc"
  workload             = "01"
  location             = "francecentral"
  resource_group_name  = "rg-mgm-prod-frc-messaging"
}

# -----------------------------------------------------------------------
# Test 1: happy_default_naming — convention naming + secure defaults.
# -----------------------------------------------------------------------
run "happy_default_naming" {
  command = plan

  assert {
    condition     = azurerm_servicebus_namespace.this.name == "sbns-mgm-prod-frc-01"
    error_message = "Namespace name must follow the sbns-{sub}-{env}-{region}-{workload} convention."
  }

  assert {
    condition     = azurerm_servicebus_namespace.this.sku == "Standard"
    error_message = "sku must default to Standard."
  }

  assert {
    condition     = azurerm_servicebus_namespace.this.minimum_tls_version == "1.2"
    error_message = "minimum_tls_version must default to 1.2."
  }
}

# -----------------------------------------------------------------------
# Test 2: happy_name_override — explicit var.name (XOR escape hatch).
# -----------------------------------------------------------------------
run "happy_name_override" {
  command = plan

  variables {
    name = "sbns-legacy-custom"
  }

  assert {
    condition     = azurerm_servicebus_namespace.this.name == "sbns-legacy-custom"
    error_message = "Namespace name must match the explicit var.name override."
  }
}

# -----------------------------------------------------------------------
# Test 3: happy_entra_only — local auth off + a data-plane role assignment.
# -----------------------------------------------------------------------
run "happy_entra_only" {
  command = plan

  variables {
    local_auth_enabled = false
    role_assignments = {
      sender = {
        role_definition_id_or_name = "Azure Service Bus Data Sender"
        principal_id               = "00000000-0000-0000-0000-000000000001"
      }
    }
  }

  assert {
    condition     = azurerm_servicebus_namespace.this.local_auth_enabled == false
    error_message = "local_auth_enabled must wire false (Entra-only)."
  }

  assert {
    condition     = length(module.rbac) == 1
    error_message = "One rbac module instance must be planned for 1 role assignment."
  }
}

# -----------------------------------------------------------------------
# Test 4: happy_entities — queues + topics + subscriptions.
# -----------------------------------------------------------------------
run "happy_entities" {
  command = plan

  variables {
    queues = {
      orders = { max_delivery_count = 10, requires_session = true }
    }
    topics = {
      events = {
        subscriptions = {
          billing = { max_delivery_count = 10 }
          audit   = { max_delivery_count = 5 }
        }
      }
    }
  }

  assert {
    condition     = azurerm_servicebus_queue.this["orders"].name == "orders"
    error_message = "Queue name must default to the map key."
  }

  assert {
    condition     = length(azurerm_servicebus_topic.this) == 1
    error_message = "One topic must be planned."
  }

  assert {
    condition     = length(azurerm_servicebus_subscription.this) == 2
    error_message = "Two subscriptions must be flattened from the topic."
  }
}

# -----------------------------------------------------------------------
# Test 5: happy_auth_rules — namespace SAS authorization rules.
# -----------------------------------------------------------------------
run "happy_auth_rules" {
  command = plan

  variables {
    authorization_rules = {
      app-listen = { listen = true, send = false, manage = false }
    }
  }

  assert {
    condition     = azurerm_servicebus_namespace_authorization_rule.this["app-listen"].listen == true
    error_message = "Authorization rule listen must wire through."
  }
}

# -----------------------------------------------------------------------
# Test 6: happy_identity_and_network — identity + network_rule_set blocks.
# -----------------------------------------------------------------------
run "happy_identity_and_network" {
  command = plan

  variables {
    sku      = "Premium"
    capacity = 1
    identity = { type = "SystemAssigned" }
    network_rule_set = {
      default_action = "Deny"
      ip_rules       = ["10.0.0.0/24"]
    }
  }

  assert {
    condition     = azurerm_servicebus_namespace.this.identity[0].type == "SystemAssigned"
    error_message = "identity block must wire type through."
  }

  assert {
    condition     = length(azurerm_servicebus_namespace.this.network_rule_set) == 1
    error_message = "network_rule_set block must be emitted when provided."
  }
}

# -----------------------------------------------------------------------
# Test 6b: happy_customer_managed_key — CMK + double encryption block wired.
# -----------------------------------------------------------------------
run "happy_customer_managed_key" {
  command = plan

  variables {
    sku      = "Premium"
    capacity = 1
    identity = { type = "UserAssigned", identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-sb"] }
    customer_managed_key = {
      key_vault_key_id = "https://kv-example.vault.azure.net/keys/sb-cmk/abc"
      identity_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-sb"
    }
  }

  assert {
    condition     = length(azurerm_servicebus_namespace.this.customer_managed_key) == 1
    error_message = "customer_managed_key block must be emitted when provided."
  }

  assert {
    condition     = azurerm_servicebus_namespace.this.customer_managed_key[0].infrastructure_encryption_enabled == true
    error_message = "infrastructure_encryption_enabled must default to true (double encryption) when CMK is set."
  }
}

# -----------------------------------------------------------------------
# Test 6c: happy_with_private_endpoint — embedded ../PrivateEndpoint.
# -----------------------------------------------------------------------
run "happy_with_private_endpoint" {
  command = plan

  variables {
    sku      = "Premium"
    capacity = 1
    private_endpoints = {
      sbns = {
        subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-frc-network/providers/Microsoft.Network/virtualNetworks/vnet-mgm-prod-frc/subnets/snet-pe"
        private_dns_zone_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mgm-prod-frc-dns/providers/Microsoft.Network/privateDnsZones/privatelink.servicebus.windows.net"]
      }
    }
  }

  assert {
    condition     = length(module.private_endpoint) == 1
    error_message = "One PrivateEndpoint module instance must be planned when private_endpoints has an entry."
  }
}

# -----------------------------------------------------------------------
# Test 7: happy_with_lock — var.lock.
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
# Test 8: validator_naming_xor_fails — name=null + naming vars=null → failure.
# -----------------------------------------------------------------------
run "validator_naming_xor_fails" {
  command = plan

  variables {
    subscription_acronym = null
    environment          = null
    region_code          = null
  }

  expect_failures = [var.name]
}

# -----------------------------------------------------------------------
# Test 9: validator_invalid_sku — bad sku → failure.
# -----------------------------------------------------------------------
run "validator_invalid_sku" {
  command = plan

  variables {
    sku = "Ultra"
  }

  expect_failures = [var.sku]
}

# -----------------------------------------------------------------------
# Test 10: validator_invalid_capacity — 3 → failure.
# -----------------------------------------------------------------------
run "validator_invalid_capacity" {
  command = plan

  variables {
    capacity = 3
  }

  expect_failures = [var.capacity]
}

# -----------------------------------------------------------------------
# Test 11: validator_authrule_manage — manage without listen+send → failure.
# -----------------------------------------------------------------------
run "validator_authrule_manage" {
  command = plan

  variables {
    authorization_rules = {
      bad = { listen = false, send = false, manage = true }
    }
  }

  expect_failures = [var.authorization_rules]
}

# -----------------------------------------------------------------------
# Test 12: validator_invalid_role_principal_type — "Foo" → failure.
# -----------------------------------------------------------------------
run "validator_invalid_role_principal_type" {
  command = plan

  variables {
    role_assignments = {
      bad = {
        role_definition_id_or_name = "Contributor"
        principal_id               = "00000000-0000-0000-0000-000000000002"
        principal_type             = "Foo"
      }
    }
  }

  expect_failures = [var.role_assignments]
}
