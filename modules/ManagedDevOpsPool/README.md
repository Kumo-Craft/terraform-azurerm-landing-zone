# ManagedDevOpsPool

Deploys an Azure **Managed DevOps Pool** (`Microsoft.DevOpsInfrastructure/pools`) — a managed fleet of Azure DevOps build/release agents, organized under a **Dev Center project**. Supports **VNet injection** (agents placed into your own subnet) and isolated Microsoft-managed networking.

> Managed DevOps Pools **require a Dev Center project** as their organizational container (`dev_center_project_id`) — pair this with the in-repo `DevCenterProject` module. This is unrelated to Microsoft Dev Box.

## Networking — VNet injection

The screenshot's *"Agents injected into existing virtual network"* maps to `subnet_id`:

- **`subnet_id` set** → agents are injected into your subnet (private connectivity to your resources). The subnet must be **delegated to `Microsoft.DevOpsInfrastructure/pools`** and sized for `maximum_concurrency`.
- **`subnet_id` null** (default) → *"Isolated virtual network"* — a Microsoft-managed network.

## Usage

### With VNet injection, under a Dev Center project

```hcl
module "dev_center" {
  source = "../DevCenter"
  # ... -> dc-mgm-nprd-gwc-devops
}

module "dev_center_project" {
  source        = "../DevCenterProject"
  dev_center_id = module.dev_center.id
  # ...
}

module "devops_pool" {
  source = "../ManagedDevOpsPool"

  subscription_acronym = "mgm"
  environment          = "nprd"
  region_code          = "gwc"
  workload             = "devops"
  location             = "germanywestcentral"
  resource_group_name  = "rg-mgm-nprd-gwc-devops"

  dev_center_project_id = module.dev_center_project.id
  maximum_concurrency   = 5

  organizations = [{
    url         = "https://dev.azure.com/contoso"
    parallelism = 5
    projects    = ["Platform", "Apps"] # optional — empty = all projects
  }]

  # Agents injected into an existing subnet (delegated to Microsoft.DevOpsInfrastructure/pools)
  subnet_id = "/subscriptions/.../virtualNetworks/vnet-cicd/subnets/snet-agents"

  sku_name = "Standard_D2ads_v5"
  images   = [{ well_known_image_name = "ubuntu-22.04/latest" }]

  # Stateless agents (fresh per job) with automatic warm-agent prediction.
  agent_type                            = "stateless"
  automatic_resource_prediction_enabled = true
  prediction_preference                 = "Balanced"

  # UserAssigned identity (Managed DevOps Pools support UserAssigned only)
  identity_ids = ["/subscriptions/.../userAssignedIdentities/uami-devops-pool"]

  tags = { Environment = "NonProd" }
}
```

### Subnet delegation (prerequisite for VNet injection)

