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
