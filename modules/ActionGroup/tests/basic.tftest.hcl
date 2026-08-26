# Plan-time tests for the ActionGroup module.
#
# Run with:
#   cd modules/ActionGroup
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}
mock_provider "time" {}

# ---------------------------------------------------------------------
# Test 1: Convention naming — 4 house vars set, no `name` override.
#         Produces ag-{acr}-{env}-{region}-{workload}.
# ---------------------------------------------------------------------
run "convention_naming" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-mgm-nprd-gwc-mon"
  }

  assert {
    condition     = azurerm_monitor_action_group.this.name == "ag-mgm-nprd-gwc-ama"
    error_message = "Convention naming must produce ag-{acr}-{env}-{region}-{workload}."
  }
}

# ---------------------------------------------------------------------
# Test 2: Legacy override — `name` set, house vars null.
#         The Naming submodule is NOT instantiated (for_each empty set);
#         the override wins.
# ---------------------------------------------------------------------
run "legacy_name_override" {
  command = plan

  variables {
    name                = "ActionGroup-Old-Random"
    resource_group_name = "rg-legacy"
    # subscription_acronym, environment, region_code, workload all null
  }

  assert {
    condition     = azurerm_monitor_action_group.this.name == "ActionGroup-Old-Random"
    error_message = "name override must take precedence over convention."
  }
}

# ---------------------------------------------------------------------
# Test 3: Validation — neither `name` nor the 4 house vars set should
#         fail the cross-var validator on `var.name`.
# ---------------------------------------------------------------------
run "no_name_no_house_vars_fails" {
  command = plan

  variables {
    resource_group_name = "rg-test"
    # name = null, all house vars = null
  }

  expect_failures = [var.name]
}

# ---------------------------------------------------------------------
# Test 4: short_name minimum (1 char) — validator must accept it.
# ---------------------------------------------------------------------
run "short_name_min_accepted" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-test"
    short_name           = "X"
  }

  assert {
    condition     = azurerm_monitor_action_group.this.short_name == "X"
    error_message = "short_name of 1 character must be accepted by the validator."
  }
}

# ---------------------------------------------------------------------
# Test 5: short_name too long (13 chars) — validator must reject it.
# ---------------------------------------------------------------------
run "short_name_too_long_fails" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-test"
    short_name           = "ThirteenCharS"
  }

  expect_failures = [var.short_name]
}

# ---------------------------------------------------------------------
# Test 6: webhook_receiver — F-2: one entry, verify dynamic block planned.
# ---------------------------------------------------------------------
run "happy_with_webhook_receiver" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-test"

    webhook_receivers = {
      pagerduty = {
        service_uri             = "https://events.pagerduty.com/integration/abc123/enqueue"
        use_common_alert_schema = true
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this.webhook_receiver) == 1
    error_message = "One webhook_receiver entry must produce exactly one webhook_receiver block."
  }
}

# ---------------------------------------------------------------------
# Test 7: sms_receiver — F-2: one entry, verify country_code + phone_number wired.
# ---------------------------------------------------------------------
run "happy_with_sms_receiver" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-test"

    sms_receivers = {
      oncall = {
        country_code = "32"
        phone_number = "0123456789"
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this.sms_receiver) == 1
    error_message = "One sms_receivers entry must produce exactly one sms_receiver block."
  }
  assert {
    condition     = tolist(azurerm_monitor_action_group.this.sms_receiver)[0].country_code == "32"
    error_message = "sms_receiver.country_code must flow through from var.sms_receivers."
  }
}

# ---------------------------------------------------------------------
# Test 8: arm_role_receiver — F-2: Monitoring Contributor role_id.
# ---------------------------------------------------------------------
run "happy_with_arm_role_receiver" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-test"

    arm_role_receivers = {
      monitoring-contributor = {
        role_id                 = "749f88d5-cbae-40b8-bcfc-e573ddc772fa"
        use_common_alert_schema = true
      }
    }
  }

  assert {
    condition     = length(azurerm_monitor_action_group.this.arm_role_receiver) == 1
    error_message = "One arm_role_receivers entry must produce exactly one arm_role_receiver block."
  }
}

# ---------------------------------------------------------------------
# Test 9: var.lock — F-6: CanNotDelete lock, module.lock must be instantiated.
# ---------------------------------------------------------------------
run "happy_with_lock" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-test"

    lock = {
      kind = "CanNotDelete"
    }
  }

  assert {
    condition     = var.lock.kind == "CanNotDelete"
    error_message = "lock.kind must flow through to the lock variable."
  }
}

# ---------------------------------------------------------------------
# Test 10: use_common_alert_schema for email_receiver — verify it flows through.
# ---------------------------------------------------------------------
run "happy_use_common_alert_schema_email" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-test"
    email_addresses      = ["ops@example.com"]
  }

  assert {
    condition     = tolist(azurerm_monitor_action_group.this.email_receiver)[0].use_common_alert_schema == true
    error_message = "email_receiver.use_common_alert_schema must be hardcoded true."
  }
}

# ---------------------------------------------------------------------
# Test 11: Invalid webhook URI — F-2 regex validator must reject it.
# ---------------------------------------------------------------------
run "validator_invalid_webhook_uri" {
  command = plan

  variables {
    subscription_acronym = "mgm"
    environment          = "nprd"
    region_code          = "gwc"
    workload             = "ama"
    resource_group_name  = "rg-test"

    webhook_receivers = {
      bad = {
        service_uri = "not-a-url"
      }
    }
  }

  expect_failures = [var.webhook_receivers]
}
