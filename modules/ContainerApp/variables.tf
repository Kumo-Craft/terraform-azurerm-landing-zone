###############################################################
# MODULE: ContainerApp - Variables
# Azure Container App (Microsoft.App/containerApps) — runs on a
# Container Apps Environment (see the ContainerAppEnvironment module).
#
# NAMING
# Convention: ca-{subscription_acronym}-{environment}-{region_code}-{workload}
#
# XOR escape hatch:
#   var.name != null  → explicit name used verbatim
#   var.name == null  → all 4 convention components required
###############################################################

variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit Container App name (2-32 chars, lowercase letters/digits/hyphens, start/end alphanumeric). If null, computed as ca-{acr}-{env}-{region}-{workload}."

  validation {
    condition     = var.name == null || (length(var.name) >= 2 && length(var.name) <= 32 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name)))
    error_message = "Name must be 2-32 chars, lowercase letters/digits/hyphens, start and end alphanumeric."
  }

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym for naming convention (e.g. mgm, api)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment for naming convention (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code for naming convention (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name for naming convention. Keep short — composed name must be <= 32 chars."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9-]{0,15}$", var.workload))
    error_message = "workload must be 1 to 16 characters: lowercase letters, digits, hyphens."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  nullable    = false
}

variable "container_app_environment_id" {
  type        = string
  description = "ID of the Container App Environment to run in (e.g. module.aca_env.id)."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.App/managedEnvironments/[^/]+$", var.container_app_environment_id))
    error_message = "container_app_environment_id must be a valid Microsoft.App/managedEnvironments resource ID."
  }
}

variable "revision_mode" {
  type        = string
  description = "Revision operational mode: 'Single' (one active revision) or 'Multiple' (traffic split via ingress traffic_weight)."
  default     = "Single"

  validation {
    condition     = contains(["Single", "Multiple"], var.revision_mode)
    error_message = "revision_mode must be 'Single' or 'Multiple'."
  }
}

variable "workload_profile_name" {
  type        = string
  description = "Name of the Environment workload profile to place this app on. Null = the default Consumption profile."
  default     = null
}

variable "max_inactive_revisions" {
  type        = number
  description = "Maximum number of inactive revisions to retain."
  default     = null
}

###############################################################
# TEMPLATE — containers + scaling
###############################################################
variable "containers" {
  description = <<-EOT
  One or more application containers. Each:
  - `name`, `image`           - (Required)
  - `cpu`, `memory`           - (Required) e.g. cpu = 0.25, memory = "0.5Gi" (must match an allowed combo).
  - `args`, `command`         - (Optional) lists.
  - `env`                     - (Optional) list of { name, value, secret_name }. Use secret_name to reference a `secrets` entry.
  - `liveness_probe` / `readiness_probe` / `startup_probe` - (Optional) probe objects (see probe shape).
  - `volume_mounts`           - (Optional) list of { name, path, sub_path }.
  EOT
  type = list(object({
    name    = string
    image   = string
    cpu     = number
    memory  = string
    args    = optional(list(string))
    command = optional(list(string))
    env = optional(list(object({
      name        = string
      value       = optional(string)
      secret_name = optional(string)
    })), [])
    liveness_probe = optional(object({
      port                    = number
      transport               = string
      path                    = optional(string)
      host                    = optional(string)
      initial_delay           = optional(number)
      interval_seconds        = optional(number)
      timeout                 = optional(number)
      failure_count_threshold = optional(number)
      headers                 = optional(list(object({ name = string, value = string })), [])
    }))
    readiness_probe = optional(object({
      port                    = number
      transport               = string
      path                    = optional(string)
      host                    = optional(string)
      initial_delay           = optional(number)
      interval_seconds        = optional(number)
      timeout                 = optional(number)
      failure_count_threshold = optional(number)
      success_count_threshold = optional(number)
      headers                 = optional(list(object({ name = string, value = string })), [])
    }))
    startup_probe = optional(object({
      port                    = number
      transport               = string
      path                    = optional(string)
      host                    = optional(string)
      initial_delay           = optional(number)
      interval_seconds        = optional(number)
      timeout                 = optional(number)
      failure_count_threshold = optional(number)
      headers                 = optional(list(object({ name = string, value = string })), [])
    }))
    volume_mounts = optional(list(object({
      name     = string
      path     = string
      sub_path = optional(string)
    })), [])
  }))
  nullable = false

  validation {
    condition     = length(var.containers) >= 1
    error_message = "At least one container must be defined."
  }
}

