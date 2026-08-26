# ResourceLock

Applies management locks (CanNotDelete or ReadOnly) to one or more existing Azure scopes (resource groups or individual resources), with a flag to disable all locks for maintenance operations.

## Usage

### Standalone

```hcl
module "resource_lock" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/ResourceLock?ref=v0.2.15"

  locks = {
    rg_network = {
      scope = "/subscriptions/.../resourceGroups/rg-api-prod-gwc-network"
      name  = "lock-rg-network"
      notes = "VNet, subnets, peerings — deletion causes connectivity loss"
    }
    rg_aks = {
      scope      = "/subscriptions/.../resourceGroups/rg-api-prod-gwc-aks"
      name       = "lock-rg-aks"
      lock_level = "ReadOnly"
    }
  }
}
```

### Terragrunt

Assumes a single ResourceGroup module call producing map outputs.

```hcl
terraform {
  source = "${get_repo_root()}/modules/ResourceLock"
}

dependency "rg" {
  config_path = "../resource-group"
}

inputs = {
  locks = {
    rg_network = {
      scope = dependency.rg.outputs.ids["network"]
      name  = "lock-rg-network"
    }
    rg_aks = {
      scope = dependency.rg.outputs.ids["aks"]
      name  = "lock-rg-aks"
    }
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| locks | Map of management locks. Key is arbitrary. | `map(object({...}))` | -- | Yes |
| enable_locks | Set to false to disable all locks (e.g. maintenance destroy) | `bool` | `true` | No |

### Lock Object

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| scope | `string` | Yes | -- | Azure resource ID to lock. Accepts subscription, resource group, child resource, or management group scope (see "Supported scopes" below). |
| name | `string` | No | `"lock-<map-key>"` (derived from the entry's key in `var.locks`) | Lock name |
| lock_level | `string` | No | `"CanNotDelete"` | `CanNotDelete` or `ReadOnly` |
| notes | `string` | No | auto | Lock description |

## Supported scopes

| Scope | Pattern |
| --- | --- |
| Subscription | `/subscriptions/<sub-guid>` |
| Resource group | `/subscriptions/<sub-guid>/resourceGroups/<rg-name>` |
| Child resource | `/subscriptions/<sub-guid>/resourceGroups/<rg-name>/providers/<RP>/<type>/<name>` |
| Management group | `/providers/Microsoft.Management/managementGroups/<mg-name>` |

## Tearing down locked resources — 2-step procedure

`CanNotDelete` and `ReadOnly` locks block `terraform destroy` on the locked
resources. To dismantle a deployment that this module protects, do **not**
attempt a single `destroy` — Azure will refuse the operation with `Scope
locked` and the destroy plan will fail half-way, leaving orphan state.

Use this procedure instead:

```bash
# 1. Disable the locks. The for_each on the lock resource collapses
#    to {} and Terraform deletes every lock in this deployment.
TF_VAR_enable_locks=false terragrunt apply

# 2. Destroy the locked resources from their own deployments.
terragrunt run-all destroy --terragrunt-include-dir <locked-deployment>

# 3. (Optional) Re-enable the locks if you only wanted to remove a
#    subset of resources and the lock deployment must continue to
#    exist.
terragrunt apply
```

The same pattern applies if you only want to disable locks **temporarily**
(e.g. to apply a config change to a `ReadOnly`-locked resource): step 1,
make your change, then re-run step 3.

## Notes

### Lock duality with ResourceGroup module

The canonical `ResourceGroup` module exposes a per-entry inline `lock` field. If you use both, target different scopes or set explicit non-default `name` values on at least one side, otherwise both default names will collide on the same scope and Azure will return a `409 Conflict`.

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of lock key => lock ID |
| resources | Map of lock key => complete lock resource object |

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

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| locks | A map of management locks to create. The map key is deliberately<br>arbitrary to avoid issues where map keys may be unknown at plan time.<br><br>- `scope`      - (Required) Azure resource ID to lock (RG or resource).<br>- `name`       - (Optional) Lock name. Defaults to "lock-<map-key>" when omitted.<br>- `lock_level` - (Optional) Lock level: "CanNotDelete" or "ReadOnly". Defaults to "CanNotDelete".<br>- `notes`      - (Optional) Lock description.<br><br>WARNING: CanNotDelete locks also block `terraform destroy`.<br>Set enable\_locks = false for maintenance operations. | <pre>map(object({<br>    scope      = string<br>    name       = optional(string)<br>    lock_level = optional(string, "CanNotDelete")<br>    notes      = optional(string, "Lock applied by Terragrunt — Azure Landing Zone")<br>  }))</pre> | n/a | yes |
| enable\_locks | Set to false to disable all locks (e.g. for maintenance terraform destroy). | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of lock key => lock ID |
| resources | Map of lock key => complete lock resource object |
<!-- END_TF_DOCS -->
