# PostgreSqlFlexible

Creates an **Azure Database for PostgreSQL Flexible Server** (`Microsoft.DBforPostgreSQL/flexibleServers`) with databases, firewall rules, server parameters, optional **Private Endpoints**, identity/CMK, lock and RBAC. (Single Server is retired — Flexible Server is the GA offering.)

## Networking — choose ONE model

- **A. VNet integration (private access)** — set `delegated_subnet_id` (subnet delegated to `Microsoft.DBforPostgreSQL/flexibleServers`) **and** `private_dns_zone_id` (a zone ending in `postgres.database.azure.com`). No public endpoint. Immutable after create.
- **B. Public access + Private Endpoint** — leave `delegated_subnet_id` null, manage `public_network_access_enabled`, and declare `private_endpoints` (embedded `../PrivateEndpoint`, sub-resource `postgresqlServer`, DNS zone `privatelink.postgres.database.azure.com`).

The two are mutually exclusive (enforced by a precondition).

## Usage (VNet integration)

```hcl
module "postgres" {
  source = "../PostgreSqlFlexible"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "frc"
  workload             = "01"
  location             = "francecentral"
  resource_group_name  = "rg-mgm-prod-frc-data"

  postgresql_version = "16"
  sku_name           = "GP_Standard_D2s_v3"
  storage_mb         = 32768

  administrator_login    = "pgadmin"
  administrator_password = var.pg_admin_password # from Key Vault

  delegated_subnet_id = dependency.subnet.outputs.id
  private_dns_zone_id = dependency.dns.outputs.postgres_zone_id

  databases = { app = { charset = "UTF8", collation = "en_US.utf8" } }
  configurations = { require_secure_transport = "on" }

  tags = { Environment = "Production" }
}
```

## Usage (public + Private Endpoint)

```hcl
  public_network_access_enabled = false
  private_endpoints = {
    pg = {
      subnet_id            = dependency.pe_subnet.outputs.id
      private_dns_zone_ids = [dependency.dns.outputs.postgres_zone_id]
    }
  }
```

## Notes

- **Admin**: SQL login+password and/or Entra auth (`authentication.active_directory_auth_enabled = true`) — at least one is required (precondition).
- **TLS**: Flexible Server enforces TLS by default; tune `require_secure_transport` / `ssl_min_protocol_version` via `configurations`.
- **`prevent_destroy`** on the server and databases (stateful).
- **CMK**: enable `identity` (UserAssigned) + `customer_managed_key`.
- **Checkov**: CKV_AZURE_136 (geo-redundant backups) is `checkov:skip`-annotated with justification — the capability is exposed via `geo_redundant_backup_enabled` but not forced by default (immutable after create, cost, unsupported on Burstable/some regions). Enable per prod workload.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs (summary)

| Name | Description | Type | Default |
|------|-------------|------|---------|
| name / subscription_acronym / environment / region_code / workload | Naming (psql-{sub}-{env}-{region}-{workload}). | `string` | see vars |
| location, resource_group_name | Required placement. | `string` | -- |
| postgresql_version | Major version (11-17). | `string` | `"16"` |
| sku_name | B_/GP_/MO_ SKU. | `string` | `"GP_Standard_D2s_v3"` |
| storage_mb / storage_tier / auto_grow_enabled | Storage. | mixed | 32768 / null / true |
| backup_retention_days / geo_redundant_backup_enabled | Backups. | mixed | 7 / false |
| administrator_login / administrator_password | SQL admin (**password sensitive**). | `string` | null |
| authentication | password/AAD auth toggles. | `object` | null |
| delegated_subnet_id / private_dns_zone_id / public_network_access_enabled | Networking. | mixed | null |
| high_availability / maintenance_window / zone | Availability. | mixed | null |
| identity / customer_managed_key | UAMI + CMK. | `object` | null |
| databases / firewall_rules / configurations | Entities. | `map` | {} |
| private_endpoints | Embedded PE map (public-access mode). | `map(object)` | {} |
| lock / role_assignments / tags | Governance. | mixed | null / {} / {} |

## Outputs

