# EventGridSystemTopic

Creates an **Event Grid System Topic** sourced from a **Key Vault**
(`topic_type = "Microsoft.KeyVault.vaults"`) plus a **webhook event
subscription** — the supported Terraform path to unblock Key Vault
**near-expiry** notifications (`SecretNearExpiry`, `CertificateNearExpiry`,
`KeyNearExpiry`) and the other `Microsoft.KeyVault.*` events.

Wraps [`azurerm_eventgrid_system_topic`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventgrid_system_topic) and [`azurerm_eventgrid_system_topic_event_subscription`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventgrid_system_topic_event_subscription).

## Why a system topic (and not polling)

Key Vault emits events 30 days before a secret/certificate/key expires. Without
an Event Grid subscription these events go **nowhere** — the usual failure mode
is a certificate silently expiring in production. This module wires the vault's
system topic to a webhook so the near-expiry signal reaches an actual handler.
(Grounded in [Monitoring Key Vault with Event Grid](https://learn.microsoft.com/azure/key-vault/general/event-grid-overview) and [Key Vault event schema](https://learn.microsoft.com/azure/event-grid/event-schema-key-vault).)

## Destination scope — webhook only (azurerm limitation)

> Event Grid also supports an **"Azure Monitor Alert" endpoint** that delivers
> straight to an **Action Group**. That endpoint type is **not implemented in
> the azurerm 4.x provider** (no `action_group` / `monitor_alert` destination
> on event subscriptions), so this module does **not** offer it. To reach an
> Action Group, point `webhook.url` at a **Logic App / Function / Automation
> runbook** that triggers the action group. The other azurerm-native
> destinations (Service Bus, Storage Queue, Event Hub, Azure Function) are out
> of scope for this KV-notification module.

## Usage

```hcl
module "kv_expiry_events" {
  source = "git::https://dev.azure.com/azure-forge/Modules/_git/Modules//modules/EventGridSystemTopic?ref=v0.3.0"

  subscription_acronym = "sec"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "keyvault"

  # The system topic must live in the Key Vault's region and resource group.
  key_vault_id        = dependency.key_vault.outputs.id
  location            = "germanywestcentral"
  resource_group_name = dependency.key_vault.outputs.resource_group_name

  webhook = {
    url = "https://prod-kvexpiry.logic.azure.com/workflows/.../triggers/manual/paths/invoke?..."
  }

  # default included_event_types = the 3 near-expiry types; override to widen:
  # included_event_types = ["Microsoft.KeyVault.SecretNearExpiry", "Microsoft.KeyVault.SecretExpired"]

  # Recommended for prod: never silently lose a near-expiry event.
  dead_letter = {
    storage_account_id          = dependency.storage.outputs.id
    storage_blob_container_name = "eventgrid-deadletter"
  }
}
```

## Naming

Via the [`Naming`](../Naming/) submodule (Azure/naming has no eventgrid
system-topic type, so the slug is built manually — like `ServiceBus`):

- System topic: `egst-{acr}-{env}-{region}-{workload}`
- Event subscription: `evgs-{acr}-{env}-{region}-{workload}`

Override with `name` / `event_subscription_name` (escape hatches).

## Gotchas (by design)

1. **`topic_type` is hardcoded to `"Microsoft.KeyVault.vaults"`** and not exposed — this module is Key-Vault-specific. Use a different module for other sources.
2. **`location` must be the Key Vault's region.** Event Grid creates a system topic for a regional source in that source's region; a mismatch is rejected.
3. **`key_vault_id` is ForceNew** — changing the source recreates the topic.
4. **`webhook` is `sensitive`** — the URL commonly embeds a SAS/token query string.
5. **Webhook must be HTTPS** — Event Grid never delivers to `http://`; validated.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `string` | `null` | System-topic name override. Null = derived `egst-…`. |
| `event_subscription_name` | `string` | `null` | Subscription name override. Null = derived `evgs-…`. |
| `subscription_acronym` / `environment` / `region_code` / `workload` | `string` | `…/…/…/"keyvault"` | Naming components (required unless `name` **and** `event_subscription_name` are set). |
| `key_vault_id` | `string` | — (required) | Source Key Vault ARM ID. ForceNew. |
| `location` | `string` | — (required) | Region (**must** match the Key Vault's). |
| `resource_group_name` | `string` | — (required) | RG for the topic + subscription. |
| `webhook` | `object` (sensitive) | — (required) | `url` (HTTPS, required) + optional `max_events_per_batch`, `preferred_batch_size_in_kilobytes`, `active_directory_tenant_id`, `active_directory_app_id_or_uri`. |
| `included_event_types` | `list(string)` | 3 near-expiry types | `Microsoft.KeyVault.*` event types (validated against the documented set). |
| `event_delivery_schema` | `string` | `"EventGridSchema"` | `EventGridSchema` / `CloudEventSchemaV1_0` / `CustomInputSchema`. ForceNew. |
| `advanced_filtering_on_arrays_enabled` | `bool` | `false` | Evaluate advanced filters against array values. |
| `subject_filter` | `object` | `null` | `subject_begins_with` / `subject_ends_with` / `case_sensitive`. |
| `retry_policy` | `object` | `{30, 1440}` | `max_delivery_attempts` (1-30) + `event_time_to_live` minutes (1-1440). |
| `dead_letter` | `object` | `null` | `storage_account_id` + `storage_blob_container_name` for undeliverable events. |
| `lock` | `object({ kind, name })` | `null` | Optional CanNotDelete/ReadOnly lock on the topic. |
| `tags` | `map(string)` | `{}` | Tags on the system topic. |

## Outputs

| Name | Description |
|------|-------------|
| `id` | System topic resource ID. |
| `name` | System topic name. |
| `metric_resource_id` | Resource ID for metric queries. |
| `event_subscription_id` | Webhook event subscription ID. |
| `event_subscription_name` | Webhook event subscription name. |
| `lock_ids` | Map of lock key => lock ID (empty when `lock` is null). |

## Testing

`tests/basic.tftest.hcl` — plan-time, `mock_provider "azurerm"`: derived + overridden naming, KV topic type, default near-expiry event set, full config (subject filter / retry / dead-letter / identity), optional lock, and validators (non-KV id, non-HTTPS webhook, invalid event type, retry range, partial AAD). Run: `terraform init -backend=false && terraform test`.
