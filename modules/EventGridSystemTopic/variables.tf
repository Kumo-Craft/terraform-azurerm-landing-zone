###############################################################
# MODULE: EventGridSystemTopic - Variables
###############################################################

###############################################################
# NAMING CONVENTION (mirrors sibling modules)
# System topic:       egst-{acr}-{env}-{region}-{workload}
# Event subscription: evgs-{acr}-{env}-{region}-{workload}
# (Azure/naming v0.4.3 has no eventgrid_system_topic type, so we build
#  the slug manually — same approach as ServiceBus / ApplicationInsights.)
###############################################################
variable "name" {
  description = "Explicit system-topic name override (escape hatch). If null, derived via ../Naming (egst-{acr}-{env}-{region}-{workload})."
  type        = string
  default     = null
  nullable    = true

  # Naming components are required unless BOTH derived names are overridden —
  # event_subscription_name also falls back to the ../Naming suffix, so a bare
  # var.name override without naming vars would still fail inside ../Naming.
  validation {
    condition     = (var.name != null && var.event_subscription_name != null) || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    error_message = "Provide BOTH name and event_subscription_name, OR all 4 naming components (subscription_acronym, environment, region_code, workload)."
  }

  # ARM: Event Grid system topic name is 3-128 chars, alphanumerics and hyphens.
  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9-]{3,128}$", var.name))
    error_message = "name must be 3 to 128 characters: letters, digits and hyphens only."
  }
}

variable "event_subscription_name" {
  description = "Explicit event-subscription name override. If null, derived via ../Naming (evgs-{acr}-{env}-{region}-{workload})."
  type        = string
  default     = null
  nullable    = true

  # ARM: Event Grid event subscription name is 3-64 chars, alphanumerics and hyphens.
  validation {
    condition     = var.event_subscription_name == null || can(regex("^[a-zA-Z0-9-]{3,64}$", var.event_subscription_name))
    error_message = "event_subscription_name must be 3 to 64 characters: letters, digits and hyphens only."
  }
}

variable "subscription_acronym" {
  description = "Subscription acronym (e.g. mgm, con, sec)."
  type        = string
  default     = null

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  description = "Environment code (prod / nprd)."
  type        = string
  default     = null

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  description = "Region code (e.g. gwc)."
  type        = string
  default     = null

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  description = "Workload name (naming suffix segment)."
  type        = string
  default     = "keyvault"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# SYSTEM TOPIC — source = Key Vault
###############################################################
variable "key_vault_id" {
  description = "Full ARM ID of the source Key Vault. Sets source_resource_id; topic_type is hardcoded to 'Microsoft.KeyVault.vaults'. ForceNew — changing it recreates the topic."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.KeyVault/vaults/[^/]+$", var.key_vault_id))
    error_message = "key_vault_id must be a full Key Vault ARM ID (/subscriptions/<guid>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<name>)."
  }
}

variable "location" {
  description = "Azure region of the system topic. For a Key Vault (a regional source) this MUST be the Key Vault's region."
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "Resource group for the system topic and its event subscription (typically the Key Vault's resource group)."
  type        = string
  nullable    = false
}

###############################################################
# EVENT SUBSCRIPTION — destination = webhook
###############################################################
variable "webhook" {
  description = <<-EOT
  Webhook delivery target for the event subscription.
  - url                               : (Required) HTTPS endpoint (Logic App / Function / Automation runbook / your own handler). May embed a secret token → the whole object is sensitive.
  - max_events_per_batch              : (Optional) 1-5000.
  - preferred_batch_size_in_kilobytes : (Optional) up to 1024.
  - active_directory_tenant_id        : (Optional) Entra tenant ID for AAD-protected webhooks.
  - active_directory_app_id_or_uri    : (Optional) Entra app ID/URI for AAD-protected webhooks.
  EOT
  type = object({
    url                               = string
    max_events_per_batch              = optional(number)
    preferred_batch_size_in_kilobytes = optional(number)
    active_directory_tenant_id        = optional(string)
    active_directory_app_id_or_uri    = optional(string)
  })
  nullable  = false
  sensitive = true

  validation {
    condition     = can(regex("^https://", var.webhook.url))
    error_message = "webhook.url must be an HTTPS URL (Event Grid only delivers to HTTPS endpoints)."
  }
  validation {
    condition     = (var.webhook.active_directory_tenant_id == null) == (var.webhook.active_directory_app_id_or_uri == null)
    error_message = "Set BOTH webhook.active_directory_tenant_id and webhook.active_directory_app_id_or_uri, or neither."
  }
  validation {
    condition     = var.webhook.max_events_per_batch == null || (var.webhook.max_events_per_batch >= 1 && var.webhook.max_events_per_batch <= 5000)
    error_message = "webhook.max_events_per_batch must be between 1 and 5000."
  }
  validation {
    condition     = var.webhook.preferred_batch_size_in_kilobytes == null || (var.webhook.preferred_batch_size_in_kilobytes >= 1 && var.webhook.preferred_batch_size_in_kilobytes <= 1024)
    error_message = "webhook.preferred_batch_size_in_kilobytes must be between 1 and 1024."
  }
}

