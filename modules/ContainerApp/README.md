# ContainerApp

Deploys an Azure **Container App** (`Microsoft.App/containerApps`) onto a Container Apps Environment (see the [`ContainerAppEnvironment`](../ContainerAppEnvironment) module). Covers the full app surface: multi-container templates, probes, KEDA autoscaling, ingress (traffic split, CORS, IP rules), registries (ACR via managed identity), secrets (inline or Key Vault), Dapr, and managed identity.

## Secure-by-default choices

- **Ingress is internal by default** (`external_enabled = false`) — set it to `true` only to expose the app publicly.
- **Registry auth prefers managed identity** (`registry.identity`) over username/password.
- **Secrets prefer Key Vault references** (`key_vault_secret_id` + `identity`) over inline values.

## Usage

### Public web app, ACR pull via UAMI, KV-backed secret

```hcl
module "app" {
  source = "../ContainerApp"

  subscription_acronym = "api"
  environment          = "prod"
  region_code          = "gwc"
  workload             = "web"
  resource_group_name  = "rg-api-prod-gwc-aca"

  container_app_environment_id = module.aca_env.id
  revision_mode                = "Single"

  identity = {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }

  registries = [{
    server   = "myacr.azurecr.io"
    identity = azurerm_user_assigned_identity.aca.id # needs AcrPull on the registry
  }]

  secrets = [{
    name                = "db-password"
    key_vault_secret_id = "https://my-kv.vault.azure.net/secrets/db-password"
    identity            = azurerm_user_assigned_identity.aca.id # needs Key Vault Secrets User
  }]

  containers = [{
    name   = "web"
    image  = "myacr.azurecr.io/web:1.4.2"
    cpu    = 0.5
    memory = "1Gi"
    env = [
      { name = "ASPNETCORE_ENVIRONMENT", value = "Production" },
      { name = "DB_PASSWORD", secret_name = "db-password" },
    ]
    liveness_probe  = { port = 8080, transport = "HTTP", path = "/healthz" }
    readiness_probe = { port = 8080, transport = "HTTP", path = "/ready" }
  }]

  min_replicas = 1
  max_replicas = 10

  http_scale_rules = [{
    name                = "http-concurrency"
    concurrent_requests = 50
  }]

  ingress = {
    target_port      = 8080
    external_enabled = true
    transport        = "auto"
    # traffic_weights defaults to 100% latest revision
  }

  tags = { Environment = "Production" }
}
```

### Blue/green (Multiple revisions, traffic split)