variable "init_containers" {
  description = "Optional init containers (run to completion before app containers start). Same shape as containers, without probes. cpu/memory optional."
  type = list(object({
    name    = string
    image   = string
    cpu     = optional(number)
    memory  = optional(string)
    args    = optional(list(string))
    command = optional(list(string))
    env = optional(list(object({
      name        = string
      value       = optional(string)
      secret_name = optional(string)
    })), [])
    volume_mounts = optional(list(object({
      name     = string
      path     = string
      sub_path = optional(string)
    })), [])
  }))
  default  = []
  nullable = false
}

variable "min_replicas" {
  type        = number
  description = "Minimum number of replicas. Set to 0 to allow scale-to-zero."
  default     = null
}

variable "max_replicas" {
  type        = number
  description = "Maximum number of replicas."
  default     = null
}

variable "revision_suffix" {
  type        = string
  description = "Optional revision suffix (must be unique for the resource lifetime). If omitted, the service hashes one."
  default     = null
}

variable "cooldown_period_in_seconds" {
  type        = number
  description = "Seconds to wait before scaling down again. Defaults to 300 (provider)."
  default     = null
}

variable "polling_interval_in_seconds" {
  type        = number
  description = "KEDA polling interval in seconds. Defaults to 30 (provider)."
  default     = null
}

variable "termination_grace_period_seconds" {
  type        = number
  description = "Seconds after SIGTERM before the process is forcibly killed."
  default     = null
}

###############################################################
# SCALE RULES (KEDA)
###############################################################
variable "http_scale_rules" {
  description = "HTTP scale rules: list of { name, concurrent_requests, authentications = [{ secret_name, trigger_parameter }] }."
  type = list(object({
    name                = string
    concurrent_requests = number
    authentications = optional(list(object({
      secret_name       = string
      trigger_parameter = string
    })), [])
  }))
  default  = []
  nullable = false
}

variable "tcp_scale_rules" {
  description = "TCP scale rules: list of { name, concurrent_requests, authentications }."
  type = list(object({
    name                = string
    concurrent_requests = number
    authentications = optional(list(object({
      secret_name       = string
      trigger_parameter = string
    })), [])
  }))
  default  = []
  nullable = false
}

variable "custom_scale_rules" {
  description = "Custom (KEDA) scale rules: list of { name, custom_rule_type, metadata = map, authentications }."
  type = list(object({
    name             = string
    custom_rule_type = string
    metadata         = map(string)
    authentications = optional(list(object({
      secret_name       = string
      trigger_parameter = string
    })), [])
  }))
  default  = []
  nullable = false
}

variable "azure_queue_scale_rules" {
  description = "Azure Storage Queue scale rules: list of { name, queue_name, queue_length, authentications }."
  type = list(object({
    name         = string
    queue_name   = string
    queue_length = number
    authentications = list(object({
      secret_name       = string
      trigger_parameter = string
    }))
  }))
  default  = []
  nullable = false
}

###############################################################
# VOLUMES
###############################################################
variable "volumes" {
  description = "Template volumes: list of { name, storage_type (AzureFile/EmptyDir/NfsAzureFile/Secret), storage_name, mount_options }."
  type = list(object({
    name          = string
    storage_type  = optional(string, "EmptyDir")
    storage_name  = optional(string)
    mount_options = optional(string)
  }))
  default  = []
  nullable = false
}

###############################################################
# INGRESS
###############################################################
variable "ingress" {
  description = <<-EOT
  Optional ingress. Omit for an app with no inbound HTTP/TCP.

  - `target_port`                - (Required) Container port to route to.
  - `external_enabled`           - (Optional) Expose outside the environment. Defaults to false (internal only — secure default).
  - `transport`                  - (Optional) auto | http | http2 | tcp. Defaults to auto.
  - `allow_insecure_connections` - (Optional) Allow HTTP (no redirect to HTTPS). Defaults to false.
  - `exposed_port`               - (Optional) Only valid with transport = tcp.
  - `client_certificate_mode`    - (Optional) require | accept | ignore.
  - `traffic_weights`            - (Optional) list of { percentage, latest_revision, revision_suffix, label }. Defaults to 100% latest.
  - `cors`                       - (Optional) CORS policy object.
  - `ip_security_restrictions`   - (Optional) list of { name, action (Allow/Deny — all must match), ip_address_range, description }.
  EOT
  type = object({
    target_port                = number
    external_enabled           = optional(bool, false)
    transport                  = optional(string, "auto")
    allow_insecure_connections = optional(bool, false)
    exposed_port               = optional(number)
    client_certificate_mode    = optional(string)
    traffic_weights = optional(list(object({
      percentage      = number
      latest_revision = optional(bool)
      revision_suffix = optional(string)
      label           = optional(string)
    })), [])
    cors = optional(object({
      allowed_origins           = list(string)
      allow_credentials_enabled = optional(bool)
      allowed_headers           = optional(list(string))
      allowed_methods           = optional(list(string))
      exposed_headers           = optional(list(string))
      max_age_in_seconds        = optional(number)
    }))
    ip_security_restrictions = optional(list(object({
      name             = string
      action           = string
      ip_address_range = string
      description      = optional(string)
    })), [])
  })
  default = null

  validation {
    condition     = var.ingress == null || contains(["auto", "http", "http2", "tcp"], var.ingress.transport)
    error_message = "ingress.transport must be 'auto', 'http', 'http2' or 'tcp'."
  }

  validation {
    condition     = var.ingress == null || var.ingress.client_certificate_mode == null || contains(["require", "accept", "ignore"], var.ingress.client_certificate_mode)
    error_message = "ingress.client_certificate_mode must be 'require', 'accept' or 'ignore'."
  }

  validation {
    condition     = var.ingress == null || alltrue([for r in var.ingress.ip_security_restrictions : contains(["Allow", "Deny"], r.action)])
    error_message = "Each ingress.ip_security_restrictions[*].action must be 'Allow' or 'Deny' (and all must be the same)."
  }
}

