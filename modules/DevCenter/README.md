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
