###############################################################
# MODULE: EventGridSystemTopic - Main
# Description: Event Grid System Topic sourced from a Key Vault
#              (topic_type "Microsoft.KeyVault.vaults") plus a webhook
#              event subscription — the supported azurerm path to unblock
#              SecretNearExpiry / CertificateNearExpiry / KeyNearExpiry
#              notifications.
#
# Destination scope: WEBHOOK only. The azurerm 4.x provider does NOT
# expose the Event Grid "Azure Monitor Alert" (action group) endpoint
# type on event subscriptions — route to an Action Group by pointing the
# webhook at a Logic App / Function / Automation runbook that fans out.
###############################################################

###############################################################
# Naming — house prefixes egst- (topic) / evgs- (subscription) + the
# Naming submodule suffix. Instantiated whenever EITHER name is derived.
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = (var.name == null || var.event_subscription_name == null) ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  name                    = var.name != null ? var.name : "egst-${join("-", module.naming["this"].suffix)}"
  event_subscription_name = var.event_subscription_name != null ? var.event_subscription_name : "evgs-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RESOURCE: Event Grid System Topic (source = Key Vault)
###############################################################
resource "azurerm_eventgrid_system_topic" "this" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # source_resource_id (not the deprecated source_arm_resource_id) — the v5-ready
  # attribute for the event source.
  source_resource_id = var.key_vault_id
  # ⚠️ topic_type is FIXED to the Key Vault source type — this module is
  # KV-specific by design; do not expose it as a variable.
  topic_type = "Microsoft.KeyVault.vaults"

  tags = var.tags
}

###############################################################
# RESOURCE: Event Subscription (destination = webhook)
###############################################################
resource "azurerm_eventgrid_system_topic_event_subscription" "this" {
  name                = local.event_subscription_name
  system_topic        = azurerm_eventgrid_system_topic.this.name
  resource_group_name = var.resource_group_name

  included_event_types                 = var.included_event_types
  event_delivery_schema                = var.event_delivery_schema
  advanced_filtering_on_arrays_enabled = var.advanced_filtering_on_arrays_enabled

  webhook_endpoint {
    url                               = var.webhook.url
    max_events_per_batch              = var.webhook.max_events_per_batch
    preferred_batch_size_in_kilobytes = var.webhook.preferred_batch_size_in_kilobytes
    active_directory_tenant_id        = var.webhook.active_directory_tenant_id
    active_directory_app_id_or_uri    = var.webhook.active_directory_app_id_or_uri
  }

  dynamic "subject_filter" {
    for_each = var.subject_filter != null ? [var.subject_filter] : []
    content {
      subject_begins_with = subject_filter.value.subject_begins_with
      subject_ends_with   = subject_filter.value.subject_ends_with
      case_sensitive      = subject_filter.value.case_sensitive
    }
  }

  retry_policy {
    max_delivery_attempts = var.retry_policy.max_delivery_attempts
    event_time_to_live    = var.retry_policy.event_time_to_live
  }

  dynamic "storage_blob_dead_letter_destination" {
    for_each = var.dead_letter != null ? [var.dead_letter] : []
    content {
      storage_account_id          = storage_blob_dead_letter_destination.value.storage_account_id
      storage_blob_container_name = storage_blob_dead_letter_destination.value.storage_blob_container_name
    }
  }
}

###############################################################
# RESOURCE: Management Lock (optional) — on the system topic
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_eventgrid_system_topic.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
