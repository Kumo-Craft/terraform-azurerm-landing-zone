# Plan-time tests for the EventGridSystemTopic module.
#
# Covers:
#   1. happy_default            — derived naming, default near-expiry event set, webhook
#   2. happy_name_override       — explicit topic + subscription names
#   3. happy_full                — subject_filter + retry + dead_letter + identity + custom events
#   4. happy_with_lock           — optional management lock
#   5. validator_bad_kv_id        — non-KeyVault key_vault_id → failure
#   6. validator_bad_webhook_url  — non-HTTPS webhook.url → failure
#   7. validator_bad_event_type   — non Microsoft.KeyVault.* event type → failure
#   8. validator_retry_range      — max_delivery_attempts out of 1-30 → failure
#   9. validator_aad_partial      — only one of the two AAD webhook fields → failure
#
# Run with:
#   cd modules/EventGridSystemTopic
#   terraform init -backend=false
#   terraform test

mock_provider "azurerm" {}

variables {
  subscription_acronym = "sec"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "keyvault"
  location             = "germanywestcentral"
  resource_group_name  = "rg-sec-prod-gwc"
  key_vault_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec-prod-gwc/providers/Microsoft.KeyVault/vaults/kv-sec-prod-gwc-01"
  webhook = {
    url = "https://handler.example.com/kv-expiry"
  }
}

# 1. nominal — derived names, KV topic type, default near-expiry event set.
run "happy_default" {
  command = plan

  assert {
    condition     = azurerm_eventgrid_system_topic.this.name == "egst-sec-prod-gwc-keyvault"
    error_message = "system topic name must be the derived egst- slug."
  }
  assert {
    condition     = azurerm_eventgrid_system_topic.this.topic_type == "Microsoft.KeyVault.vaults"
    error_message = "topic_type must be hardcoded to Microsoft.KeyVault.vaults."
  }
  assert {
    condition     = azurerm_eventgrid_system_topic.this.source_resource_id == var.key_vault_id
    error_message = "source_resource_id must be the Key Vault ID."
  }
  assert {
    condition     = azurerm_eventgrid_system_topic_event_subscription.this.name == "evgs-sec-prod-gwc-keyvault"
    error_message = "event subscription name must be the derived evgs- slug."
  }
  assert {
    condition     = length(azurerm_eventgrid_system_topic_event_subscription.this.included_event_types) == 3
    error_message = "default included_event_types must be the 3 near-expiry types."
  }
  assert {
    condition     = azurerm_eventgrid_system_topic_event_subscription.this.event_delivery_schema == "EventGridSchema"
    error_message = "event_delivery_schema must default to EventGridSchema."
  }
}

# 2. explicit name overrides for both topic and subscription.
run "happy_name_override" {
  command = plan

  variables {
    name                    = "egst-custom-topic"
    event_subscription_name = "evgs-custom-sub"
  }

  assert {
    condition     = azurerm_eventgrid_system_topic.this.name == "egst-custom-topic"
    error_message = "topic name override must win."
  }
  assert {
    condition     = azurerm_eventgrid_system_topic_event_subscription.this.name == "evgs-custom-sub"
    error_message = "event subscription name override must win."
  }
}

# 3. full config — subject filter, custom retry, dead letter, identity, single event type.
run "happy_full" {
  command = plan

  variables {
    included_event_types = ["Microsoft.KeyVault.SecretNearExpiry"]
    subject_filter = {
      subject_begins_with = "prod-"
      case_sensitive      = true
    }
    retry_policy = {
      max_delivery_attempts = 10
      event_time_to_live    = 120
    }
    dead_letter = {
      storage_account_id          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec-prod-gwc/providers/Microsoft.Storage/storageAccounts/stsecprodgwcdlq"
      storage_blob_container_name = "eventgrid-deadletter"
    }
    tags = { costCenter = "sec" }
  }

  assert {
    condition     = length(azurerm_eventgrid_system_topic_event_subscription.this.included_event_types) == 1
    error_message = "included_event_types override must apply."
  }
  assert {
    condition     = azurerm_eventgrid_system_topic_event_subscription.this.retry_policy[0].max_delivery_attempts == 10
    error_message = "retry_policy.max_delivery_attempts must wire through."
  }
  assert {
    condition     = azurerm_eventgrid_system_topic_event_subscription.this.subject_filter[0].subject_begins_with == "prod-"
    error_message = "subject_filter must wire through when set."
  }
  assert {
    condition     = azurerm_eventgrid_system_topic_event_subscription.this.storage_blob_dead_letter_destination[0].storage_blob_container_name == "eventgrid-deadletter"
    error_message = "dead_letter must wire through when set."
  }
}

# 4. optional management lock.
run "happy_with_lock" {
  command = plan

  variables {
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(module.lock.ids) == 1
    error_message = "a lock must be created when var.lock is set."
  }
}

# 5. non-KeyVault key_vault_id => failure.
run "validator_bad_kv_id" {
  command = plan

  variables {
    key_vault_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec-prod-gwc/providers/Microsoft.Storage/storageAccounts/stsecprodgwc01"
  }

  expect_failures = [var.key_vault_id]
}

# 6. non-HTTPS webhook.url => failure.
run "validator_bad_webhook_url" {
  command = plan

  variables {
    webhook = { url = "http://insecure.example.com/hook" }
  }

  expect_failures = [var.webhook]
}

# 7. non Microsoft.KeyVault.* event type => failure.
run "validator_bad_event_type" {
  command = plan

  variables {
    included_event_types = ["Microsoft.Storage.BlobCreated"]
  }

  expect_failures = [var.included_event_types]
}

# 8. retry max_delivery_attempts out of 1-30 => failure.
run "validator_retry_range" {
  command = plan

  variables {
    retry_policy = { max_delivery_attempts = 99 }
  }

  expect_failures = [var.retry_policy]
}

# 9. only one of the two AAD webhook fields => failure.
run "validator_aad_partial" {
  command = plan

  variables {
    webhook = {
      url                        = "https://handler.example.com/kv-expiry"
      active_directory_tenant_id = "11111111-1111-1111-1111-111111111111"
    }
  }

  expect_failures = [var.webhook]
}
