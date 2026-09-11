# SqlDatabase

Deploys an Azure SQL **logical server** (`Microsoft.Sql/servers`) plus one or more **databases** (`azurerm_mssql_database`) — standalone or Hyperscale — and optional **elastic pools** (`azurerm_mssql_elasticpool`), wired secure-by-default:

- **Microsoft Entra-only authentication** by default (`azuread_authentication_only = true`) — SQL local auth disabled.
- **Public network access off** — expose the server over a **built-in Private Endpoint** (`private_endpoints`, sub-resource `sqlServer`).
- **TLS 1.2** minimum.
- **Transparent Data Encryption (TDE)** enabled on every database; optional Customer-Managed Key (CMK/BYOK).
- **Express Vulnerability Assessment** enabled (storage-less).
- **Point-in-time restore** kept 7 days by default; optional Long-Term Retention.
- Every database carries `prevent_destroy = true` to guard against accidental data loss.

### What you can deploy

| Capability | How |
|---|---|
| SQL logical server | Always created (`azurerm_mssql_server`) |
| Single databases | `databases` map entries |
| **Hyperscale** databases | A database with a `HS_*` SKU (e.g. `sku_name = "HS_Gen5_4"`, `read_replica_count`) |
| **Elastic pools** | `elastic_pools` map (`azurerm_mssql_elasticpool`); place databases via `elastic_pool_key` |
| Pre-existing external pool | A database with `elastic_pool_id` (full resource ID) |
| **Private Endpoint(s)** | `private_endpoints` map — delegated to the in-repo `PrivateEndpoint` module (sub-resource `sqlServer`) |

## Prerequisites

**A Microsoft Entra administrator.** With the secure default (`entra_administrator.azuread_authentication_only = true`) the server has **no** SQL local login. You must supply an `entra_administrator` (a user, group, or service principal `object_id`) that will own the server and create logins/users inside each database. Prefer an **Entra group** so membership — not a single identity — governs access.

If you need SQL authentication instead, set `entra_administrator.azuread_authentication_only = false` (or omit `entra_administrator`) and provide `administrator_login` + `administrator_login_password`. Source the password from Key Vault — it is stored in plain text in Terraform state.

## Usage

### Standalone

```hcl
module "sql" {
  source = "../SqlDatabase"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "billing"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-sql"

  # Entra-only auth (default). Prefer a group object_id.
  entra_administrator = {
    login_username = "sg-sql-admins"
    object_id      = "00000000-0000-0000-0000-000000000000"
  }

  public_network_access_enabled = false
  minimum_tls_version           = "1.2"

  databases = {
    invoices = {
      sku_name    = "GP_S_Gen5_2" # General Purpose serverless
      max_size_gb = 32
      long_term_retention_policy = {
        weekly_retention  = "P4W"
        monthly_retention = "P12M"
        yearly_retention  = "P5Y"
        week_of_year      = 1
      }
    }
    reporting = {
      sku_name       = "BC_Gen5_2" # Business Critical
      max_size_gb    = 64
      zone_redundant = true
      read_scale     = true
    }
  }

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Elastic pools + Hyperscale

```hcl
module "sql" {
  source = "../SqlDatabase"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "billing"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-sql"

  entra_administrator = {
    login_username = "sg-sql-admins"
    object_id      = "00000000-0000-0000-0000-000000000000"
  }

  # Create an elastic pool on the server.
  elastic_pools = {
    pool-gp = {
      sku                   = { name = "GP_Gen5", tier = "GeneralPurpose", capacity = 4 }
      per_database_settings = { min_capacity = 0, max_capacity = 2 }
      max_size_gb           = 256
    }
  }

