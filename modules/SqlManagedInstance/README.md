# SqlManagedInstance

Creates an **Azure SQL Managed Instance** (`Microsoft.Sql/managedInstances`), secure-by-default (private-only data endpoint, TLS 1.2), with optional Entra admin, managed identity, lock and RBAC.

## Network prerequisite (not created by this module)

SQL MI can **only** be deployed into a **dedicated subnet** that is:

- **delegated** to `Microsoft.Sql/managedInstances`,
- associated with a **network security group** and a **route table** (service-aided configuration),
- sized for at least **32 IP addresses** (`/27` minimum; larger recommended).

The caller provides this subnet via `subnet_id`. See [SQL MI connectivity architecture](https://learn.microsoft.com/azure/azure-sql/managed-instance/connectivity-architecture-overview#network-requirements).

## Usage

```hcl
module "sql_managed_instance" {
  source = "../SqlManagedInstance"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "frc"
  workload             = "01"
  location             = "francecentral"
  resource_group_name  = "rg-mgm-prod-frc-sqlmi"

  subnet_id = dependency.subnet.outputs.id # dedicated, delegated subnet

  sku_name           = "GP_Gen5"
  vcores             = 4
  storage_size_in_gb = 32
  license_type       = "LicenseIncluded"

  # Entra-only admin (no SQL password); or set administrator_login + _password.
  entra_administrator = {
    login_username                      = "sql-admins"
    object_id                           = "00000000-0000-0000-0000-000000000000"
    principal_type                      = "Group"
    azuread_authentication_only_enabled = true
  }

  tags = { Environment = "Production" }
}
```

## Notes

- **At least one administrator is required** — SQL admin (`administrator_login` + `administrator_login_password`) and/or `entra_administrator`. Enforced by a precondition.
- **`prevent_destroy = true`** — the MI holds data and takes hours to (re)provision. Removing it requires editing the module.
- **Backups**: `storage_account_type` defaults to `GRS` (geo-redundant). `zone_redundant_enabled` is opt-in (tier/region dependent, adds cost).
- **CMK / TDE with your own key**: enable a `SystemAssigned` `identity`, grant it on the Key Vault, then wire the key at the database level (or via a dedicated TDE resource).

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Optional explicit name. If null, computed (sqlmi-{sub}-{env}-{region}-{workload}). | `string` | `null` | No |
| subscription_acronym / environment / region_code / workload | Naming components. | `string` | see vars | Conditional |
| location | Azure region. | `string` | -- | Yes |
| resource_group_name | Resource group name. | `string` | -- | Yes |
| subnet_id | Dedicated subnet delegated to Microsoft.Sql/managedInstances. | `string` | -- | Yes |
| administrator_login | SQL admin login. | `string` | `null` | Conditional |
| administrator_login_password | SQL admin password (**sensitive**). | `string` | `null` | Conditional |
| entra_administrator | Entra (Azure AD) admin object. | `object` | `null` | Conditional |
| sku_name | SKU (GP_*/BC_*). | `string` | `"GP_Gen5"` | No |
| vcores | vCores (>=4). | `number` | `4` | No |
| storage_size_in_gb | Storage GB (32-16384). | `number` | `32` | No |
| license_type | LicenseIncluded / BasePrice. | `string` | `"LicenseIncluded"` | No |
| storage_account_type | Backup redundancy (LRS/ZRS/GRS/GZRS). | `string` | `"GRS"` | No |
| public_data_endpoint_enabled | Public data endpoint. | `bool` | `false` | No |
| minimum_tls_version | Minimum TLS (1.1/1.2/1.3). | `string` | `"1.2"` | No |
| proxy_override | Default/Proxy/Redirect. | `string` | `null` | No |
| zone_redundant_enabled | Zone redundancy (opt-in). | `bool` | `false` | No |
| collation / timezone_id / maintenance_configuration_name / dns_zone_partner_id | Optional MI settings. | `string` | `null` | No |
| identity | Managed identity object. | `object` | `null` | No |
| lock | Optional resource lock. | `object` | `null` | No |
| role_assignments | RBAC map (delegated to ../RoleAssignment). | `map(object)` | `{}` | No |
| tags | Tags. | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Managed Instance |
| name | The name of the Managed Instance |
| fqdn | Fully qualified domain name |
| dns_zone | DNS zone (partner/failover-group setups) |
| identity_principal_id | Managed identity principal ID (null if none) |
| identity_tenant_id | Managed identity tenant ID (null if none) |
| resource | Complete resource object (**sensitive**) |
| lock_id | Management lock ID (null if no lock) |
| role_assignment_ids | Map of role assignment key => ID |
