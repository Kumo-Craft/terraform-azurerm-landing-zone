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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_eventgrid_system_topic.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventgrid_system_topic) | resource |
| [azurerm_eventgrid_system_topic_event_subscription.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/eventgrid_system_topic_event_subscription) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| key\_vault\_id | Full ARM ID of the source Key Vault. Sets source\_resource\_id; topic\_type is hardcoded to 'Microsoft.KeyVault.vaults'. ForceNew — changing it recreates the topic. | `string` | n/a | yes |
| location | Azure region of the system topic. For a Key Vault (a regional source) this MUST be the Key Vault's region. | `string` | n/a | yes |
| resource\_group\_name | Resource group for the system topic and its event subscription (typically the Key Vault's resource group). | `string` | n/a | yes |
| webhook | Webhook delivery target for the event subscription.<br>- url                               : (Required) HTTPS endpoint (Logic App / Function / Automation runbook / your own handler). May embed a secret token → the whole object is sensitive.<br>- max\_events\_per\_batch              : (Optional) 1-5000.<br>- preferred\_batch\_size\_in\_kilobytes : (Optional) up to 1024.<br>- active\_directory\_tenant\_id        : (Optional) Entra tenant ID for AAD-protected webhooks.<br>- active\_directory\_app\_id\_or\_uri    : (Optional) Entra app ID/URI for AAD-protected webhooks. | <pre>object({<br>    url                               = string<br>    max_events_per_batch              = optional(number)<br>    preferred_batch_size_in_kilobytes = optional(number)<br>    active_directory_tenant_id        = optional(string)<br>    active_directory_app_id_or_uri    = optional(string)<br>  })</pre> | n/a | yes |
| advanced\_filtering\_on\_arrays\_enabled | Whether advanced filtering evaluates against array values in the event payload. | `bool` | `false` | no |
| dead\_letter | Optional dead-letter destination for undeliverable events (Storage blob container). Recommended for production so near-expiry events are never silently lost. Null = no dead-lettering. | <pre>object({<br>    storage_account_id          = string<br>    storage_blob_container_name = string<br>  })</pre> | `null` | no |
| environment | Environment code (prod / nprd). | `string` | `null` | no |
| event\_delivery\_schema | Schema Event Grid uses to deliver events. One of EventGridSchema, CloudEventSchemaV1\_0, CustomInputSchema. ForceNew. | `string` | `"EventGridSchema"` | no |
| event\_subscription\_name | Explicit event-subscription name override. If null, derived via ../Naming (evgs-{acr}-{env}-{region}-{workload}). | `string` | `null` | no |
| included\_event\_types | Key Vault event types to subscribe to. Defaults to the near-expiry set (Secret/Certificate/Key). Each value must be a documented Microsoft.KeyVault.* event type. | `list(string)` | <pre>[<br>  "Microsoft.KeyVault.SecretNearExpiry",<br>  "Microsoft.KeyVault.CertificateNearExpiry",<br>  "Microsoft.KeyVault.KeyNearExpiry"<br>]</pre> | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) applied to the system topic. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| name | Explicit system-topic name override (escape hatch). If null, derived via ../Naming (egst-{acr}-{env}-{region}-{workload}). | `string` | `null` | no |
| region\_code | Region code (e.g. gwc). | `string` | `null` | no |
| retry\_policy | Delivery retry policy. max\_delivery\_attempts 1-30 (Azure default 30); event\_time\_to\_live 1-1440 minutes (Azure default 1440 = 24h). | <pre>object({<br>    max_delivery_attempts = optional(number, 30)<br>    event_time_to_live    = optional(number, 1440)<br>  })</pre> | `{}` | no |
| subject\_filter | Optional subject prefix/suffix filter (e.g. limit to a specific secret name). Null = no subject filter. | <pre>object({<br>    subject_begins_with = optional(string)<br>    subject_ends_with   = optional(string)<br>    case_sensitive      = optional(bool)<br>  })</pre> | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con, sec). | `string` | `null` | no |
| tags | Tags applied to the system topic. (Event subscriptions have no tags argument.) | `map(string)` | `{}` | no |
| workload | Workload name (naming suffix segment). | `string` | `"keyvault"` | no |

## Outputs

| Name | Description |
|------|-------------|
| event\_subscription\_id | Resource ID of the webhook event subscription. |
| event\_subscription\_name | Name of the webhook event subscription. |
| id | Resource ID of the Event Grid System Topic. |
| lock\_ids | Map of lock key => lock ID (empty when var.lock is null). |
| metric\_resource\_id | Resource ID used to query metrics for the system topic (v5-ready attribute, not the deprecated metric\_arm\_resource\_id). |
| name | Name of the Event Grid System Topic. |
<!-- END_TF_DOCS -->
