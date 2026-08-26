# NetworkWatcher

Creates an Azure Network Watcher resource with optional management lock. Naming is delegated to the in-repo `Naming` submodule (`Azure/naming/azurerm`).

## Breaking changes

### v0.2.1

**The module no longer creates its own resource group.** The `create_resource_group` and `resource_group_workload` variables have been removed. `resource_group_name` is now required.

Callers that previously used `create_resource_group = true` must add a `removed` block in their Terragrunt root config:

```hcl
removed {
  from = module.network_watcher.azurerm_resource_group.this
  lifecycle { destroy = false }
}
```

Apply **once** with this block present, then delete it. This tells Terraform: "this RG is gone from the module but DO NOT destroy it in Azure." Callers that already used `create_resource_group = false` (the default) are unaffected.

**The workload-free naming variant (`nw-{sub}-{env}-{region}`) has been dropped.** Callers with `workload = null` must either provide a workload, or pass an explicit `name`.

## Usage

### Standalone

```hcl
module "network_watcher" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/NetworkWatcher?ref=v0.2.1"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "platform"
  location             = "germanywestcentral"
  resource_group_name  = "rg-con-prod-gwc-network"

  lock = { kind = "CanNotDelete" }
  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/NetworkWatcher"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = include.root.inputs.workload
  location             = include.root.inputs.location
  resource_group_name  = include.root.inputs.network_watcher_rg_name
  tags                 = include.root.inputs.common_tags
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
| name | Explicit name override. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. mgm, con) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload suffix (e.g. platform). Required when `name` is null. | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Name of the resource group in which to create the Network Watcher. Must be caller-provided. | `string` | -- | Yes |
| lock | Management lock configuration (CanNotDelete or ReadOnly) | `object({ kind = string, name = optional(string) })` | `null` | No |
| tags | Tags to apply | `map(string)` | `{}` | No |

Note: `subscription_acronym`, `environment`, `region_code`, and `workload` are all required when `name` is null.

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Network Watcher |
| name | The name of the Network Watcher |
| resource | Complete Network Watcher resource object |
| resource_group_name | The name of the resource group |
