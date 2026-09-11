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
