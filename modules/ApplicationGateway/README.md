# ApplicationGateway

Deploys an Azure Application Gateway v2 (WAF_v2 SKU) with a WAF Policy (Microsoft Default Rule Set 2.1 + Bot Manager), autoscaling, zone redundancy, and optional public IP. Includes a default placeholder backend for AGIC or manual configuration.

> **Secure by default — HTTPS listener.** The default (placeholder) listener terminates TLS (`protocol = "Https"`), so a real `terraform apply` requires an SSL certificate: set `ssl_certificate_key_vault_secret_id` to a Key Vault PFX secret ID and attach a UserAssigned identity (`identity_type` / `identity_ids`) with *Key Vault Certificate User* on the vault. The bootstrap listener/backend/routing blocks are in `ignore_changes`; AGIC (or manual config) manages the real listeners and certificates after create.

## Usage

### Standalone

```hcl
module "application_gateway" {
  source = "git::https://github.com/Kumo-Craft/Modules.git//modules/ApplicationGateway?ref=v0.2.89"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "001"
  location             = "germanywestcentral"
  resource_group_name  = "rg-api-prod-gwc-appgw"
  appgw_subnet_id      = "/subscriptions/.../subnets/snet-api-prod-gwc-appgw"

  create_public_ip   = false
  private_ip_address = "10.238.10.10"
  waf_mode           = "Prevention"
  min_capacity       = 1
  max_capacity       = 3

  tags = { Environment = "Production" }
}
```

### Terragrunt

```hcl
terraform {
  source = "${get_repo_root()}/modules/ApplicationGateway"
}

inputs = {
  subscription_acronym = include.sub.locals.subscription_acronym
  environment          = include.root.inputs.environment
  region_code          = include.root.inputs.region_code
  workload             = "001"
  location             = include.root.inputs.location
  resource_group_name  = dependency.rg.outputs.name
  appgw_subnet_id      = dependency.subnet.outputs.subnet_ids[include.sub.locals.networks.corp_apimanager.subnets.appgw.name]
  create_public_ip     = false
  private_ip_address   = "10.238.10.10"
  tags                 = include.root.inputs.common_tags
}
```

## Breaking Changes

### v0.2.81

- **`enable_http2` renamed to `http2_enabled`** (SOFT BREAKING). The `enable_http2` argument is the deprecated alias in the azurerm provider; `http2_enabled` is the canonical name. No state migration is needed — this is a variable rename only. Callers must update their input:

  ```hcl
  # Before (v0.2.80 and earlier)
  module "appgw" {
    enable_http2 = true
  }

  # After (v0.2.81+)
  module "appgw" {
    http2_enabled = true
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
| name | Explicit name. If null, computed from naming components. | `string` | `null` | No |
| subscription_acronym | Subscription acronym (e.g. api, con) | `string` | `null` | No |
| environment | Environment (e.g. prod, nprd) | `string` | `null` | No |
| region_code | Region code (e.g. gwc, weu) | `string` | `null` | No |
| workload | Workload name (e.g. apim, web) | `string` | `null` | No |
| location | Azure region | `string` | -- | Yes |
| resource_group_name | Resource group name | `string` | -- | Yes |
| appgw_subnet_id | Dedicated subnet ID for the Application Gateway | `string` | -- | Yes |
| create_public_ip | Create a public IP. WARNING: exposes AppGW to internet. Prod traffic must go through Palo Alto FW. | `bool` | `false` | No |
| private_ip_address | Static private IP for the private frontend. If null, dynamic allocation. | `string` | `null` | No |
| waf_mode | WAF mode: Detection or Prevention | `string` | `"Prevention"` | No |
| default_rule_set_version | Microsoft Default Rule Set version. Current GA = 2.1. | `string` | `"2.1"` | No |
| bot_manager_rule_set_version | Microsoft Bot Manager Rule Set version. Current GA = 1.1. | `string` | `"1.1"` | No |
| ssl_policy_type | SSL policy mode: Predefined or CustomV2. 'Custom' is deprecated. | `string` | `"Predefined"` | No |
| ssl_policy_name | Predefined SSL policy name. Default enforces TLS 1.2 only + strong ciphers. Set to null when ssl_policy_type = CustomV2. | `string` | `"AppGwSslPolicy20220101S"` | No |
| ssl_policy_min_protocol_version | Minimum TLS version when ssl_policy_type = CustomV2. Allowed: TLSv1_2, TLSv1_3. | `string` | `null` | No |
| ssl_policy_cipher_suites | Cipher suite list when ssl_policy_type = CustomV2. | `list(string)` | `null` | No |
| ssl_certificate_name | Logical name of the SSL certificate bound to the default HTTPS listener. | `string` | `"appgw-ssl-cert"` | No |
| ssl_certificate_key_vault_secret_id | Key Vault secret/certificate ID of the PFX cert for TLS termination on the default HTTPS listener. Required for a real apply (default listener is HTTPS-only). | `string` | `null` | No |
| http2_enabled | Enable HTTP/2 on frontend listeners. | `bool` | `true` | No |
| force_firewall_policy_association | Force the attached WAF policy to apply to ALL listeners. Recommended true for security baseline. | `bool` | `true` | No |
| identity_type | Identity type: 'UserAssigned' only. Set to null when no KV-managed certs are used. | `string` | `null` | No |
| identity_ids | List of UAMI resource IDs to attach. Required when identity_type = UserAssigned. | `list(string)` | `[]` | No |
| min_capacity | Minimum capacity (autoscale) | `number` | `1` | No |
| max_capacity | Maximum capacity (autoscale) | `number` | `3` | No |
| availability_zones | Availability zones | `list(string)` | `["1", "2", "3"]` | No |
| lock | Resource Lock configuration. Object with `kind` (CanNotDelete or ReadOnly) and optional `name`. | `object({kind=string, name=optional(string)})` | `null` | No |
| role_assignments | Map of role assignments scoped to the Application Gateway resource. | `map(object({...}))` | `{}` | No |
| tags | Tags | `map(string)` | `{}` | No |

## Outputs

| Name | Description | Sensitive |
|------|-------------|-----------|
| id | Application Gateway ID | No |
| name | Application Gateway name | No |
| waf_policy_id | WAF Policy ID | No |
| public_ip_address | Public IP address (if created) | No |
| private_ip_address | Private IP address of the frontend | No |
| resource | The complete Application Gateway resource object | Yes |
| role_assignment_ids | Map of role assignment IDs keyed by the role_assignments input map key. | No |
