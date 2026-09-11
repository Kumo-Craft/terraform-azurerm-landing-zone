# ServiceBus

Creates an **Azure Service Bus namespace** (`Microsoft.ServiceBus/namespaces`) with optional **queues**, **topics + subscriptions**, **SAS authorization rules**, a managed **identity**, **network rules**, a **lock** and **RBAC**. Secure-by-default: TLS 1.2; Entra-only auth available via `local_auth_enabled = false`.

## Usage

```hcl
module "service_bus" {
  source = "../ServiceBus"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "frc"
  workload             = "01"
  location             = "francecentral"
  resource_group_name  = "rg-mgm-prod-frc-messaging"

  sku = "Standard"

  # Entra-only (recommended): disable SAS and grant data roles via RBAC.
  local_auth_enabled = false
  role_assignments = {
    app-sender = {
      role_definition_id_or_name = "Azure Service Bus Data Sender"
      principal_id               = "00000000-0000-0000-0000-000000000000"
    }
  }

  queues = {
    orders = { max_delivery_count = 10, requires_session = true }
  }

  topics = {
    events = {
      subscriptions = {
        billing = { max_delivery_count = 10 }
        audit   = { max_delivery_count = 5, requires_session = false }
      }
    }
  }

  tags = { Environment = "Production" }
}
```

## Notes

- **Auth**: `local_auth_enabled` defaults to `true` (SAS usable). Microsoft recommends **disabling local auth** (`false`) and using **Microsoft Entra ID + RBAC** data roles (`Azure Service Bus Data Sender/Receiver/Owner`) — assign them via `role_assignments`. `authorization_rules` are only usable while `local_auth_enabled = true`.
- **Private networking**: a fully private namespace requires the **Premium** SKU + a **Private Endpoint** and `public_network_access_enabled = false`. Declare PEs inline via the `private_endpoints` map (embedded `../PrivateEndpoint`, sub-resource `namespace`, DNS zone `privatelink.servicebus.windows.net`). Basic/Standard have no Private Endpoint; use `network_rule_set` (Premium) for IP/VNet restrictions.
- **Tiers**: `capacity`, `premium_messaging_partitions`, `network_rule_set` and CMK apply to **Premium** only. **Topics** require Standard or Premium (not Basic).
- **Checkov**: CKV_AZURE_199/201 (double encryption / CMK) and CKV_AZURE_203/204 (local auth / public access) are `checkov:skip`-annotated **with justifications** in `main.tf` — each secure setting is exposed as a variable (`customer_managed_key`, `local_auth_enabled`, `public_network_access_enabled`) but not forced by default because it is Premium-only or would break Basic/Standard operability. Enable them per workload.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Optional explicit namespace name (else sbns-{sub}-{env}-{region}-{workload}). | `string` | `null` | No |
| subscription_acronym / environment / region_code / workload | Naming components. | `string` | see vars | Conditional |
| location | Azure region. | `string` | -- | Yes |
| resource_group_name | Resource group name. | `string` | -- | Yes |
| sku | Basic / Standard / Premium. | `string` | `"Standard"` | No |
| capacity | Premium messaging units (1/2/4/8/16). | `number` | `null` | No |
| premium_messaging_partitions | Premium messaging partitions. | `number` | `null` | No |
| local_auth_enabled | SAS auth enabled. Set false for Entra-only. | `bool` | `true` | No |
| minimum_tls_version | Minimum TLS (1.0/1.1/1.2). | `string` | `"1.2"` | No |
| public_network_access_enabled | Public network access. | `bool` | `true` | No |
| identity | Managed identity object. | `object` | `null` | No |
| network_rule_set | Network rules (Premium). | `object` | `null` | No |
| customer_managed_key | CMK encryption (Premium; UAMI + KV key). `infrastructure_encryption_enabled` = double encryption. | `object` | `null` | No |
| queues | Map of queues. | `map(object)` | `{}` | No |
| topics | Map of topics (+ nested subscriptions). | `map(object)` | `{}` | No |
| authorization_rules | Map of namespace SAS rules. | `map(object)` | `{}` | No |
| lock | Optional resource lock. | `object` | `null` | No |
| role_assignments | RBAC map (delegated to ../RoleAssignment). | `map(object)` | `{}` | No |
| tags | Tags. | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Namespace ID |
| name | Namespace name |
| endpoint | Namespace endpoint URL |
| identity_principal_id / identity_tenant_id | Managed identity IDs (null if none) |
| default_primary_connection_string / default_primary_key | Root SAS (**sensitive**; empty when local auth disabled) |
| queue_ids / topic_ids / subscription_ids | Maps of entity key => ID |
| authorization_rule_ids | Map of rule name => ID |
| authorization_rule_primary_connection_strings | Map of rule name => connection string (**sensitive**) |
| lock_id | Management lock ID (null if no lock) |
| role_assignment_ids | Map of role assignment key => ID |
