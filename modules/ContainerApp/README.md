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
