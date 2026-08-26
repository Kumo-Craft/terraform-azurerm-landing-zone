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
