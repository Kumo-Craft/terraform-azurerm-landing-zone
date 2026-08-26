# NatGateway

Creates a zone-redundant NAT Gateway using the StandardV2 SKU together with its associated public IP address. Uses the `azapi` provider because `azurerm` does not yet support the StandardV2 SKU.

## Usage

### Standalone

```hcl
module "nat_gateway" {
  source = "github.com/Kumo-Craft/terraform-azurerm-landing-zone//modules/NatGateway?ref=v0.2.40"

  subscription_acronym = "con"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "untrust"
  location             = "germanywestcentral"
  resource_group_id    = "/subscriptions/.../resourceGroups/rg-con-prod-gwc-network"

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/NatGateway"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "untrust"
  location             = include.root.inputs.location
  resource_group_id    = dependency.rg.outputs.id
  tags                 = include.root.inputs.common_tags
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azurerm | ~> 4.0 |
| azapi | ~> 2.4 |
| time | >= 0.9 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | Optional. Explicit NAT Gateway name. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. con, mgm) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name (e.g. untrust) | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_id | Resource group ID (azapi parent_id) | `string` | -- | Yes |
| tags | Tags to assign | `map(string)` | `{}` | No |
| idle_timeout_in_minutes | Idle timeout in minutes (4-120) | `number` | `4` | No |
| zones | Availability zones for the NAT Gateway and Public IP | `list(string)` | `["1", "2", "3"]` | No |
| additional_public_ips | Optional additional PIPs to attach (max 15, 16 total). Map key = name suffix. | `map(object({zones=optional(list(string))}))` | `{}` | No |
| lock | Optional management lock to protect egress (`{kind, name?}`) | `object({...})` | `null` | No |

### Multi-PIP example

NAT Gateways scale outbound throughput by attaching multiple public IPs
(up to 16). Each extra PIP gets +64K SNAT ports per associated subnet.

```hcl
additional_public_ips = {
  "02" = {}                    # pip-ng-...-02, default zones
  "03" = { zones = ["1"] }     # pip-ng-...-03, pinned to AZ1
}
```

This adds `pip-<name>-02` and `pip-<name>-03` alongside the base
`pip-<name>`. Outputs `additional_public_ip_addresses` /
`additional_public_ip_ids` expose the map; `all_public_ip_addresses`
gives the flat list (base + additional).

### Locking

Destroying a NAT Gateway breaks egress for every subnet it serves.
For production deployments, set:

```hcl
lock = { kind = "CanNotDelete" }
```

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the NAT Gateway |
| name | The name of the NAT Gateway |
| public_ip_address | The public IP address of the base PIP |
| public_ip_id | The ID of the base public IP |
| additional_public_ip_addresses | Map of additional PIP key => address (empty if none) |
| additional_public_ip_ids | Map of additional PIP key => resource ID |
| all_public_ip_addresses | Flat list of all attached public IP addresses (base + additional) |

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.12.0 |
| azapi | ~> 2.4 |
| azurerm | ~> 4.0 |
| time | >= 0.9 |

## Providers

| Name | Version |
|------|---------|
| azapi | ~> 2.4 |
| time | >= 0.9 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| lock | ../ResourceLock | n/a |
| naming | ../Naming | n/a |
| rbac | ../RoleAssignment | n/a |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.additional_public_ip](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.nat_gateway](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.public_ip](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region | `string` | n/a | yes |
| resource\_group\_id | Resource group ID (azapi parent\_id) | `string` | n/a | yes |
| additional\_public\_ips | Optional additional public IPs to attach to the NAT Gateway. The base<br>PIP (pip-<name>) is always created; entries here add pip-<name>-<key><br>alongside. Map key becomes the suffix (e.g. "02" → pip-<name>-02).<br>Azure caps a NAT Gateway at 16 attached public IPs total — this map is<br>capped at 15 (16 total including the base PIP).<br><br>- `zones` - (Optional) Per-PIP zones override. Defaults to var.zones. | <pre>map(object({<br>    zones = optional(list(string))<br>  }))</pre> | `{}` | no |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | no |
| idle\_timeout\_in\_minutes | Idle timeout in minutes (4-120) | `number` | `4` | no |
| lock | Optional management lock on the NAT Gateway. Destroying a NAT Gateway<br>breaks egress on every subnet associated with it — set kind =<br>"CanNotDelete" in production to require an explicit unlock before<br>teardown.<br><br>- `kind` - (Required) "CanNotDelete" or "ReadOnly".<br>- `name` - (Optional) Lock name. Defaults to "lock-<kind>". | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| name | Optional. Explicit NAT Gateway name. If null, computed from naming components. | `string` | `null` | no |
| public\_ip\_prefix\_ids | Map of existing Public IP Prefix IDs to associate with this NAT Gateway. Key is a logical name. Each prefix can be a /28-/31 block of sequential IPs (16/8/4/2 IPs respectively) — useful for BGP advertisement or firewall allow-listing where predictable CIDR is required. Composes with var.additional\_public\_ips (both can coexist). | `map(string)` | `{}` | no |
| region\_code | Region code (e.g. gwc, weu) | `string` | `null` | no |
| role\_assignments | Map of role assignments at the NAT Gateway scope. Common for granting 'Network Contributor' to policy-managed identities. Default principal\_type='ServicePrincipal' (network resources rarely user-assigned). | <pre>map(object({<br>    role_definition_id_or_name       = string<br>    principal_id                     = string<br>    principal_type                   = optional(string, "ServicePrincipal")<br>    condition                        = optional(string, null)<br>    condition_version                = optional(string, null)<br>    description                      = optional(string, null)<br>    skip_service_principal_aad_check = optional(bool, false)<br>  }))</pre> | `{}` | no |
| subscription\_acronym | Subscription acronym (e.g. con, mgm) | `string` | `null` | no |
| tags | Tags to assign | `map(string)` | `{}` | no |
| workload | Workload name (e.g. untrust) | `string` | `null` | no |
| zones | Availability Zones for the NAT Gateway and base Public IP. StandardV2 SKU supports zone-redundancy with ['1','2','3']. Pass [] for no-zone (regional) deployment with no AZ constraint. Note: the original Standard SKU only supports single-zone or no-zone — this module uses StandardV2 which adds zone-redundancy. | `list(string)` | <pre>[<br>  "1",<br>  "2",<br>  "3"<br>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| additional\_public\_ip\_addresses | Map of additional public IP key => address (empty when no additional PIPs are configured). |
| additional\_public\_ip\_ids | Map of additional public IP key => resource ID. |
| all\_public\_ip\_addresses | Flat list of all public IP addresses attached to the NAT Gateway (base + additional). |
| id | The ID of the NAT Gateway |
| lock\_id | Management lock ID (null if var.lock is null) |
| name | The name of the NAT Gateway |
| public\_ip\_address | The public IP address of the base NAT Gateway PIP |
| public\_ip\_id | The ID of the base public IP |
| public\_ip\_prefix\_ids | Map of logical name => associated public IP prefix ID |
| resource | Full NAT Gateway azapi resource object |
| role\_assignment\_ids | Map of role assignment logical key => role assignment ID |
<!-- END_TF_DOCS -->
