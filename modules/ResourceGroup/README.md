# ResourceGroup

Creates **N Azure Resource Groups in one apply**, each with its own optional management lock and role assignments. Map-shape input — pass a single entry when you only need one RG; pass many for a subscription baseline (network, aks, aca, vm, shared, ...).

## Critical-pivot protection

`azurerm_resource_group.this` carries a **hardcoded** `lifecycle { prevent_destroy = true }`. This cannot be disabled via a variable. ResourceGroup is the foundational BASE module for the entire ALZ stack — destroying it cascades deletion of every resource inside the group. If you genuinely need to destroy a managed resource group you must fork this module and remove the lifecycle block explicitly, or use `terraform state rm` followed by an out-of-band `az group delete`.

## Breaking changes

### v0.2.76

The `moved` block that previously targeted `module.role_assignments.azurerm_role_assignment.this` has been **removed**. It was invalid: `module.role_assignments` is `for_each`-keyed by dynamic `"<rg_key>|<ra_key>"` composite keys and Terraform cannot resolve a keyless static `moved` block against a for_each collection.

**Action required for callers with pre-existing state:**

For each role assignment that Terraform reports as new (it was previously tracked at the bare `azurerm_role_assignment.this["<key>"]` address), run:

```sh
terraform state mv \
  'azurerm_role_assignment.this["<key>"]' \
  'module.role_assignments["<key>"].azurerm_role_assignment.this'
```

Replace `<key>` with the composite key (e.g. `network|reader`). Repeat for every role assignment entry. After the `state mv` commands, `terraform plan` should show no changes.

## Requirements

| Name | Version |
| --- | --- |
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| time | >= 0.9.0 |

## Naming

`rg-{subscription_acronym}-{environment}-{region_code}-{workload}` per entry. Override per-entry via `name`. Region can also be overridden per-entry (`region_code` + `location`) when one RG must sit in a different region than the set-level default (e.g. AVD control plane in WEU while session hosts stay in GWC).

## Usage (Terragrunt — multi-RG baseline)

```hcl
# landing-zone/corporate/shc/resource-group/terragrunt.hcl
include "root" { path = find_in_parent_folders("root.hcl") }
include "sub"  { path = find_in_parent_folders("corporate.hcl") }

terraform {
  source = "git::https://github.com/Kumo-Craft/terraform-azurerm-landing-zone.git//modules/ResourceGroup?ref=v0.2.89"
}

inputs = {
  resource_groups = {
    network = {
      workload = "network"
      lock     = { kind = "CanNotDelete" }
    }
    aks    = { workload = "aks" }
    aca    = { workload = "aca" }
    vm     = { workload = "vm" }
    shared = { workload = "shared", lock = { kind = "CanNotDelete" } }
  }
}
```

## Usage (Terragrunt — single RG)

```hcl
terraform {
  source = "git::https://github.com/Kumo-Craft/terraform-azurerm-landing-zone.git//modules/ResourceGroup?ref=v0.2.89"
}

inputs = {
  resource_groups = {
    only = { workload = "management" }
  }
}
```

Downstream consumer (Terragrunt dependency):

```hcl
dependency "rg" {
  config_path = "../resource-group"
  mock_outputs = {
    names = { network = "rg-shc-nprd-gwc-network" }
    ids   = { network = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shc-nprd-gwc-network" }
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  resource_group_name = dependency.rg.outputs.names["network"]
}
```

## Inputs

| Name | Type | Required | Description |
|---|---|---|---|
| `subscription_acronym` | `string` | yes | 2-5 lowercase letters (mgm, con, idn, sec, shc, ...) |
| `environment` | `string` | yes | 2-4 lowercase letters (prod, nprd) — auto-injected by `root.hcl` |
| `region_code` | `string` | yes | 2-5 lowercase letters (gwc, weu) — auto-injected by `root.hcl` |
| `location` | `string` | yes | Azure region (e.g. `germanywestcentral`) |
| `resource_groups` | `map(object)` | yes | Map of RGs to create. Key is opaque, used for output lookup. See per-entry fields below. |
| `tags` | `map(string)` | no | Set-level tags merged into every RG. Per-RG `tags` override on conflict. `CreatedOn` is auto-added. |

### `resource_groups[*]` fields