  databases = {
    # Pooled databases (share pool-gp capacity).
    app1 = { elastic_pool_key = "pool-gp" }
    app2 = { elastic_pool_key = "pool-gp" }

    # Standalone Hyperscale database with readonly replicas.
    analytics = {
      sku_name           = "HS_Gen5_4"
      read_replica_count = 2
      zone_redundant     = true
    }
  }
}
```

> A database is **either** pooled (`elastic_pool_key` / `elastic_pool_id`) **or** standalone with its own `sku_name` — not both. Pooled databases inherit their compute from the pool.

### Private Endpoint (private connectivity)

```hcl
module "sql" {
  source = "../SqlDatabase"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "billing"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-sql"

  entra_administrator = {
    login_username = "sg-sql-admins"
    object_id      = "00000000-0000-0000-0000-000000000000"
  }

  public_network_access_enabled = false # default — reach the server privately only

  private_endpoints = {
    primary = {
      subnet_id            = "/subscriptions/.../virtualNetworks/vnet-1/subnets/snet-pe"
      private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.database.windows.net"]
      # name / private_ip_address optional
    }
  }

  databases = { app = { sku_name = "GP_S_Gen5_2", max_size_gb = 32 } }
}
```

> Always connect clients to `<server>.database.windows.net` (not the `privatelink` FQDN or the IP) — the private endpoint routes that name to the regional SQL gateway. Omit `private_dns_zone_ids` if an ALZ DINE policy wires DNS for you (the PrivateEndpoint module ignores drift on the zone group).

### TDE with a Customer-Managed Key (CMK/BYOK)

```hcl
module "sql" {
  source = "../SqlDatabase"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "billing"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-sql"

  entra_administrator = {
    login_username = "sg-sql-admins"
    object_id      = "00000000-0000-0000-0000-000000000000"
  }

  # User-assigned identity must have Get/WrapKey/UnwrapKey on the Key Vault key.
  identity = {
    type         = "UserAssigned"
    identity_ids = ["/subscriptions/.../userAssignedIdentities/uami-sql"]
  }
  primary_user_assigned_identity_id            = "/subscriptions/.../userAssignedIdentities/uami-sql"
  transparent_data_encryption_key_vault_key_id = "https://my-kv.vault.azure.net/keys/sql-cmk/<version>"

  databases = { app = { sku_name = "GP_S_Gen5_2", max_size_gb = 32 } }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/SqlDatabase"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "billing"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name

  entra_administrator = {
    login_username = "sg-sql-admins"
    object_id      = dependency.sql_admins_group.outputs.object_id
  }

  databases = {
    app = { sku_name = "GP_S_Gen5_2", max_size_gb = 32 }
  }

  tags = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Explicit SQL server name (1-63 chars, globally unique). If null, computed. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. api, mgm) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name (server name is global — keep unique) | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| server_version | SQL server version (`12.0` or `2.0`) | `string` | `"12.0"` | No |