variable "included_event_types" {
  description = "Key Vault event types to subscribe to. Defaults to the near-expiry set (Secret/Certificate/Key). Each value must be a documented Microsoft.KeyVault.* event type."
  type        = list(string)
  default = [
    "Microsoft.KeyVault.SecretNearExpiry",
    "Microsoft.KeyVault.CertificateNearExpiry",
    "Microsoft.KeyVault.KeyNearExpiry",
  ]
  nullable = false

  validation {
    condition     = length(var.included_event_types) > 0
    error_message = "included_event_types must contain at least one event type."
  }
  validation {
    condition = alltrue([
      for e in var.included_event_types : contains([
        "Microsoft.KeyVault.CertificateNewVersionCreated",
        "Microsoft.KeyVault.CertificateNearExpiry",
        "Microsoft.KeyVault.CertificateExpired",
        "Microsoft.KeyVault.KeyNewVersionCreated",
        "Microsoft.KeyVault.KeyNearExpiry",
        "Microsoft.KeyVault.KeyExpired",
        "Microsoft.KeyVault.SecretNewVersionCreated",
        "Microsoft.KeyVault.SecretNearExpiry",
        "Microsoft.KeyVault.SecretExpired",
        "Microsoft.KeyVault.VaultAccessPolicyChanged",
      ], e)
    ])
    error_message = "Each included_event_types value must be a documented Microsoft.KeyVault.* event type."
  }
}

variable "event_delivery_schema" {
  description = "Schema Event Grid uses to deliver events. One of EventGridSchema, CloudEventSchemaV1_0, CustomInputSchema. ForceNew."
  type        = string
  default     = "EventGridSchema"
  nullable    = false

  validation {
    condition     = contains(["EventGridSchema", "CloudEventSchemaV1_0", "CustomInputSchema"], var.event_delivery_schema)
    error_message = "event_delivery_schema must be EventGridSchema, CloudEventSchemaV1_0 or CustomInputSchema."
  }
}

variable "advanced_filtering_on_arrays_enabled" {
  description = "Whether advanced filtering evaluates against array values in the event payload."
  type        = bool
  default     = false
  nullable    = false
}

variable "subject_filter" {
  description = "Optional subject prefix/suffix filter (e.g. limit to a specific secret name). Null = no subject filter."
  type = object({
    subject_begins_with = optional(string)
    subject_ends_with   = optional(string)
    case_sensitive      = optional(bool)
  })
  default  = null
  nullable = true

  validation {
    condition     = var.subject_filter == null || var.subject_filter.subject_begins_with != null || var.subject_filter.subject_ends_with != null
    error_message = "When subject_filter is set, provide at least one of subject_begins_with / subject_ends_with (else leave it null)."
  }
}

variable "retry_policy" {
  description = "Delivery retry policy. max_delivery_attempts 1-30 (Azure default 30); event_time_to_live 1-1440 minutes (Azure default 1440 = 24h)."
  type = object({
    max_delivery_attempts = optional(number, 30)
    event_time_to_live    = optional(number, 1440)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.retry_policy.max_delivery_attempts >= 1 && var.retry_policy.max_delivery_attempts <= 30
    error_message = "retry_policy.max_delivery_attempts must be between 1 and 30."
  }
  validation {
    condition     = var.retry_policy.event_time_to_live >= 1 && var.retry_policy.event_time_to_live <= 1440
    error_message = "retry_policy.event_time_to_live must be between 1 and 1440 (minutes)."
  }
}

variable "dead_letter" {
  description = "Optional dead-letter destination for undeliverable events (Storage blob container). Recommended for production so near-expiry events are never silently lost. Null = no dead-lettering."
  type = object({
    storage_account_id          = string
    storage_blob_container_name = string
  })
  default  = null
  nullable = true

  validation {
    condition     = var.dead_letter == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Storage/storageAccounts/[^/]+$", var.dead_letter.storage_account_id))
    error_message = "dead_letter.storage_account_id must be a full Storage Account ARM ID."
  }
}

###############################################################
# RESOURCE LOCK (optional) — mirrors sibling modules
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) applied to the system topic. Set to null to skip."
  type = object({
    kind = string
    name = optional(string, null)
  })
  default  = null
  nullable = true

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], var.lock.kind)
    error_message = "lock.kind must be 'CanNotDelete' or 'ReadOnly'."
  }
}

variable "tags" {
  description = "Tags applied to the system topic. (Event subscriptions have no tags argument.)"
  type        = map(string)
  default     = {}
  nullable    = false
}
