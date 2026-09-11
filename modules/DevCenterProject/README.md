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
| [azurerm_dev_center_project.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_center_project) | resource |
| [azurerm_dev_center_project_environment_type.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dev_center_project_environment_type) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| dev\_center\_id | Resource ID of the parent Dev Center (e.g. module.dev\_center.id). Changing this forces a new project. | `string` | n/a | yes |
| location | Azure region where the project will be deployed (typically the same region as the Dev Center). | `string` | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| description | Optional description of the project. Changing this forces a new project. | `string` | `null` | no |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| environment\_types | Project environment types to enable, keyed by name. The key MUST match a<br>Dev Center environment type name (created via the DevCenter module's<br>`environment_types`). This is what makes an environment deployable.<br><br>Per-entry fields:<br>- `deployment_target_id`          - (Required) Subscription ID where this environment type's<br>                                     resources are deployed (e.g. /subscriptions/<sub>).<br>- `creator_role_assignment_roles` - (Optional) Role definition IDs (GUIDs) granted to the<br>                                     environment CREATOR on the target subscription (e.g. the<br>                                     Owner role id "8e3af657-a8ff-443c-a75c-2fe8c4bcb635").<br>- `user_role_assignments`         - (Optional) Map of user/principal object ID => list of role<br>                                     definition IDs, granting standing access on the target sub.<br>- `identity`                      - (Optional) Deployment identity for this environment type<br>                                     (default SystemAssigned). This identity needs Contributor +<br>                                     User Access Administrator on `deployment_target_id`.<br>- `tags`                          - (Optional) Per-environment-type tags. | <pre>map(object({<br>    deployment_target_id          = string<br>    creator_role_assignment_roles = optional(list(string), [])<br>    user_role_assignments         = optional(map(list(string)), {})<br>    identity = optional(object({<br>      type         = optional(string, "SystemAssigned")<br>      identity_ids = optional(list(string), [])<br>    }), {})<br>    tags = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| identity | Managed identity for the project. Recommended: the project identity is what<br>deploys environment types and reads project-level catalogs / Key Vault secrets.<br>As a security best practice, use a project identity that is MORE restricted than<br>the Dev Center identity.<br><br>Default is SystemAssigned. If BOTH a system-assigned and a user-assigned identity<br>are attached, the project uses ONLY the user-assigned identity.<br><br>- `type`         - (Required) 'SystemAssigned', 'UserAssigned', or 'SystemAssigned, UserAssigned'.<br>- `identity_ids` - (Optional) User Assigned Managed Identity IDs. Required when type includes 'UserAssigned'. | <pre>object({<br>    type         = string<br>    identity_ids = optional(list(string), [])<br>  })</pre> | <pre>{<br>  "type": "SystemAssigned"<br>}</pre> | no |
| lock | Optional management lock on the project.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Generated from kind if not specified. | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| maximum\_dev\_boxes\_per\_user | Optional cap on the number of Dev Boxes a single user can create across all pools in the project. Null = no limit. | `number` | `null` | no |
| name | Optional. Explicit Dev Center Project name (3-63 chars, start with a letter, letters/digits/hyphens). If null, computed as dcp-{acr}-{env}-{region}-{workload}. | `string` | `null` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | A map of role assignments to create on this project. The map key is arbitrary.<br>Typical project-scoped roles: "DevCenter Project Admin", "DevCenter Dev Box User",<br>"Deployment Environments User".<br><br>- `role_definition_id_or_name`             - (Required) The ID or name of the role definition.<br>- `principal_id`                           - (Required) The ID of the principal.<br>- `principal_type`                         - (Optional) User, Group or ServicePrincipal.<br>- `condition`                              - (Optional) ABAC condition.<br>- `condition_version`                      - (Optional) Condition version ("1.0" or "2.0").<br>- `description`                            - (Optional) Description.<br>- `skip_service_principal_aad_check`       - (Optional) Skip AAD check.<br>- `delegated_managed_identity_resource_id` - (Optional) Cross-tenant delegated MI. | <pre>map(object({<br>    role_definition_id_or_name             = string<br>    principal_id                           = string<br>    principal_type                         = optional(string)<br>    condition                              = optional(string)<br>    condition_version                      = optional(string)<br>    description                            = optional(string)<br>    skip_service_principal_aad_check       = optional(bool, false)<br>    delegated_managed_identity_resource_id = optional(string)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, api) | `string` | `null` | no |
| tags | Tags to apply to the project | `map(string)` | `{}` | no |
| workload | Workload / team name for naming convention. Keep short — composed name must be <= 63 chars. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| dev\_center\_uri | The URI of the Dev Center this project is associated with |
| environment\_type\_identity\_principal\_ids | Map of environment type name => deployment identity principal ID (null when no system-assigned identity). Grant Contributor + User Access Administrator on the target subscription. |
| environment\_type\_ids | Map of environment type name => Dev Center Project Environment Type resource ID. |
| id | The Dev Center Project resource ID |
| identity\_principal\_id | The system-assigned managed identity principal ID of the project (null when no system-assigned identity). Grant it RBAC on deployment subscriptions / project catalogs. |
| identity\_tenant\_id | The tenant ID of the project managed identity (null when no system-assigned identity). |
| name | The Dev Center Project name |
| resource | The complete Dev Center Project resource object |
<!-- END_TF_DOCS -->