| minimum_tls_version | Minimum TLS (`1.0`/`1.1`/`1.2`/`Disabled`) | `string` | `"1.2"` | No |
| public_network_access_enabled | Allow public network access | `bool` | `false` | No |
| outbound_network_restriction_enabled | Restrict outbound traffic | `bool` | `false` | No |
| connection_policy | `Default`/`Proxy`/`Redirect` | `string` | `"Default"` | No |
| express_vulnerability_assessment_enabled | Enable Express Vulnerability Assessment | `bool` | `true` | No |
| entra_administrator | Entra (Azure AD) admin block (`azuread_authentication_only` defaults true) | `object({...})` | `null` | No |
| administrator_login | SQL auth admin login (when Entra-only off) | `string` | `null` | No |
| administrator_login_password | SQL auth admin password (sensitive) | `string` | `null` | No |
| identity | Managed identity (`SystemAssigned` default) | `object({ type = string, identity_ids = optional(list(string), []) })` | `{ type = "SystemAssigned" }` | No |
| primary_user_assigned_identity_id | Primary UAMI id (required for UserAssigned) | `string` | `null` | No |
| transparent_data_encryption_key_vault_key_id | Server-level TDE CMK key URL | `string` | `null` | No |
| allow_azure_services | Create the 0.0.0.0 "allow Azure services" firewall rule | `bool` | `false` | No |
| firewall_rules | Map of `{ start_ip_address, end_ip_address }` rules | `map(object({...}))` | `{}` | No |
| private_endpoints | Map of Private Endpoints (subnet_id + optional DNS zone/IP/name) | `map(object({...}))` | `{}` | No |
| elastic_pools | Map of elastic pools to create (sku + per_database_settings, see variable docs) | `map(object({...}))` | `{}` | No |
| databases | Map of databases to create (see variable docs) | `map(object({...}))` | `{}` | No |
| role_assignments | Map of role assignments on the server. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| lock | Management lock (`CanNotDelete` or `ReadOnly`) | `object({ kind = string, name = optional(string) })` | `null` | No |
| tags | Tags applied to the server and databases | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| server_id | The SQL logical server resource ID |
| server_name | The SQL logical server name |
| fully_qualified_domain_name | FQDN (`<name>.database.windows.net`) |
| identity_principal_id | System-assigned identity principal ID (null if none) |
| identity_tenant_id | Managed identity tenant ID (null if none) |
| database_ids | Map of database key => resource ID |
| database_names | Map of database key => database name |
| elastic_pool_ids | Map of elastic pool key => resource ID |
| elastic_pools | Map of elastic pool key => complete pool resource object |
| private_endpoint_ids | Map of private endpoint key => Private Endpoint resource ID |
| private_endpoint_ip_addresses | Map of private endpoint key => assigned private IP address |
| server | Complete SQL server resource object |
| databases | Map of database key => complete database resource object |

## Notes

