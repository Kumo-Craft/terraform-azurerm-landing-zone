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
| private\_endpoint | ../PrivateEndpoint | n/a |
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_servicebus_namespace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_namespace) | resource |
| [azurerm_servicebus_namespace_authorization_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_namespace_authorization_rule) | resource |
| [azurerm_servicebus_queue.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_queue) | resource |
| [azurerm_servicebus_subscription.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_subscription) | resource |
| [azurerm_servicebus_topic.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/servicebus_topic) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| authorization\_rules | Map of namespace-level SAS authorization rules. Only usable when local\_auth\_enabled = true. Key is the rule name. | <pre>map(object({<br>    listen = optional(bool, true)<br>    send   = optional(bool, true)<br>    manage = optional(bool, false)<br>  }))</pre> | `{}` | no |
| capacity | Premium messaging units (1, 2, 4, 8, 16). Only valid for the Premium SKU; null for Basic/Standard. | `number` | `null` | no |
| customer\_managed\_key | Optional CMK encryption (Premium only). Requires a user-assigned identity with get/wrap/unwrap on the Key Vault key. infrastructure\_encryption\_enabled = double encryption at rest (CKV\_AZURE\_199). | <pre>object({<br>    key_vault_key_id                  = string<br>    identity_id                       = string<br>    infrastructure_encryption_enabled = optional(bool, true)<br>  })</pre> | `null` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| identity | Optional managed identity (for CMK / Entra scenarios). type = SystemAssigned \| UserAssigned \| 'SystemAssigned, UserAssigned'. | <pre>object({<br>    type         = string<br>    identity_ids = optional(list(string), null)<br>  })</pre> | `null` | no |
| local\_auth\_enabled | Whether SAS (shared access key) authentication is enabled. Default true. Set false to enforce Entra-only auth (recommended by MS — pair with RBAC data roles via role\_assignments). | `bool` | `true` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the namespace. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| minimum\_tls\_version | Minimum TLS version. Default 1.2. | `string` | `"1.2"` | no |
| name | Optional. Explicit namespace name. If null, computed (sbns-{sub}-{env}-{region}-{workload}). Globally unique. | `string` | `null` | no |
| network\_rule\_set | Optional network rule set (Premium only). default\_action Allow/Deny, optional IP CIDR rules and VNet subnet rules. | <pre>object({<br>    default_action                = optional(string, "Deny")<br>    public_network_access_enabled = optional(bool, true)<br>    trusted_services_allowed      = optional(bool, true)<br>    ip_rules                      = optional(list(string), [])<br>    network_rules = optional(list(object({<br>      subnet_id                            = string<br>      ignore_missing_vnet_service_endpoint = optional(bool, false)<br>    })), [])<br>  })</pre> | `null` | no |
| premium\_messaging\_partitions | Number of messaging partitions (Premium only; e.g. 1, 2, 4). Null for Basic/Standard. | `number` | `null` | no |
| private\_endpoints | Map of Private Endpoints to create for the namespace (delegated to<br>../PrivateEndpoint, same pattern as SqlDatabase). The map key is arbitrary.<br>Each endpoint targets the namespace with sub-resource `namespace` and<br>resolves via `privatelink.servicebus.windows.net`. Requires the Premium SKU.<br><br>- `subnet_id`                     - (Required) Subnet ID where the PE NIC lands.<br>- `name`                          - (Optional) PE name. Defaults to `pe-{namespace}-{key}`.<br>- `private_dns_zone_ids`          - (Optional) Private DNS zone IDs for `privatelink.servicebus.windows.net`. Omit when DNS is wired by an ALZ DINE policy (the PrivateEndpoint module ignores drift on the zone group).<br>- `private_ip_address`            - (Optional) Static private IPv4 address (dynamic when null).<br>- `member_name`                   - (Optional) IP config member name. Defaults to "namespace" (the Service Bus PE group id).<br>- `custom_network_interface_name` - (Optional) Custom NIC name.<br>- `tags`                          - (Optional) Per-endpoint tags (merged over the module tags). | <pre>map(object({<br>    subnet_id                     = string<br>    name                          = optional(string)<br>    private_dns_zone_ids          = optional(list(string))<br>    private_ip_address            = optional(string)<br>    member_name                   = optional(string, "namespace")<br>    custom_network_interface_name = optional(string)<br>    tags                          = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| public\_network\_access\_enabled | Whether the namespace is reachable from the public internet. Default true. For a fully private namespace, use Premium + a Private Endpoint and set this false (Basic/Standard have no Private Endpoint). | `bool` | `true` | no |
| queues | Map of queues to create. Key is the queue name unless `name` is set. Null fields fall back to provider defaults. | <pre>map(object({<br>    name                                    = optional(string, null)<br>    max_size_in_megabytes                   = optional(number, null)<br>    max_message_size_in_kilobytes           = optional(number, null)<br>    max_delivery_count                      = optional(number, null)<br>    lock_duration                           = optional(string, null)<br>    default_message_ttl                     = optional(string, null)<br>    auto_delete_on_idle                     = optional(string, null)<br>    duplicate_detection_history_time_window = optional(string, null)<br>    requires_session                        = optional(bool, null)<br>    requires_duplicate_detection            = optional(bool, null)<br>    dead_lettering_on_message_expiration    = optional(bool, null)<br>    partitioning_enabled                    = optional(bool, null)<br>    batched_operations_enabled              = optional(bool, null)<br>    express_enabled                         = optional(bool, null)<br>    forward_to                              = optional(string, null)<br>    forward_dead_lettered_messages_to       = optional(string, null)<br>    status                                  = optional(string, null)<br>  }))</pre> | `{}` | no |
| region\_code | Region code (e.g. gwc, frc) | `string` | `null` | no |
| role\_assignments | Map of role assignments at the namespace scope (delegated to ../RoleAssignment). Common roles: 'Azure Service Bus Data Sender/Receiver/Owner'. Default principal\_type='ServicePrincipal'. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| sku | Namespace SKU: Basic, Standard, or Premium. Premium is required for Private Endpoints, CMK, zone redundancy and messaging partitions. | `string` | `"Standard"` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| topics | Map of topics to create (Standard/Premium only). Each topic may declare a map of subscriptions. Null fields fall back to provider defaults. | <pre>map(object({<br>    name                                    = optional(string, null)<br>    max_size_in_megabytes                   = optional(number, null)<br>    max_message_size_in_kilobytes           = optional(number, null)<br>    default_message_ttl                     = optional(string, null)<br>    auto_delete_on_idle                     = optional(string, null)<br>    duplicate_detection_history_time_window = optional(string, null)<br>    requires_duplicate_detection            = optional(bool, null)<br>    partitioning_enabled                    = optional(bool, null)<br>    batched_operations_enabled              = optional(bool, null)<br>    express_enabled                         = optional(bool, null)<br>    support_ordering                        = optional(bool, null)<br>    status                                  = optional(string, null)<br>    subscriptions = optional(map(object({<br>      name                                      = optional(string, null)<br>      max_delivery_count                        = optional(number, 10) # provider-required<br>      lock_duration                             = optional(string, null)<br>      default_message_ttl                       = optional(string, null)<br>      auto_delete_on_idle                       = optional(string, null)<br>      requires_session                          = optional(bool, null)<br>      dead_lettering_on_message_expiration      = optional(bool, null)<br>      dead_lettering_on_filter_evaluation_error = optional(bool, null)<br>      batched_operations_enabled                = optional(bool, null)<br>      forward_to                                = optional(string, null)<br>      forward_dead_lettered_messages_to         = optional(string, null)<br>      status                                    = optional(string, null)<br>    })), {})<br>  }))</pre> | `{}` | no |
| workload | Workload suffix (e.g. 01) | `string` | `"01"` | no |

## Outputs

| Name | Description |
|------|-------------|
| authorization\_rule\_ids | Map of namespace authorization rule name => ID |
| authorization\_rule\_primary\_connection\_strings | Map of namespace authorization rule name => primary connection string (sensitive). |
| default\_primary\_connection\_string | Default (RootManageSharedAccessKey) primary connection string. Empty when local\_auth\_enabled = false. |
| default\_primary\_key | Default (RootManageSharedAccessKey) primary key. Empty when local\_auth\_enabled = false. |
| endpoint | The Service Bus namespace endpoint URL |
| id | The ID of the Service Bus namespace |
| identity\_principal\_id | Principal ID of the namespace managed identity (null if no identity block). |
| identity\_tenant\_id | Tenant ID of the namespace managed identity (null if no identity block). |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | The name of the Service Bus namespace |
| private\_endpoint\_ids | Map of private endpoint key => Private Endpoint ID |
| private\_endpoint\_ips | Map of private endpoint key => private IP address |
| queue\_ids | Map of queue key => queue ID |
| role\_assignment\_ids | Map of role assignment logical key => role assignment ID |
| subscription\_ids | Map of 'topic/subscription' key => subscription ID |
| topic\_ids | Map of topic key => topic ID |
<!-- END_TF_DOCS -->
