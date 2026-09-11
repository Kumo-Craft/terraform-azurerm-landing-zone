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
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_mssql_managed_instance.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_managed_instance) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_name | Resource group name | `string` | n/a | yes |
| subnet\_id | REQUIRED. Resource ID of the DEDICATED subnet delegated to Microsoft.Sql/managedInstances (with the mandatory NSG + route table). SQL MI can only be deployed into such a subnet; the module does not create it. | `string` | n/a | yes |
| administrator\_login | SQL administrator login. Optional if an Entra admin with entra-only auth is configured. Cannot be changed after creation. | `string` | `null` | no |
| administrator\_login\_password | SQL administrator password. Required when administrator\_login is set. Prefer sourcing from Key Vault. | `string` | `null` | no |
| collation | Server collation. Null = provider default (SQL\_Latin1\_General\_CP1\_CI\_AS). Cannot be changed after creation. | `string` | `null` | no |
| dns\_zone\_partner\_id | Optional. Resource ID of a partner MI to share the DNS zone with (failover group scenarios). | `string` | `null` | no |
| entra\_administrator | Optional Microsoft Entra (Azure AD) administrator. Set azuread\_authentication\_only\_enabled = true to disable SQL auth entirely. | <pre>object({<br>    login_username                      = string<br>    object_id                           = string<br>    principal_type                      = string # User | Group | Application<br>    tenant_id                           = optional(string, null)<br>    azuread_authentication_only_enabled = optional(bool, false)<br>  })</pre> | `null` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| identity | Optional managed identity. type = SystemAssigned \| UserAssigned \| 'SystemAssigned, UserAssigned'. identity\_ids required for UserAssigned. | <pre>object({<br>    type         = string<br>    identity_ids = optional(list(string), null)<br>  })</pre> | `null` | no |
| license\_type | License model: LicenseIncluded (pay-as-you-go) or BasePrice (Azure Hybrid Benefit). | `string` | `"LicenseIncluded"` | no |
| lock | Optional resource lock (CanNotDelete / ReadOnly) on the Managed Instance. Set to null to skip. | <pre>object({<br>    kind = string<br>    name = optional(string, null)<br>  })</pre> | `null` | no |
| maintenance\_configuration\_name | Optional maintenance window configuration name (e.g. SQL\_WestEurope\_MI\_1). | `string` | `null` | no |
| minimum\_tls\_version | Minimum TLS version for connections. Default 1.2. | `string` | `"1.2"` | no |
| name | Optional. Explicit name. If null, computed from naming components (sqlmi-{sub}-{env}-{region}-{workload}). | `string` | `null` | no |
| proxy\_override | Connection type: Default, Proxy, or Redirect. Null = provider default. | `string` | `null` | no |
| public\_data\_endpoint\_enabled | Whether the public data endpoint is enabled. Default false (private-only): connect via the delegated subnet or a Private Endpoint. | `bool` | `false` | no |
| region\_code | Region code (e.g. gwc, frc) | `string` | `null` | no |
| role\_assignments | Map of role assignments at the Managed Instance scope (delegated to ../RoleAssignment). Default principal\_type='ServicePrincipal'. | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| sku\_name | SKU name. General Purpose (GP\_*) or Business Critical (BC\_*), e.g. GP\_Gen5, BC\_Gen5, GP\_Gen8IM. | `string` | `"GP_Gen5"` | no |
| storage\_account\_type | Backup storage redundancy: LRS, ZRS, GRS, GZRS. Default GRS (geo-redundant backups). | `string` | `"GRS"` | no |
| storage\_size\_in\_gb | Storage size in GB (32 to 16384). | `number` | `32` | no |
| subscription\_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | no |
| tags | Tags to apply | `map(string)` | `{}` | no |
| timezone\_id | Time zone ID (e.g. 'W. Europe Standard Time'). Null = provider default (UTC). Cannot be changed after creation. | `string` | `null` | no |
| vcores | Number of vCores. Minimum 4. | `number` | `4` | no |
| workload | Workload suffix (e.g. 01) | `string` | `"01"` | no |
| zone\_redundant\_enabled | Zone redundancy. Opt-in (default false): only supported on eligible tiers/regions and increases cost. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| dns\_zone | The DNS zone the managed instance is in (used for partner/failover-group setups). |
| fqdn | The fully qualified domain name of the SQL Managed Instance |
| id | The ID of the SQL Managed Instance |
| identity\_principal\_id | Principal ID of the managed identity (null if no identity block). |
| identity\_tenant\_id | Tenant ID of the managed identity (null if no identity block). |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | The name of the SQL Managed Instance |
| resource | The complete SQL Managed Instance resource object (sensitive: carries the admin password). |
| role\_assignment\_ids | Map of role assignment logical key => role assignment ID |
<!-- END_TF_DOCS -->