| Field | Type | Required | Description |
|---|---|---|---|
| `workload` | `string` | yes | Workload name. Final RG name = `rg-{acr}-{env}-{region}-{workload}`. Regex: `^[a-z][a-z0-9_-]{1,30}$` — 2–31 chars, must start with a lowercase letter, then lowercase letters, digits, hyphens, or underscores. |
| `name` | `string` | no | Explicit name override. Skips computed naming. |
| `location` | `string` | no | Override the set-level location for this specific RG. |
| `region_code` | `string` | no | Override the set-level region_code in the computed name. Set together with `location`. |
| `tags` | `map(string)` | no | Per-RG tags merged on top of set-level `tags`. |
| `lock` | `object({ kind, name?, notes? })` | no | Management lock. `kind`: `CanNotDelete` or `ReadOnly`. `notes` is ForceNew in the provider — any edit destroys+recreates the lock. |
| `role_assignments` | `map(object)` | no | Map of role assignments scoped to this RG. |

## Outputs

| Output | Description |
|---|---|
| `resource_groups` | `map({ id, name, location, tags })` keyed by input map key |
| `ids` | `map(string)` of RG IDs |
| `names` | `map(string)` of RG names |
| `resources` | Full `azurerm_resource_group` objects (advanced) |
| `role_assignment_ids` | `map(string)` of role assignment IDs, keyed `"<rg_key>\|<ra_key>"` |

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
| naming | ../Naming | n/a |
| role\_assignments | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Environment for naming convention (e.g. prod, nprd). Automatically injected by root.hcl. | `string` | n/a | yes |
| location | Azure region where all resource groups will be deployed. | `string` | n/a | yes |
| region\_code | Region code for naming convention (e.g. gwc, weu). Automatically injected by root.hcl. | `string` | n/a | yes |
| resource\_groups | Map of Resource Groups to create. Map key is an arbitrary identifier used for<br>output lookup (e.g. dependency.rg.outputs.resource\_groups["network"]).<br><br>Per-entry fields:<br>- `workload`         - (Required) Workload name. Final RG name = rg-{acr}-{env}-{region}-{workload}<br>- `name`             - (Optional) Explicit RG name override. If null, computed from naming.<br>- `location`         - (Optional) Override the set-level location for this specific RG. Useful when most<br>                       RGs sit in one region but a few must be elsewhere (e.g. AVD control plane forced<br>                       to westeurope while session hosts and storage stay in germanywestcentral).<br>- `region_code`      - (Optional) Override the set-level region\_code in the computed name. Should be<br>                       set together with `location` to keep the name aligned with the actual region<br>                       (e.g. location="westeurope" + region\_code="weu").<br>- `tags`             - (Optional) Per-RG tags. Merged on top of the set-level `tags`.<br>- `lock`             - (Optional) Management lock. { kind = "CanNotDelete"\|"ReadOnly", name = optional(string), notes = optional(string) }<br>- `role_assignments` - (Optional) Map of role assignments scoped to this RG. | <pre>map(object({<br>    workload    = string<br>    name        = optional(string)<br>    location    = optional(string)<br>    region_code = optional(string)<br>    tags        = optional(map(string), {})<br>    lock = optional(object({<br>      kind  = string<br>      name  = optional(string)<br>      notes = optional(string) # ForceNew in provider — changing destroys+recreates the lock.<br>    }))<br>    role_assignments = optional(map(object({<br>      role_definition_id_or_name             = string<br>      principal_id                           = string<br>      principal_type                         = optional(string)<br>      condition                              = optional(string)<br>      condition_version                      = optional(string)<br>      description                            = optional(string)<br>      skip_service_principal_aad_check       = optional(bool, false)<br>      delegated_managed_identity_resource_id = optional(string)<br>    })), {})<br>  }))</pre> | n/a | yes |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, con, idn, sec, shc). Applied to every RG in the set. | `string` | n/a | yes |
| tags | Tags applied to every RG in the set. Per-RG tags override these on conflict. Merged with auto-generated CreatedOn tag. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| ids | Map of resource group IDs keyed by the input map key. Convenience for `dependency.rg.outputs.ids["network"]`. |
| locations | Map of resource group locations keyed by the input map key. |
| names | Map of resource group names keyed by the input map key. |
| resource\_groups | Map of created resource groups keyed by the input map key. Each value: { id, name, location, tags }. |
| resources | Full azurerm\_resource\_group resource objects, keyed by input map key. |
| role\_assignment\_ids | Map of role assignment keys ("<rg\_key>\|<ra\_key>") to their Azure resource IDs. |
<!-- END_TF_DOCS -->
