# DevCenter

Deploys an Azure **Dev Center** (`Microsoft.DevCenter/devcenters`) — the top-level resource for **Microsoft Dev Box** and **Azure Deployment Environments** — with a managed identity, optional management lock, and role assignments.

A Dev Center is the parent for projects, catalogs, dev box definitions, environment types, and network connections. This module manages the Dev Center itself; attach those child resources with the dedicated `azurerm_dev_center_*` resources (separate modules) referencing this module's `id`.

## Managed identity (recommended)

Microsoft recommends attaching a managed identity to the Dev Center — it is **required** to:

- attach **catalogs** (GitHub / Azure Repos) and read **environment definitions**;
- read **Key Vault** secrets (e.g. a catalog Personal Access Token);
- create **environment types** in deployment subscriptions (grant the identity `Contributor` + `User Access Administrator` there).

This module defaults `identity = { type = "SystemAssigned" }`. Use the `identity_principal_id` output to assign the roles above.

> If you attach **both** a system-assigned and a user-assigned identity, the Dev Center uses **only** the user-assigned identity.

## Usage

### Standalone

```hcl
module "dev_center" {
  source = "../DevCenter"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "devbox"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-devcenter"

  # SystemAssigned by default. Switch to a user-assigned identity if you
  # share one identity across dev center + projects.
  identity = { type = "SystemAssigned" }

  # Enable when projects use project-level catalogs.
  project_catalog_item_sync_enabled = true

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}

# Grant the Dev Center identity access to a Key Vault holding a catalog PAT.
module "kv_role" {
  source = "../RoleAssignment"

  scope                      = module.key_vault.id
  role_definition_id_or_name = "Key Vault Secrets User"
  principal_id               = module.dev_center.identity_principal_id
  principal_type             = "ServicePrincipal"
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/DevCenter"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "devbox"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name

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
| name | Explicit Dev Center name (3-26 chars). If null, computed `dc-{acr}-{env}-{region}-{workload}`. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, api) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name (composed name must be ≤ 26 chars) | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| identity | Managed identity (`SystemAssigned` default) | `object({ type = string, identity_ids = optional(list(string), []) })` | `{ type = "SystemAssigned" }` | No |
| project_catalog_item_sync_enabled | Allow project catalogs to sync catalog items | `bool` | `false` | No |
| environment_types | Names of environment types to create on the Dev Center (e.g. `["sandbox","dev","prod"]`). Prerequisite for project environment types. | `list(string)` | `[]` | No |
| role_assignments | Map of role assignments on the Dev Center. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| lock | Management lock (CanNotDelete or ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The Dev Center resource ID |
| name | The Dev Center name |
| dev_center_uri | The URI of the Dev Center |
| identity_principal_id | System-assigned identity principal ID (null if none) — grant it RBAC on catalogs/Key Vault/subscriptions |
| identity_tenant_id | Managed identity tenant ID (null if none) |
| environment_type_ids | Map of environment type name => resource ID |
| resource | The complete Dev Center resource object |

## Environment types

`environment_types` creates `azurerm_dev_center_environment_type` resources on the Dev Center — just names (e.g. `["sandbox","dev","test","prod"]`). They are a **prerequisite**: a project can only surface/deploy an environment type whose name was first declared here. Making an environment type *deployable* (target subscription, deployment identity, creator role) happens on the project side — see the `DevCenterProject` module's `environment_types` input.

## Notes

- **Name length.** The Dev Center name must be 3-26 characters. A `precondition` enforces this on the composed name — shorten `workload` or pass an explicit `name` if it overflows.
- **Child resources.** Projects (`azurerm_dev_center_project`), catalogs, dev box definitions, network connections, and pools are separate resources/modules that reference `module.dev_center.id`.

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
| role\_assignments | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_dev_center.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_center) | resource |
| [azurerm_dev_center_environment_type.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_center_environment_type) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region where the Dev Center will be deployed | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| environment\_types | Names of the environment types to create on this Dev Center (e.g.<br>["sandbox", "dev", "test", "prod"]). These are a PREREQUISITE for project<br>environment types — a `DevCenterProject` can only enable an environment type<br>whose name matches one defined here. The portal also requires at least one<br>Dev Center environment type before a project can surface environments. | `list(string)` | `[]` | no |
| identity | Managed identity for the Dev Center. Microsoft strongly recommends attaching an<br>identity: it is required to attach catalogs (GitHub/Azure Repos), to read Key Vault<br>secrets (e.g. catalog PATs), and to create environment types in deployment<br>subscriptions (the identity needs Contributor + User Access Administrator there).<br><br>Default is SystemAssigned. Note: if BOTH a system-assigned and a user-assigned<br>identity are attached, the Dev Center uses ONLY the user-assigned identity.<br><br>- `type`         - (Required) 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'.<br>- `identity_ids` - (Optional) User Assigned Managed Identity IDs. Required when type includes 'UserAssigned'. | <pre>object({<br>    type         = string<br>    identity_ids = optional(list(string), [])<br>  })</pre> | <pre>{<br>  "type": "SystemAssigned"<br>}</pre> | no |
| lock | Optional management lock on the Dev Center.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit Dev Center name (3-26 chars, start with a letter, letters/digits/hyphens). If null, computed as dc-{acr}-{env}-{region}-{workload}. | `string` | `null` | no |
| project\_catalog\_item\_sync\_enabled | Whether project catalogs associated with projects in this Dev Center may sync catalog items. Azure default is false; enable when project-level catalogs are used. | `bool` | `false` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | A map of role assignments to create on this Dev Center. The map key is arbitrary.<br><br>- `role_definition_id_or_name`             - (Required) The ID or name of the role definition.<br>- `principal_id`                           - (Required) The ID of the principal.<br>- `principal_type`                         - (Optional) User, Group or ServicePrincipal.<br>- `condition`                              - (Optional) ABAC condition.<br>- `condition_version`                      - (Optional) Condition version ("1.0" or "2.0").<br>- `description`                            - (Optional) Description.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check.<br>- `delegated_managed_identity_resource_id` - (Optional) Cross-tenant delegated MI. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    principal_id                           = string<br>    principal_type                         = optional(string)<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    description                            = optional(string)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, api) | `string` | `null` | no |
| tags | Tags to apply to the Dev Center | `map(string)` | `{}` | no |
| workload | Workload name for naming convention. Keep short — the composed name must be <= 26 chars. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| dev\_center\_uri | The URI of the Dev Center |
| environment\_type\_ids | Map of environment type name => Dev Center Environment Type resource ID. |
| id | The Dev Center resource ID |
| identity\_principal\_id | The system-assigned managed identity principal ID (null when no system-assigned identity). Grant this RBAC on catalogs, Key Vault, and deployment subscriptions. |
| identity\_tenant\_id | The tenant ID of the Dev Center managed identity (null when no system-assigned identity). |
| name | The Dev Center name |
| resource | The complete Dev Center resource object |
<!-- END_TF_DOCS -->
