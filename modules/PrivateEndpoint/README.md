# PrivateEndpoint

Creates one or more Azure Private Endpoints to securely connect PaaS services (Key Vault, Storage, ACR, SQL, etc.) to a private virtual network subnet. Supports static IP, custom NIC names, and DNS zone groups.

## Usage

### Standalone

```hcl
module "private_endpoint" {
  source = "github.com/John6810/terraform-azurerm-landing-zone//modules/PrivateEndpoint?ref=PrivateEndpoint/v1.0.0"

  location            = "germanywestcentral"
  resource_group_name = "rg-api-prod-gwc-aks"
  subnet_id           = "/subscriptions/.../subnets/snet-api-prod-gwc-pe"

  private_endpoints = {
    acr = {
      name              = "pep-api-prod-gwc-acr-001"
      resource_id       = "/subscriptions/.../registries/crapiprodgwc001"
      subresource_names = ["registry"]
      private_dns_zone_group = {
        private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.azurecr.io"]
      }
    }
    kv = {
      name               = "pep-api-prod-gwc-kv-001"
      resource_id        = "/subscriptions/.../vaults/kv-api-prod-gwc-apim"
      subresource_names  = ["vault"]
      private_ip_address = "10.238.2.10"
    }
  }

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/PrivateEndpoint"
}

inputs = {
  location            = include.root.inputs.location
  resource_group_name = dependency.rg.outputs.name
  subnet_id           = dependency.subnet.outputs.subnet_ids["snet-api-prod-gwc-pe"]

  private_endpoints = {
    acr = {
      name              = "pep-api-prod-gwc-acr-001"
      resource_id       = dependency.acr.outputs.id
      subresource_names = ["registry"]
    }
  }

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
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| subnet_id | Subnet ID for deploying PEs | `string` | -- | Yes |
| private_endpoints | Map of PE configurations. Key is arbitrary. | `map(object({...}))` | -- | Yes |
| tags | Common tags for all PEs | `map(string)` | `{}` | No |

### Private Endpoint Object

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| name | `string` | Yes | -- | Private Endpoint name |
| resource_id | `string` | Yes | -- | Target Azure resource ID |
| subresource_names | `list(string)` | Yes | -- | Subresources (e.g. `["vault"]`, `["blob"]`, `["registry"]`) |
| is_manual_connection | `bool` | No | `false` | Manual connection requiring approval |
| request_message | `string` | No | -- | Message for manual connections (required if manual) |
| private_ip_address | `string` | No | -- | Static private IP |
| member_name | `string` | No | `"default"` | Member name for IP config |
| custom_network_interface_name | `string` | No | -- | Custom NIC name |
| private_dns_zone_group | `object` | No | -- | DNS zone group (name + zone IDs) |
| tags | `map(string)` | No | `{}` | Endpoint-specific tags |

## Outputs

| Name | Description |
|------|-------------|
| resources | Map of key => complete PE resource object |
| ids | Map of key => PE ID |
| private_ip_addresses | Map of key => private IP address |