| Name | Description |
|------|-------------|
| id / name / fqdn | Server identity |
| identity_principal_id | UAMI principal (null if none) |
| database_ids | Map of database key => ID |
| private_endpoint_ids / private_endpoint_ips | PE maps |
| resource | Complete resource object (**sensitive**) |
| lock_id | Lock ID (null if no lock) |
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
| [azurerm_postgresql_flexible_server.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server) | resource |
| [azurerm_postgresql_flexible_server_configuration.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_configuration) | resource |
| [azurerm_postgresql_flexible_server_database.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_database) | resource |
| [azurerm_postgresql_flexible_server_firewall_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server_firewall_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| administrator\_login | SQL administrator login. Required unless Entra-only auth (authentication.password\_auth\_enabled=false + active\_directory\_auth\_enabled=true). Immutable after create. | `string` | `null` | no |
| administrator\_password | SQL administrator password. Required when administrator\_login is set. Prefer sourcing from Key Vault. | `string` | `null` | no |
| authentication | Authentication modes. Set active\_directory\_auth\_enabled=true for Entra auth; password\_auth\_enabled=false to disable SQL password auth (Entra-only). | <pre>object({<br>    password_auth_enabled         = optional(bool, true)<br>    active_directory_auth_enabled = optional(bool, false)<br>    tenant_id                     = optional(string, null)<br>  })</pre> | `null` | no |
| auto\_grow\_enabled | Auto-grow storage when near capacity. Default true (avoids out-of-storage outages). | `bool` | `true` | no |
| backup\_retention\_days | Backup retention in days (7-35). | `number` | `7` | no |
| configurations | Map of server parameters (name => value), e.g. { require\_secure\_transport = "on", log\_min\_duration\_statement = "1000" }. | `map(string)` | `{}` | no |
| create\_mode | Create mode: Default, PointInTimeRestore, Replica, Update. Null = Default. | `string` | `null` | no |
| customer\_managed\_key | Optional CMK encryption. Requires a user-assigned identity (var.identity) with access to the Key Vault key. | <pre>object({<br>    key_vault_key_id                     = string<br>    primary_user_assigned_identity_id    = optional(string, null)<br>    geo_backup_key_vault_key_id          = optional(string, null)<br>    geo_backup_user_assigned_identity_id = optional(string, null)<br>  })</pre> | `null` | no |
| databases | Map of databases to create. Key is the database name unless `name` is set. | <pre>map(object({<br>    name      = optional(string, null)<br>    charset   = optional(string, "UTF8")<br>    collation = optional(string, "en_US.utf8")<br>  }))</pre> | `{}` | no |
| delegated\_subnet\_id | VNet-integration mode. Resource ID of the subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. Requires private\_dns\_zone\_id. Immutable after create. | `string` | `null` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| firewall\_rules | Map of firewall rules (public-access mode). Key is the rule name. | <pre>map(object({<br>    start_ip_address = string<br>    end_ip_address   = string<br>  }))</pre> | `{}` | no |
| geo\_redundant\_backup\_enabled | Geo-redundant backups. Opt-in (default false): immutable after create and adds cost. | `bool` | `false` | no |
| high\_availability | Optional high availability. mode = ZoneRedundant \| SameZone. | <pre>object({<br>    mode                      = string<br>    standby_availability_zone = optional(string, null)<br>  })</pre> | `null` | no |
| identity | Optional user-assigned identity (required for CMK). type must be UserAssigned. | <pre>object({<br>    type         = string<br>    identity_ids = list(string)<br>  })</pre> | `null` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the server. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| maintenance\_window | Optional maintenance window (UTC). day\_of\_week 0-6 (0=Sunday). | <pre>object({<br>    day_of_week  = optional(number, 0)<br>    start_hour   = optional(number, 0)<br>    start_minute = optional(number, 0)<br>  })</pre> | `null` | no |
| name | Optional. Explicit server name. If null, computed (psql-{sub}-{env}-{region}-{workload}). Globally unique, 3-63 lowercase alphanumerics/hyphens. | `string` | `null` | no |
| postgresql\_version | PostgreSQL major version. | `string` | `"16"` | no |
| private\_dns\_zone\_id | Private DNS zone ID for VNet-integration mode (privatelink.postgres.database.azure.com, or any zone ending in postgres.database.azure.com). Mandatory when delegated\_subnet\_id is set. | `string` | `null` | no |
| private\_endpoints | Map of Private Endpoints (public-access mode) delegated to ../PrivateEndpoint.<br>Each endpoint targets the server with sub-resource `postgresqlServer` and<br>resolves via `privatelink.postgres.database.azure.com`. Do NOT combine with<br>delegated\_subnet\_id (VNet integration already provides private access).<br><br>- `subnet_id`                     - (Required) Subnet ID where the PE NIC lands.<br>- `name`                          - (Optional) PE name. Defaults to `pe-{server}-{key}`.<br>- `private_dns_zone_ids`          - (Optional) Private DNS zone IDs for privatelink.postgres.database.azure.com.<br>- `private_ip_address`            - (Optional) Static private IPv4 (dynamic when null).<br>- `member_name`                   - (Optional) IP config member name. Defaults to "postgresqlServer".<br>- `custom_network_interface_name` - (Optional) Custom NIC name.<br>- `tags`                          - (Optional) Per-endpoint tags. | <pre>map(object({<br>    subnet_id                     = string<br>    name                          = optional(string)<br>    private_dns_zone_ids          = optional(list(string))<br>    private_ip_address            = optional(string)<br>    member_name                   = optional(string, "postgresqlServer")<br>    custom_network_interface_name = optional(string)<br>    tags                          = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| public\_network\_access\_enabled | Public network access. Null = provider default. Must be omitted/false with delegated\_subnet\_id (VNet integration). For public+PE, set as needed. | `bool` | `null` | no |
| region\_code | Region code (e.g. gwc, frc) | `string` | `null` | no |
| role\_assignments | Map of role assignments at the server scope (delegated to ../RoleAssignment). Default principal\_type='ServicePrincipal'. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| sku\_name | Compute SKU. Prefix B\_ (Burstable), GP\_ (General Purpose) or MO\_ (Memory Optimized), e.g. GP\_Standard\_D2s\_v3, B\_Standard\_B1ms. | `string` | `"GP_Standard_D2s_v3"` | no |
| storage\_mb | Storage size in MB (e.g. 32768 = 32 GB). Allowed tiers per MS docs (32768, 65536, 131072, ...). | `number` | `32768` | no |
| storage\_tier | Optional storage performance tier (e.g. P4, P6, P10...). Null = provider default for the storage size. | `string` | `null` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| workload | Workload suffix (e.g. 01) | `string` | `"01"` | no |
| zone | Availability zone for the primary (1/2/3). Null = platform choice. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| database\_ids | Map of database key => database ID |
| fqdn | The fully qualified domain name of the server |
| id | The ID of the PostgreSQL Flexible Server |
| identity\_principal\_id | Principal ID of the server managed identity (null if no identity block). |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | The name of the PostgreSQL Flexible Server |
| private\_endpoint\_ids | Map of private endpoint key => Private Endpoint ID |
| private\_endpoint\_ips | Map of private endpoint key => private IP address |
| resource | The complete PostgreSQL Flexible Server resource object (sensitive: carries the admin password). |
| role\_assignment\_ids | Map of role assignment logical key => role assignment ID |
<!-- END_TF_DOCS -->