```hcl
  revision_mode = "Multiple"
  ingress = {
    target_port      = 8080
    external_enabled = true
    traffic_weights = [
      { revision_suffix = "v2", percentage = 20 },
      { latest_revision = true, percentage = 80 },
    ]
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
| name | Explicit name (2-32). If null, `ca-{acr}-{env}-{region}-{workload}`. | `string` | `null` | No |
| subscription_acronym / environment / region_code / workload | Naming components | `string` | `null` | No |
| resource_group_name | Resource group | `string` | -- | Yes |
| container_app_environment_id | Parent environment ID | `string` | -- | Yes |
| revision_mode | `Single` / `Multiple` | `string` | `"Single"` | No |
| workload_profile_name | Environment workload profile (null = Consumption) | `string` | `null` | No |
| containers | App containers (name, image, cpu, memory, env, probes, volume_mounts) | `list(object)` | -- | Yes |
| init_containers | Init containers | `list(object)` | `[]` | No |
| min_replicas / max_replicas | Replica bounds (min 0 = scale-to-zero) | `number` | `null` | No |
| cooldown_period_in_seconds / polling_interval_in_seconds / termination_grace_period_seconds | Scaling/lifecycle timings | `number` | `null` | No |
| http_scale_rules / tcp_scale_rules / custom_scale_rules / azure_queue_scale_rules | KEDA scale rules | `list(object)` | `[]` | No |
| volumes | Template volumes (AzureFile/EmptyDir/NfsAzureFile/Secret) | `list(object)` | `[]` | No |
| ingress | Ingress (target_port, external_enabled, transport, traffic_weights, cors, ip rules) | `object` | `null` | No |
| identity | Managed identity | `object` | `null` | No |
| registries | Registries (identity XOR username/password_secret_name) | `list(object)` | `[]` | No |
| secrets | Secrets (inline value XOR key_vault_secret_id + identity) — sensitive | `list(object)` | `[]` | No |
| dapr | Dapr sidecar (app_id, app_port, app_protocol) | `object` | `null` | No |
| max_inactive_revisions | Inactive revisions to retain | `number` | `null` | No |
| lock | Management lock | `object` | `null` | No |
| tags | Tags | `map(string)` | `{}` | No |

## Outputs

| Name | Description |
|------|-------------|
| id | Container App resource ID |
| name | Container App name |
| latest_revision_fqdn | FQDN of the latest revision |
| latest_revision_name | Latest revision name |
| ingress_fqdn | Ingress FQDN (null if no ingress) |
| outbound_ip_addresses | Outbound public IPs |
| custom_domain_verification_id | For custom domain binding (sensitive) |
| identity_principal_id | System-assigned identity principal ID (null if none) |
| resource | Complete resource object (sensitive — carries secrets) |

## Notes

- **Secret references.** `env.secret_name`, `registry.password_secret_name`, and scale-rule `authentication.secret_name` all reference a `secrets[*].name` defined on this app.
- **Mutual exclusivity** (enforced by validation): registry auth = identity XOR username/password; secret = inline value XOR Key Vault reference (+ identity).
- **Traffic weights** only take effect with `revision_mode = "Multiple"`; the cumulative percentage must equal 100. With a single weight, this module defaults to 100% latest revision.
- **Ingress FQDN → DNS.** For a private environment, create a record in the environment's private DNS zone pointing at the environment `static_ip_address`.

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
| [azurerm_container_app.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app) | resource |
| [time_static.time](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/static) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| container\_app\_environment\_id | ID of the Container App Environment to run in (e.g. module.aca\_env.id). | `string` | n/a | yes |
| containers | One or more application containers. Each:<br>- `name`, `image`           - (Required)<br>- `cpu`, `memory`           - (Required) e.g. cpu = 0.25, memory = "0.5Gi" (must match an allowed combo).<br>- `args`, `command`         - (Optional) lists.<br>- `env`                     - (Optional) list of { name, value, secret\_name }. Use secret\_name to reference a `secrets` entry.<br>- `liveness_probe` / `readiness_probe` / `startup_probe` - (Optional) probe objects (see probe shape).<br>- `volume_mounts`           - (Optional) list of { name, path, sub\_path }. | <pre>list(object({<br>    name    = string<br>    image   = string<br>    cpu     = number<br>    memory  = string<br>    args    = optional(list(string))<br>    command = optional(list(string))<br>    env = optional(list(object({<br>      name        = string<br>      value       = optional(string)<br>      secret_name = optional(string)<br>    })), [])<br>    liveness_probe = optional(object({<br>      port                    = number<br>      transport               = string<br>      path                    = optional(string)<br>      host                    = optional(string)<br>      initial_delay           = optional(number)<br>      interval_seconds        = optional(number)<br>      timeout                 = optional(number)<br>      failure_count_threshold = optional(number)<br>      headers                 = optional(list(object({ name = string, value = string })), [])<br>    }))<br>    readiness_probe = optional(object({<br>      port                    = number<br>      transport               = string<br>      path                    = optional(string)<br>      host                    = optional(string)<br>      initial_delay           = optional(number)<br>      interval_seconds        = optional(number)<br>      timeout                 = optional(number)<br>      failure_count_threshold = optional(number)<br>      success_count_threshold = optional(number)<br>      headers                 = optional(list(object({ name = string, value = string })), [])<br>    }))<br>    startup_probe = optional(object({<br>      port                    = number<br>      transport               = string<br>      path                    = optional(string)<br>      host                    = optional(string)<br>      initial_delay           = optional(number)<br>      interval_seconds        = optional(number)<br>      timeout                 = optional(number)<br>      failure_count_threshold = optional(number)<br>      headers                 = optional(list(object({ name = string, value = string })), [])<br>    }))<br>    volume_mounts = optional(list(object({<br>      name     = string<br>      path     = string<br>      sub_path = optional(string)<br>    })), [])<br>  }))</pre> | n/a | yes |
| resource\_group\_name | Name of the resource group | `string` | n/a | yes |
| azure\_queue\_scale\_rules | Azure Storage Queue scale rules: list of { name, queue\_name, queue\_length, authentications }. | <pre>list(object({<br>    name         = string<br>    queue_name   = string<br>    queue_length = number<br>    authentications = list(object({<br>      secret_name       = string<br>      trigger_parameter = string<br>    }))<br>  }))</pre> | `[]` | no |
| cooldown\_period\_in\_seconds | Seconds to wait before scaling down again. Defaults to 300 (provider). | `number` | `null` | no |
| custom\_scale\_rules | Custom (KEDA) scale rules: list of { name, custom\_rule\_type, metadata = map, authentications }. | <pre>list(object({<br>    name             = string<br>    custom_rule_type = string<br>    metadata         = map(string)<br>    authentications = optional(list(object({<br>      secret_name       = string<br>      trigger_parameter = string<br>    })), [])<br>  }))</pre> | `[]` | no |
| dapr | Optional Dapr sidecar config: { app\_id, app\_port, app\_protocol (http\|grpc) }. | <pre>object({<br>    app_id       = string<br>    app_port     = optional(number)<br>    app_protocol = optional(string)<br>  })</pre> | `null` | no |
| environment | Environment for naming convention (e.g. prod, nprd) | `string` | `null` | no |
| http\_scale\_rules | HTTP scale rules: list of { name, concurrent\_requests, authentications = [{ secret\_name, trigger\_parameter }] }. | <pre>list(object({<br>    name                = string<br>    concurrent_requests = number<br>    authentications = optional(list(object({<br>      secret_name       = string<br>      trigger_parameter = string<br>    })), [])<br>  }))</pre> | `[]` | no |
| identity | Managed identity for the app (pull from ACR, read Key Vault secrets). type = SystemAssigned \| UserAssigned \| 'SystemAssigned, UserAssigned'; identity\_ids required for UserAssigned. | <pre>object({<br>    type         = string<br>    identity_ids = optional(list(string), [])<br>  })</pre> | `null` | no |
| ingress | Optional ingress. Omit for an app with no inbound HTTP/TCP.<br><br>- `target_port`                - (Required) Container port to route to.<br>- `external_enabled`           - (Optional) Expose outside the environment. Defaults to false (internal only — secure default).<br>- `transport`                  - (Optional) auto \| http \| http2 \| tcp. Defaults to auto.<br>- `allow_insecure_connections` - (Optional) Allow HTTP (no redirect to HTTPS). Defaults to false.<br>- `exposed_port`               - (Optional) Only valid with transport = tcp.<br>- `client_certificate_mode`    - (Optional) require \| accept \| ignore.<br>- `traffic_weights`            - (Optional) list of { percentage, latest\_revision, revision\_suffix, label }. Defaults to 100% latest.<br>- `cors`                       - (Optional) CORS policy object.<br>- `ip_security_restrictions`   - (Optional) list of { name, action (Allow/Deny — all must match), ip\_address\_range, description }. | <pre>object({<br>    target_port                = number<br>    external_enabled           = optional(bool, false)<br>    transport                  = optional(string, "auto")<br>    allow_insecure_connections = optional(bool, false)<br>    exposed_port               = optional(number)<br>    client_certificate_mode    = optional(string)<br>    traffic_weights = optional(list(object({<br>      percentage      = number<br>      latest_revision = optional(bool)<br>      revision_suffix = optional(string)<br>      label           = optional(string)<br>    })), [])<br>    cors = optional(object({<br>      allowed_origins           = list(string)<br>      allow_credentials_enabled = optional(bool)<br>      allowed_headers           = optional(list(string))<br>      allowed_methods           = optional(list(string))<br>      exposed_headers           = optional(list(string))<br>      max_age_in_seconds        = optional(number)<br>    }))<br>    ip_security_restrictions = optional(list(object({<br>      name             = string<br>      action           = string<br>      ip_address_range = string<br>      description      = optional(string)<br>    })), [])<br>  })</pre> | `null` | no |
| init\_containers | Optional init containers (run to completion before app containers start). Same shape as containers, without probes. cpu/memory optional. | <pre>list(object({<br>    name    = string<br>    image   = string<br>    cpu     = optional(number)<br>    memory  = optional(string)<br>    args    = optional(list(string))<br>    command = optional(list(string))<br>    env = optional(list(object({<br>      name        = string<br>      value       = optional(string)<br>      secret_name = optional(string)<br>    })), [])<br>    volume_mounts = optional(list(object({<br>      name     = string<br>      path     = string<br>      sub_path = optional(string)<br>    })), [])<br>  }))</pre> | `[]` | no |
| lock | Optional management lock (CanNotDelete or ReadOnly). | <pre>object({<br>    kind = string<br>    name = optional(string)<br>  })</pre> | `null` | no |
| max\_inactive\_revisions | Maximum number of inactive revisions to retain. | `number` | `null` | no |
| max\_replicas | Maximum number of replicas. | `number` | `null` | no |
| min\_replicas | Minimum number of replicas. Set to 0 to allow scale-to-zero. | `number` | `null` | no |
| name | Optional. Explicit Container App name (2-32 chars, lowercase letters/digits/hyphens, start/end alphanumeric). If null, computed as ca-{acr}-{env}-{region}-{workload}. | `string` | `null` | no |
| polling\_interval\_in\_seconds | KEDA polling interval in seconds. Defaults to 30 (provider). | `number` | `null` | no |
| region\_code | Region code for naming convention (e.g. gwc, weu) | `string` | `null` | no |
| registries | Container registries to pull images from. Per entry use EITHER managed identity OR<br>username + password\_secret\_name (mutually exclusive).<br><br>- `server`               - (Required) Registry hostname (e.g. myacr.azurecr.io).<br>- `identity`             - (Optional) UAMI resource ID (or "System") used to pull. Recommended.<br>- `username`             - (Optional) Admin username (requires password\_secret\_name).<br>- `password_secret_name` - (Optional) Name of a `secrets` entry holding the password. | <pre>list(object({<br>    server               = string<br>    identity             = optional(string)<br>    username             = optional(string)<br>    password_secret_name = optional(string)<br>  }))</pre> | `[]` | no |
| revision\_mode | Revision operational mode: 'Single' (one active revision) or 'Multiple' (traffic split via ingress traffic\_weight). | `string` | `"Single"` | no |
| revision\_suffix | Optional revision suffix (must be unique for the resource lifetime). If omitted, the service hashes one. | `string` | `null` | no |
| secrets | Secrets available to the app. Per entry use EITHER an inline `value` OR a Key Vault<br>reference (`key_vault_secret_id` + `identity`).<br><br>- `name`                - (Required) Secret name (referenced by env.secret\_name, registry.password\_secret\_name, scale-rule auth).<br>- `value`               - (Optional) Inline secret value (sensitive). Ignored if key\_vault\_secret\_id + identity set.<br>- `key_vault_secret_id` - (Optional) Key Vault secret ID (versioned or versionless).<br>- `identity`            - (Optional) UAMI resource ID or "System" used to read the KV secret. Required with key\_vault\_secret\_id. | <pre>list(object({<br>    name                = string<br>    value               = optional(string)<br>    key_vault_secret_id = optional(string)<br>    identity            = optional(string)<br>  }))</pre> | `[]` | no |
| subscription\_acronym | Subscription acronym for naming convention (e.g. mgm, api) | `string` | `null` | no |
| tags | Tags to apply to the Container App | `map(string)` | `{}` | no |
| tcp\_scale\_rules | TCP scale rules: list of { name, concurrent\_requests, authentications }. | <pre>list(object({<br>    name                = string<br>    concurrent_requests = number<br>    authentications = optional(list(object({<br>      secret_name       = string<br>      trigger_parameter = string<br>    })), [])<br>  }))</pre> | `[]` | no |
| termination\_grace\_period\_seconds | Seconds after SIGTERM before the process is forcibly killed. | `number` | `null` | no |
| volumes | Template volumes: list of { name, storage\_type (AzureFile/EmptyDir/NfsAzureFile/Secret), storage\_name, mount\_options }. | <pre>list(object({<br>    name          = string<br>    storage_type  = optional(string, "EmptyDir")<br>    storage_name  = optional(string)<br>    mount_options = optional(string)<br>  }))</pre> | `[]` | no |
| workload | Workload name for naming convention. Keep short — composed name must be <= 32 chars. | `string` | `null` | no |
| workload\_profile\_name | Name of the Environment workload profile to place this app on. Null = the default Consumption profile. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| custom\_domain\_verification\_id | The custom domain verification ID for binding custom domains to this app. |
| id | The Container App resource ID |
| identity\_principal\_id | The system-assigned identity principal ID (null when no system-assigned identity). Grant it AcrPull on the registry / Key Vault access. |
| ingress\_fqdn | The ingress FQDN (null when no ingress is configured). |
| latest\_revision\_fqdn | FQDN of the latest revision of the Container App. |
| latest\_revision\_name | Name of the latest Container App revision. |
| name | The Container App name |
| outbound\_ip\_addresses | Public IP addresses used by the Container App for outbound access. |
| resource | The complete Container App resource object. |
<!-- END_TF_DOCS -->
