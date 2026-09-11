# NatGateway

Creates a zone-redundant NAT Gateway using the StandardV2 SKU together with its associated public IP address. Uses the `azapi` provider because `azurerm` does not yet support the StandardV2 SKU.

## Usage

### Standalone

```hcl
module "nat_gateway" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/NatGateway?ref=v0.2.40"

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