- **Global name uniqueness.** The computed `sql-{acr}-{env}-{region}-{workload}` name is deterministic and must be globally unique across Azure (it forms the public FQDN). Keep `workload` distinctive, or pass an explicit `name`.
- **Private connectivity.** With `public_network_access_enabled = false`, define one or more `private_endpoints` (sub-resource `sqlServer`, DNS zone `privatelink.database.windows.net`). This is delegated to the in-repo `PrivateEndpoint` module — one module instance per endpoint, so each can land in its own subnet.
- **CMK/BYOK requirements.** The Key Vault must have soft-delete and purge protection enabled and live in the **same tenant** as the server's user-assigned identity, which needs `Get`, `WrapKey`, `UnwrapKey` on the key.

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| private\_endpoint | ../PrivateEndpoint | n/a |
| role\_assignments | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_monitor_diagnostic_setting.sql_audit](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_mssql_database.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_database) | resource |
| [azurerm_mssql_elasticpool.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_elasticpool) | resource |
| [azurerm_mssql_firewall_rule.allow_azure_services](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_firewall_rule) | resource |
| [azurerm_mssql_firewall_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_firewall_rule) | resource |
| [azurerm_mssql_server.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_server) | resource |
| [azurerm_mssql_server_extended_auditing_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_server_extended_auditing_policy) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region where the SQL server will be deployed | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| administrator\_login | SQL authentication administrator login. Only used when Entra-only authentication is disabled. Prefer Entra-only auth. | `string` | `null` | no |
| administrator\_login\_password | Password for `administrator_login`. Only used when Entra-only authentication is disabled. Source it from Key Vault — it is stored in plain text in state. | `string` | `null` | no |
| allow\_azure\_services | Create the special 0.0.0.0 firewall rule that allows Azure services and resources to access this server. Secure default is false. | `bool` | `false` | no |
| auditing | Server extended auditing policy configuration (CKV\_AZURE\_23 / CKV\_AZURE\_24).<br><br>- `enabled`                         - (Optional) Master switch. Defaults to true.<br>- `retention_in_days`               - (Optional) Log retention in days. Must be >= 90. Defaults to 90.<br>- `log_analytics_workspace_id`      - (Optional) LAW ARM resource ID. When set, audit events are routed to Azure Monitor (log\_monitoring\_enabled = true) and a Diagnostic Setting is created on the server `master` database (category SQLSecurityAuditEvents). RECOMMENDED destination.<br>- `log_monitoring_enabled`          - (Optional) Send audit events to Azure Monitor. Forced to true when `log_analytics_workspace_id` is set. Defaults to true.<br>- `storage_endpoint`               - (Optional) Blob storage endpoint (https://<account>.blob.core.windows.net) for storage-based auditing. Storage auth uses the server managed identity.<br>- `storage_account_subscription_id` - (Optional) Subscription ID of the auditing storage account when it differs from the server subscription.<br>- `audit_actions_and_groups`        - (Optional) Actions/action-groups to audit. Provider default when null.<br>- `predicate_expression`            - (Optional) WHERE clause to filter audited events.<br>- `diagnostic_setting_name`         - (Optional) Name of the master-database Diagnostic Setting created for the Azure Monitor route. Defaults to "sqlaudit-to-law". | <pre>object({<br>    enabled                         = optional(bool, true)<br>    retention_in_days               = optional(number, 90)<br>    log_analytics_workspace_id      = optional(string)<br>    log_monitoring_enabled          = optional(bool, true)<br>    storage_endpoint                = optional(string)<br>    storage_account_subscription_id = optional(string)<br>    audit_actions_and_groups        = optional(list(string))<br>    predicate_expression            = optional(string)<br>    diagnostic_setting_name         = optional(string, "sqlaudit-to-law")<br>  })</pre> | `{}` | no |
| connection\_policy | Connection policy the server will use. Possible values: 'Default', 'Proxy', 'Redirect'. | `string` | `"Default"` | no |
| databases | A map of databases to create on this server. The map key is used as the database<br>name unless `name` is set. Every database is created with `prevent_destroy = true`<br>to guard against accidental data loss.<br><br>Common fields (all optional unless noted):<br>- `name`                 - Database name (defaults to the map key).<br>- `sku_name`             - SKU (e.g. 'GP\_S\_Gen5\_2', 'S0', 'BC\_Gen5\_2', 'HS\_Gen5\_2'). Defaults to 'GP\_S\_Gen5\_2' (General Purpose serverless).<br>- `collation`            - Database collation. Defaults to 'SQL\_Latin1\_General\_CP1\_CI\_AS'.<br>- `max_size_gb`          - Max size in GB.<br>- `license_type`         - 'LicenseIncluded' or 'BasePrice'.<br>- `zone_redundant`       - Spread replicas across availability zones. OPT-IN, defaults to false (CKV\_AZURE\_229). Set true where supported; fails at apply on Basic/Standard S0-S2 SKUs, non-AZ regions, or pooled DBs whose pool is not zone-redundant.<br>- `read_scale`           - Route readonly intent to a replica (Premium / Business Critical).<br>- `read_replica_count`   - Hyperscale readonly replica count.<br>- `auto_pause_delay_in_minutes` / `min_capacity` - Serverless only.<br>- `storage_account_type` - Backup storage redundancy: 'Geo' (default), 'GeoZone', 'Local', 'Zone'.<br>- `geo_backup_enabled`   - DataWarehouse SKUs only.<br>- `maintenance_configuration_name` - Public maintenance window.<br>- `ledger_enabled`       - Create as a ledger (tamper-evident) database. OPT-IN, defaults to false (CKV\_AZURE\_224). IRREVERSIBLE — cannot be turned off after creation. Set true for workloads needing cryptographic proof / non-repudiation.<br>- `enclave_type`         - 'Default' or 'VBS' (Always Encrypted secure enclaves).<br>- `transparent_data_encryption_enabled` - TDE at-rest. Defaults to true.<br>- `transparent_data_encryption_key_vault_key_id` / `transparent_data_encryption_key_automatic_rotation_enabled` - Database-level CMK.<br>- `create_mode` / `creation_source_database_id` - Advanced placement / restore.<br>- `elastic_pool_key` - Place this database into a pool created by this module (key in `elastic_pools`). Mutually exclusive with `elastic_pool_id`.<br>- `elastic_pool_id`  - Place this database into a pre-existing external elastic pool (full resource ID).<br>- `short_term_retention_days` (1-35, default 7) / `backup_interval_in_hours` (12 or 24) - PITR.<br>- `long_term_retention_policy` - LTR (weekly/monthly/yearly ISO-8601 retention).<br>- `tags`                 - Per-database tags (merged over the module tags). | <pre>map(object({<br>    name         = optional(string)<br>    sku_name     = optional(string, "GP_S_Gen5_2")<br>    collation    = optional(string, "SQL_Latin1_General_CP1_CI_AS")<br>    max_size_gb  = optional(number)<br>    license_type = optional(string)<br>    # OPT-IN (CKV_AZURE_229). Default false: zone redundancy fails at apply on<br>    # SKUs/regions without Availability Zone support (Basic, Standard S0-S2,<br>    # non-AZ regions) and on pooled DBs whose pool is not itself zone-redundant.<br>    # Set true per-database to enable the resilient path where supported.<br>    zone_redundant                 = optional(bool, false)<br>    read_scale                     = optional(bool)<br>    read_replica_count             = optional(number)<br>    auto_pause_delay_in_minutes    = optional(number)<br>    min_capacity                   = optional(number)<br>    storage_account_type           = optional(string)<br>    geo_backup_enabled             = optional(bool)<br>    maintenance_configuration_name = optional(string)<br>    # OPT-IN (CKV_AZURE_224). Default false because ledger is IRREVERSIBLE — it<br>    # cannot be disabled after creation and cannot be applied to an existing<br>    # non-ledger database (forces replacement, and these DBs carry prevent_destroy).<br>    # Set true per-database for workloads needing cryptographic proof / non-repudiation.<br>    ledger_enabled                                             = optional(bool, false)<br>    enclave_type                                               = optional(string)<br>    create_mode                                                = optional(string)<br>    creation_source_database_id                                = optional(string)<br>    elastic_pool_id                                            = optional(string)<br>    elastic_pool_key                                           = optional(string)<br>    transparent_data_encryption_enabled                        = optional(bool, true)<br>    transparent_data_encryption_key_vault_key_id               = optional(string)<br>    transparent_data_encryption_key_automatic_rotation_enabled = optional(bool)<br>    short_term_retention_days                                  = optional(number, 7)<br>    backup_interval_in_hours                                   = optional(number)<br>    long_term_retention_policy = optional(object({<br>      weekly_retention          = optional(string)<br>      monthly_retention         = optional(string)<br>      yearly_retention          = optional(string)<br>      week_of_year              = optional(number)<br>      immutable_backups_enabled = optional(bool)<br>    }))<br>    tags = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| elastic\_pools | A map of elastic pools to create on this server. The map key is used as the pool<br>name unless `name` is set. Reference a pool from a database entry via its<br>`elastic_pool_key`.<br><br>- `name`                  - Pool name (defaults to the map key).<br>- `sku`                   - (Required) Compute SKU of the pool:<br>    - `name`     - (Required) e.g. 'GP\_Gen5', 'BC\_Gen5', 'HS\_Gen5', 'StandardPool', 'PremiumPool'.<br>    - `tier`     - (Required) 'GeneralPurpose', 'BusinessCritical', 'Hyperscale', 'Basic', 'Standard', 'Premium'.<br>    - `capacity` - (Required) Pool compute units (vCores or DTUs).<br>    - `family`   - (Optional) Hardware family: 'Gen4', 'Gen5', 'Fsv2', 'DC', 'PRMS', 'MOPRMS'.<br>- `per_database_settings` - (Required) Per-database min/max capacity guaranteed/allowed in the pool.<br>- `max_size_gb` / `max_size_bytes` - Exactly one must be set (pool data cap).<br>- `maintenance_configuration_name` - Public maintenance window.<br>- `enclave_type`          - 'Default' or 'VBS'. All pooled databases must match.<br>- `zone_redundant`        - Premium (DTU) / Business Critical (vCore) only.<br>- `license_type`          - 'LicenseIncluded' or 'BasePrice'.<br>- `high_availability_replica_count` - Hyperscale tier only (0-4).<br>- `tags`                  - Per-pool tags (merged over the module tags). | <pre>map(object({<br>    name = optional(string)<br>    sku = object({<br>      name     = string<br>      tier     = string<br>      capacity = number<br>      family   = optional(string)<br>    })<br>    per_database_settings = object({<br>      min_capacity = number<br>      max_capacity = number<br>    })<br>    max_size_gb                     = optional(number)<br>    max_size_bytes                  = optional(number)<br>    maintenance_configuration_name  = optional(string)<br>    enclave_type                    = optional(string)<br>    zone_redundant                  = optional(bool)<br>    license_type                    = optional(string)<br>    high_availability_replica_count = optional(number)<br>    tags                            = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| entra\_administrator | Microsoft Entra (Azure AD) administrator for the SQL server. Recommended for all<br>deployments — centralises identity and supports `azuread_authentication_only`.<br><br>- `login_username`               - (Required) Display name of the Entra principal (user/group/SP).<br>- `object_id`                    - (Required) Object ID of the Entra principal.<br>- `tenant_id`                    - (Optional) Tenant ID of the principal (defaults to the server tenant).<br>- `azuread_authentication_only`  - (Optional) When true, only Entra principals can log in (SQL auth disabled). Defaults to true. | <pre>object({<br>    login_username              = string<br>    object_id                   = string<br>    tenant_id                   = optional(string)<br>    azuread_authentication_only = optional(bool, true)<br>  })</pre> | `null` | no |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| express\_vulnerability\_assessment\_enabled | Enable the Express (storage-less) SQL Vulnerability Assessment configuration. Secure default is true. | `bool` | `true` | no |
| firewall\_rules | A map of SQL server firewall rules. The map key is the rule name.<br><br>- `start_ip_address` - (Required) Start of the allowed IPv4 range.<br>- `end_ip_address`   - (Required) End of the allowed IPv4 range. | <pre>map(object({<br>    start_ip_address = string<br>    end_ip_address   = string<br>  }))</pre> | `{}` | no |
| identity | Managed identity configuration for the SQL server.<br><br>- `type`         - (Required) 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'.<br>- `identity_ids` - (Optional) User Assigned Managed Identity IDs. Required when `type` includes 'UserAssigned'. | <pre>object({<br>    type         = string<br>    identity_ids = optional(list(string), [])<br>  })</pre> | <pre>{<br>  "type": "SystemAssigned"<br>}</pre> | no |
| lock | Controls the Resource Lock configuration for this server.<br><br>- `kind` - (Required) The type of lock. Possible values are "CanNotDelete" and "ReadOnly".<br>- `name` - (Optional) The name of the lock. If not specified, generated from the kind value. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| minimum\_tls\_version | Minimum TLS version for all databases on this server. Valid values: '1.0', '1.1', '1.2', 'Disabled'. Secure default is '1.2'. | `string` | `"1.2"` | no |
| name | Optional. Explicit SQL logical server name (1-63 chars, globally unique). If null, computed from naming components (sql-{acr}-{env}-{region}-{workload}). | `string` | `null` | no |
| outbound\_network\_restriction\_enabled | Whether outbound network traffic is restricted for this server. | `bool` | `false` | no |
| primary\_user\_assigned\_identity\_id | Primary user-assigned managed identity ID. Required when identity.type includes 'UserAssigned'. | `string` | `null` | no |
| private\_endpoints | A map of Private Endpoints to create for this SQL logical server. The map key is<br>arbitrary. Each endpoint targets the server with sub-resource `sqlServer` and resolves<br>to `<server>.privatelink.database.windows.net`.<br><br>- `subnet_id`                     - (Required) Subnet ID where the Private Endpoint NIC lands.<br>- `name`                          - (Optional) PE name. Defaults to `pe-{server_name}-{key}`.<br>- `private_dns_zone_ids`          - (Optional) Private DNS zone IDs for `privatelink.database.windows.net`. Omit when DNS is wired by an ALZ DINE policy (the PrivateEndpoint module ignores drift on the zone group).<br>- `private_ip_address`            - (Optional) Static private IPv4 address (dynamic when null).<br>- `member_name`                   - (Optional) IP config member name. Defaults to "default".<br>- `custom_network_interface_name` - (Optional) Custom NIC name.<br>- `tags`                          - (Optional) Per-endpoint tags (merged over the module tags). | <pre>map(object({<br>    subnet_id                     = string<br>    name                          = optional(string)<br>    private_dns_zone_ids          = optional(list(string))<br>    private_ip_address            = optional(string)<br>    member_name                   = optional(string, "default")<br>    custom_network_interface_name = optional(string)<br>    tags                          = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| public\_network\_access\_enabled | Whether public network access is allowed. Secure default is false — connect via the separate PrivateEndpoint module. | `bool` | `false` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | A map of role assignments to create on this SQL server. The map key is arbitrary.<br><br>- `role_definition_id_or_name`             - (Required) The ID or name of the role definition.<br>- `principal_id`                           - (Required) The ID of the principal to assign the role to.<br>- `principal_type`                         - (Optional) User, Group or ServicePrincipal.<br>- `condition`                              - (Optional) ABAC condition.<br>- `condition_version`                      - (Optional) Condition version ("1.0" or "2.0").<br>- `description`                            - (Optional) Description of the role assignment.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check for the service principal.<br>- `delegated_managed_identity_resource_id` - (Optional) Delegated managed identity for cross-tenant scenarios. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    principal_id                           = string<br>    principal_type                         = optional(string)<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    description                            = optional(string)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string)<br>  }))</pre> | `{}` | no |
| server\_version | The version for the SQL logical server. Valid values: '12.0' (v12) or '2.0' (v11). | `string` | `"12.0"` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, con, api) | `string` | `null` | no |
| tags | Tags to apply to the SQL server and databases | `map(string)` | `{}` | no |
| transparent\_data\_encryption\_key\_vault\_key\_id | Fully versioned Key Vault Key URL for TDE with a Customer-Managed Key (CMK/BYOK) at the server level. The KV must have soft-delete and purge protection enabled and share the server's tenant. | `string` | `null` | no |
| workload | Workload name for naming convention. Keep short and unique (server name is global). | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| auditing\_enabled | Whether server extended auditing was actually created (requires a Log Analytics workspace or storage endpoint). |
| auditing\_policy\_id | The SQL server extended auditing policy resource ID (null when no auditing destination was supplied). |
| database\_ids | Map of database key => database resource ID. |
| database\_names | Map of database key => database name. |
| databases | Map of database key => complete database resource object. |
| elastic\_pool\_ids | Map of elastic pool key => elastic pool resource ID. |
| elastic\_pools | Map of elastic pool key => complete elastic pool resource object. |
| fully\_qualified\_domain\_name | The fully qualified domain name of the SQL server (e.g. <name>.database.windows.net) |
| identity\_principal\_id | The system-assigned managed identity principal ID of the SQL server (null when no system-assigned identity). |
| identity\_tenant\_id | The tenant ID of the SQL server managed identity (null when no system-assigned identity). |
| private\_endpoint\_ids | Map of private endpoint key => Private Endpoint resource ID. |
| private\_endpoint\_ip\_addresses | Map of private endpoint key => assigned private IP address. |
| server | The complete SQL logical server resource object. |
| server\_id | The SQL logical server resource ID |
| server\_name | The SQL logical server name |
<!-- END_TF_DOCS -->