###############################################################
# IDENTITY / REGISTRY / SECRETS / DAPR
###############################################################
variable "identity" {
  description = "Managed identity for the app (pull from ACR, read Key Vault secrets). type = SystemAssigned | UserAssigned | 'SystemAssigned, UserAssigned'; identity_ids required for UserAssigned."
  type = object({
    type         = string
    identity_ids = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.identity == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], try(var.identity.type, ""))
    error_message = "identity.type must be 'SystemAssigned', 'UserAssigned' or 'SystemAssigned, UserAssigned'."
  }

  validation {
    condition     = var.identity == null || !can(regex("UserAssigned", var.identity.type)) || length(var.identity.identity_ids) > 0
    error_message = "identity.identity_ids must be set when identity.type includes 'UserAssigned'."
  }
}

variable "registries" {
  description = <<-EOT
  Container registries to pull images from. Per entry use EITHER managed identity OR
  username + password_secret_name (mutually exclusive).

  - `server`               - (Required) Registry hostname (e.g. myacr.azurecr.io).
  - `identity`             - (Optional) UAMI resource ID (or "System") used to pull. Recommended.
  - `username`             - (Optional) Admin username (requires password_secret_name).
  - `password_secret_name` - (Optional) Name of a `secrets` entry holding the password.
  EOT
  type = list(object({
    server               = string
    identity             = optional(string)
    username             = optional(string)
    password_secret_name = optional(string)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for r in var.registries : (r.identity != null) != (r.username != null)])
    error_message = "Each registry must use EXACTLY ONE of identity or username (with password_secret_name)."
  }
}

variable "secrets" {
  description = <<-EOT
  Secrets available to the app. Per entry use EITHER an inline `value` OR a Key Vault
  reference (`key_vault_secret_id` + `identity`).

  - `name`                - (Required) Secret name (referenced by env.secret_name, registry.password_secret_name, scale-rule auth).
  - `value`               - (Optional) Inline secret value (sensitive). Ignored if key_vault_secret_id + identity set.
  - `key_vault_secret_id` - (Optional) Key Vault secret ID (versioned or versionless).
  - `identity`            - (Optional) UAMI resource ID or "System" used to read the KV secret. Required with key_vault_secret_id.
  EOT
  type = list(object({
    name                = string
    value               = optional(string)
    key_vault_secret_id = optional(string)
    identity            = optional(string)
  }))
  default   = []
  nullable  = false
  sensitive = true # entries may carry inline secret values

  validation {
    condition     = alltrue([for s in var.secrets : s.key_vault_secret_id == null || s.identity != null])
    error_message = "A secret using key_vault_secret_id must also set identity (UAMI resource ID or \"System\")."
  }
}

variable "dapr" {
  description = "Optional Dapr sidecar config: { app_id, app_port, app_protocol (http|grpc) }."
  type = object({
    app_id       = string
    app_port     = optional(number)
    app_protocol = optional(string)
  })
  default = null

  validation {
    condition     = var.dapr == null || var.dapr.app_protocol == null || contains(["http", "grpc"], var.dapr.app_protocol)
    error_message = "dapr.app_protocol must be 'http' or 'grpc'."
  }
}

###############################################################
# LOCK & TAGS
###############################################################
variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = "Optional management lock (CanNotDelete or ReadOnly)."

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the Container App"
  default     = {}
  nullable    = false
}
