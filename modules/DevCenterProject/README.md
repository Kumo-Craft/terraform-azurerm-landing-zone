# DevCenterProject

Deploys an Azure **Dev Center Project** (`Microsoft.DevCenter/projects`) — a team-scoped child of a [`DevCenter`](../DevCenter). Projects are where teams consume Dev Boxes and Deployment Environments; one Dev Center typically hosts many projects (one per team/product).

Leaf companion to the `DevCenter` module: pass the parent Dev Center's `id` as `dev_center_id`.

## Project managed identity (recommended)

A project carries its own managed identity, used to deploy **environment types** and read **project-level catalogs** / Key Vault secrets. As a Microsoft security best practice, give the **project** identity *more restricted* access than the **Dev Center** identity. Defaults to `SystemAssigned`.

> If both a system-assigned and a user-assigned identity are attached, the project uses **only** the user-assigned identity.

## Usage

### With the DevCenter module

```hcl
module "dev_center" {
  source = "../DevCenter"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "devbox"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-prod-gwc-devcenter"
}

module "dev_center_project_teama" {
  source = "../DevCenterProject"

  dev_center_id       = module.dev_center.id
  location            = "germanywestcentral"
  resource_group_name = "rg-mgm-prod-gwc-devcenter"

  subscription_acronym = "mgm"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "teama"

  description                = "Team A dev box project"
  maximum_dev_boxes_per_user = 2
  identity                   = { type = "SystemAssigned" }

  role_assignments = {
    devbox_users = {
      role_definition_id_or_name = "DevCenter Dev Box User"
      principal_id               = "00000000-0000-0000-0000-000000000000"
      principal_type             = "Group"
    }
  }

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production", Team = "A" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/DevCenterProject"
}

inputs = {
  dev_center_id       = dependency.dev_center.outputs.id
  location            = include.root.inputs.location
  resource_group_name = dependency.rg.outputs.name

  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "teama"

  maximum_dev_boxes_per_user = 2
  tags                       = include.root.inputs.common_tags
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
| name | Explicit project name (3-63 chars). If null, computed `dcp-{acr}-{env}-{region}-{workload}`. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, api) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload / team name (composed name must be ≤ 63 chars) | `string` | `null` | No |
| dev_center_id | Resource ID of the parent Dev Center | `string` | -- | Yes |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| description | Project description (ForceNew) | `string` | `null` | No |
| maximum_dev_boxes_per_user | Cap on Dev Boxes per user across all project pools | `number` | `null` | No |
| identity | Managed identity (`SystemAssigned` default) | `object({ type = string, identity_ids = optional(list(string), []) })` | `{ type = "SystemAssigned" }` | No |
| environment_types | Map (keyed by env type name, must match a Dev Center env type) of deployable environment types: `deployment_target_id`, `creator_role_assignment_roles`, `user_role_assignments`, `identity`, `tags`. | `map(object({...}))` | `{}` | No |
| role_assignments | Map of role assignments on the project. Key is arbitrary. | `map(object({...}))` | `{}` | No |
| lock | Management lock (CanNotDelete or ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The Dev Center Project resource ID |
| name | The Dev Center Project name |
| dev_center_uri | URI of the associated Dev Center |
| identity_principal_id | System-assigned identity principal ID (null if none) |
| identity_tenant_id | Managed identity tenant ID (null if none) |
| environment_type_ids | Map of env type name => project environment type resource ID |
| environment_type_identity_principal_ids | Map of env type name => deployment identity principal ID (grant Contributor + User Access Administrator on the target sub) |
| resource | The complete project resource object |

## Environment types (deployable environments)

`environment_types` enables Azure Deployment Environments for this project. **Each map key must match a Dev Center environment type name** (created via the `DevCenter` module's `environment_types`). Each entry carries:

- `deployment_target_id` — the subscription (`/subscriptions/<guid>`) where the environment's resources are deployed;
- `identity` — the deployment identity (SystemAssigned by default). It needs **Contributor + User Access Administrator** on the target subscription — use the `environment_type_identity_principal_ids` output to assign those roles;
- `creator_role_assignment_roles` — role **definition IDs** (GUIDs) granted to the environment creator on the target sub (e.g. Owner `8e3af657-a8ff-443c-a75c-2fe8c4bcb635`);
- `user_role_assignments` — map of principal object ID => list of role definition IDs for standing access.

```hcl
module "dev_center" {
  source            = "../DevCenter"
  # ...
  environment_types = ["dev", "prod"]   # prerequisite names on the Dev Center
}

module "dev_center_project_teama" {
  source        = "../DevCenterProject"
  dev_center_id = module.dev_center.id
  # ...

  environment_types = {
    dev = {                              # key matches a Dev Center env type
      deployment_target_id          = "/subscriptions/11111111-1111-1111-1111-111111111111"
      creator_role_assignment_roles = ["8e3af657-a8ff-443c-a75c-2fe8c4bcb635"] # Owner
      user_role_assignments = {
        "22222222-2222-2222-2222-222222222222" = ["acdd72a7-3385-48ef-bd42-f606fba81ae7"] # Reader
      }
    }
  }
}
```

> Ensure the Dev Center environment type exists before the project one — wire it via module dependency (`dev_center_id = module.dev_center.id`) or an explicit `depends_on` on the DevCenter module.

## Notes

- **`dev_center_id`, `name`, `description` are ForceNew** — changing any of them recreates the project.
- **Name length.** A `precondition` enforces 3-63 chars on the composed name — shorten `workload` or pass an explicit `name`.
- **Downstream.** Pools (`azurerm_dev_center_project_pool`) and dev box definitions are separate resources that reference this project's `id`.