```hcl
resource "azurerm_subnet" "agents" {
  # ...
  delegation {
    name = "mdp"
    service_delegation {
      name = "Microsoft.DevOpsInfrastructure/pools"
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Inputs (key)

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Explicit pool name (3-44 chars). If null, `mdp-{acr}-{env}-{region}-{workload}`. | `string` | `null` | No |
| subscription_acronym / environment / region_code / workload | Naming components (required unless `name`) | `string` | `null` | No |
| location / resource_group_name | — | `string` | -- | Yes |
| dev_center_project_id | Dev Center Project ID organizing the pool | `string` | -- | Yes |
| maximum_concurrency | Max agent resources (1-10000) | `number` | `1` | No |
| organizations | Azure DevOps orgs (`url`, optional `parallelism`, `projects`) | `list(object)` | -- | Yes |
| permission | Admin model (`Inherit` / `SpecificAccounts` + groups/users) | `object` | `null` | No |
| sku_name | Agent VM SKU | `string` | `"Standard_D2ads_v5"` | No |
| subnet_id | **VNet injection** subnet (null = isolated MS network) | `string` | `null` | No |
| os_disk_storage_account_type | Premium / Standard / StandardSSD | `string` | `"Premium"` | No |
| images | Agent images (`well_known_image_name` XOR `id`) | `list(object)` | Ubuntu 22.04 | No |
| storage | Optional data disk | `object` | `null` | No |
| interactive_logon_enabled | Run agent interactively | `bool` | `false` | No |
| agent_type | `stateless` (CI) or `stateful` | `string` | `"stateless"` | No |
| automatic_resource_prediction_enabled | Auto warm-agent prediction | `bool` | `true` | No |
| prediction_preference | MostCostEffective … BestPerformance | `string` | `"Balanced"` | No |
| stateful_grace_period_time_span / stateful_maximum_agent_lifetime | Stateful-only timings | `string` | `null` | No |
| identity_ids | UserAssigned identity IDs (UserAssigned only) | `list(string)` | `[]` | No |
| work_folder | Agent work folder | `string` | `null` | No |
| lock | Management lock | `object` | `null` | No |
| tags | Tags | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | The Managed DevOps Pool resource ID |
| name | The pool name (use as the pool in Azure DevOps pipelines) |
| dev_center_project_id | The associated Dev Center Project ID |
| resource | The complete pool resource object |

## Notes

- **One agent profile.** Exactly one of `stateless_agent` / `stateful_agent` is rendered (driven by `agent_type`).
- **Parallelism vs concurrency.** With a single org, unset `parallelism` defaults to `maximum_concurrency`. With **multiple** orgs, set `parallelism` per org so the sum equals `maximum_concurrency`.
- **Identity.** Managed DevOps Pools support **UserAssigned** identities only (no SystemAssigned).
- **Not exposed (yet).** GitHub organizations, manual scaling schedules (`manual_resource_prediction`), and Key Vault certificate management are out of scope of this module — extend if needed (all verified to exist on the provider resource).

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

## Resources

| Name | Type |
|------|------|
| [azurerm_managed_devops_pool.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_devops_pool) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| dev\_center\_project\_id | ID of the Dev Center Project that organizes this pool (e.g. module.dev\_center\_project.id). Managed DevOps Pools require a Dev Center project. | `string` | n/a | yes |
| location | Azure region where the Managed DevOps Pool will be deployed | `string` | n/a | yes |
| organizations | One or more Azure DevOps organizations the pool serves. The sum of `parallelism`<br>across organizations should equal `maximum_concurrency`.<br><br>- `url`         - (Required) Azure DevOps org URL (e.g. https://dev.azure.com/contoso). Must end with a letter or number.<br>- `parallelism` - (Optional) Max machines for this org (1-10000). Defaults to `maximum_concurrency`.<br>- `projects`    - (Optional) Restrict the pool to these Azure DevOps project names. Empty = all projects. | <pre>list(object({<br>    url         = string<br>    parallelism = optional(number)<br>    projects    = optional(list(string), [])<br>  }))</pre> | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| agent\_type | Agent profile: 'stateless' (clean agent per job — recommended for CI) or 'stateful' (agents persist between jobs). | `string` | `"stateless"` | no |
| automatic\_resource\_prediction\_enabled | Enable automatic standby-agent prediction (Azure decides how many warm agents to keep). When false, no resource prediction block is set (agents created on demand). | `bool` | `true` | no |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| identity\_ids | User-Assigned Managed Identity IDs to attach to the pool. Managed DevOps Pools only support UserAssigned identities. Empty list = no identity. | `list(string)` | `[]` | no |
| images | One or more images for the agents. Exactly one of `well_known_image_name` or `id`<br>per image.<br><br>- `well_known_image_name` - (Optional) Predefined alias (e.g. "ubuntu-22.04/latest", "windows-2022/latest").<br>- `id`                    - (Optional) Resource ID of a custom / Azure Compute Gallery image.<br>- `aliases`               - (Optional) Aliases to reference the image by.<br>- `buffer`                - (Optional) Percentage of the standby buffer for this image ("*" or 0-100). Defaults to "*". | <pre>list(object({<br>    well_known_image_name = optional(string)<br>    id                    = optional(string)<br>    aliases               = optional(list(string), [])<br>    buffer                = optional(string, "*")<br>  }))</pre> | <pre>[<br>  {<br>    "well_known_image_name": "ubuntu-22.04/latest"<br>  }<br>]</pre> | no |
| interactive\_logon\_enabled | Whether the agent runs in interactive mode (security block). Defaults to false. | `bool` | `false` | no |
| lock | Optional management lock (CanNotDelete or ReadOnly). | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| manual\_standby\_agent\_count | Mode Manual : nombre d'agents standby CHAUDS 24/7 (all\_week\_schedule). Si defini (>=1), prime sur l'Automatic. Doit etre entre 1 et maximum\_concurrency. | `number` | `null` | no |
| manual\_time\_zone | Fuseau des plannings Manual. Defaut UTC. | `string` | `"UTC"` | no |
| maximum\_concurrency | Maximum number of agent resources that can exist at any time (1-10000). | `number` | `1` | no |
| name | Optional. Explicit pool name (3-44 chars, alphanumerics/periods/hyphens, start alphanumeric, not ending in a period). If null, computed as mdp-{acr}-{env}-{region}-{workload}. | `string` | `null` | no |
| os\_disk\_storage\_account\_type | OS disk storage type for the agents. Possible values: Premium, Standard, StandardSSD. | `string` | `"Premium"` | no |
| permission | Optional admin permission model for the pool.<br><br>- `kind`                  - (Required) "Inherit" (Azure DevOps project admins) or "SpecificAccounts".<br>- `administrator_groups`  - (Optional) Group email addresses (only with SpecificAccounts).<br>- `administrator_users`   - (Optional) User email addresses (only with SpecificAccounts). | <pre>object({<br>    kind                 = string<br>    administrator_groups = optional(list(string), [])<br>    administrator_users  = optional(list(string), [])<br>  })</pre> | `null` | no |
| prediction\_preference | Cost/performance balance for automatic prediction. Possible values: MostCostEffective, MoreCostEffective, Balanced, MorePerformance, BestPerformance. | `string` | `"Balanced"` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| sku\_name | Azure VM SKU for the agent machines (e.g. Standard\_D2ads\_v5). | `string` | `"Standard_D2ads_v5"` | no |
| stateful\_grace\_period\_time\_span | Stateful only. Time an idle agent waits before shutting down (format dd.hh:mm:ss or hh:mm:ss). | `string` | `null` | no |
| stateful\_maximum\_agent\_lifetime | Stateful only. Maximum lifetime of an agent before it is recycled (format dd.hh:mm:ss or hh:mm:ss). | `string` | `null` | no |
| storage | Optional additional data disk for the agents.<br><br>- `disk_size_in_gb`       - (Required) 1-32767.<br>- `caching`               - (Optional) ReadOnly or ReadWrite.<br>- `drive_letter`          - (Optional) Windows drive letter.<br>- `storage_account_type`  - (Optional) Premium\_LRS, Premium\_ZRS, Standard\_LRS, StandardSSD\_LRS, StandardSSD\_ZRS. Defaults to Standard\_LRS. | <pre>object({<br>    disk_size_in_gb      = number<br>    caching              = optional(string)<br>    drive_letter         = optional(string)<br>    storage_account_type = optional(string)<br>  })</pre> | `null` | no |
| subnet\_id | Optional. Subnet ID to inject the agents into ("Agents injected into existing<br>virtual network"). When null, the pool uses an isolated Microsoft-managed network.<br>The subnet must be delegated to `Microsoft.DevOpsInfrastructure/pools`. | `string` | `null` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, api) | `string` | `null` | no |
| tags | Tags to apply to the Managed DevOps Pool | `map(string)` | `{}` | no |
| work\_folder | Optional work folder for every agent in the pool. | `string` | `null` | no |
| workload | Workload name for naming convention. Keep short — composed name must be <= 44 chars. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| dev\_center\_project\_id | The Dev Center Project ID the pool is organized under |
| id | The Managed DevOps Pool resource ID |
| name | The Managed DevOps Pool name (use this as the pool name in Azure DevOps pipelines) |
| resource | The complete Managed DevOps Pool resource object |
<!-- END_TF_DOCS -->
