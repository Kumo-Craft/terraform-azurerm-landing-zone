###############################################################
# MODULE: ServiceBus - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit namespace name. If null, computed (sbns-{sub}-{env}-{region}-{workload}). Globally unique."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }

  validation {
    # SB namespace: 6-50 chars, start with a letter, end alphanumeric, letters/digits/hyphens.
    condition     = var.name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]{4,48}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 6-50 chars, start with a letter, end with a letter/digit, and contain only letters, digits and hyphens."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. mgm, con)"

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)"

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, frc)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = "01"
  nullable    = false
  description = "Workload suffix (e.g. 01)"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region"
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  nullable    = false
}

###############################################################
# NAMESPACE SETTINGS
###############################################################
variable "sku" {
  type        = string
  default     = "Standard"
  nullable    = false
  description = "Namespace SKU: Basic, Standard, or Premium. Premium is required for Private Endpoints, CMK, zone redundancy and messaging partitions."

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard, or Premium."
  }
}

variable "capacity" {
  type        = number
  default     = null
  description = "Premium messaging units (1, 2, 4, 8, 16). Only valid for the Premium SKU; null for Basic/Standard."

  validation {
    condition     = var.capacity == null || contains([1, 2, 4, 8, 16], var.capacity)
    error_message = "capacity must be one of 1, 2, 4, 8, 16 (Premium only)."
  }
}

variable "premium_messaging_partitions" {
  type        = number
  default     = null
  description = "Number of messaging partitions (Premium only; e.g. 1, 2, 4). Null for Basic/Standard."
}

variable "local_auth_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether SAS (shared access key) authentication is enabled. Default true. Set false to enforce Entra-only auth (recommended by MS — pair with RBAC data roles via role_assignments)."
}

variable "minimum_tls_version" {
  type        = string
  default     = "1.2"
  nullable    = false
  description = "Minimum TLS version. Default 1.2."

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be 1.0, 1.1, or 1.2."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether the namespace is reachable from the public internet. Default true. For a fully private namespace, use Premium + a Private Endpoint and set this false (Basic/Standard have no Private Endpoint)."
}

variable "identity" {
  description = "Optional managed identity (for CMK / Entra scenarios). type = SystemAssigned | UserAssigned | 'SystemAssigned, UserAssigned'."
  type = object({
    type         = string
    identity_ids = optional(list(string), null)
  })
  default = null

  validation {
    condition     = var.identity == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.identity.type)
    error_message = "identity.type must be SystemAssigned, UserAssigned, or 'SystemAssigned, UserAssigned'."
  }
}

variable "network_rule_set" {
  description = "Optional network rule set (Premium only). default_action Allow/Deny, optional IP CIDR rules and VNet subnet rules."
  type = object({
    default_action                = optional(string, "Deny")
    public_network_access_enabled = optional(bool, true)
    trusted_services_allowed      = optional(bool, true)
    ip_rules                      = optional(list(string), [])
    network_rules = optional(list(object({
      subnet_id                            = string
      ignore_missing_vnet_service_endpoint = optional(bool, false)
    })), [])
  })
  default = null

  validation {
    condition     = var.network_rule_set == null || contains(["Allow", "Deny"], var.network_rule_set.default_action)
    error_message = "network_rule_set.default_action must be Allow or Deny."
  }
}

variable "customer_managed_key" {
  description = "Optional CMK encryption (Premium only). Requires a user-assigned identity with get/wrap/unwrap on the Key Vault key. infrastructure_encryption_enabled = double encryption at rest (CKV_AZURE_199)."
  type = object({
    key_vault_key_id                  = string
    identity_id                       = string
    infrastructure_encryption_enabled = optional(bool, true)
  })
  default = null
}

###############################################################
# PRIVATE ENDPOINTS
###############################################################
variable "private_endpoints" {
  description = <<-EOT
  Map of Private Endpoints to create for the namespace (delegated to
  ../PrivateEndpoint, same pattern as SqlDatabase). The map key is arbitrary.
  Each endpoint targets the namespace with sub-resource `namespace` and
  resolves via `privatelink.servicebus.windows.net`. Requires the Premium SKU.

  - `subnet_id`                     - (Required) Subnet ID where the PE NIC lands.
  - `name`                          - (Optional) PE name. Defaults to `pe-{namespace}-{key}`.
  - `private_dns_zone_ids`          - (Optional) Private DNS zone IDs for `privatelink.servicebus.windows.net`. Omit when DNS is wired by an ALZ DINE policy (the PrivateEndpoint module ignores drift on the zone group).
  - `private_ip_address`            - (Optional) Static private IPv4 address (dynamic when null).
  - `member_name`                   - (Optional) IP config member name. Defaults to "namespace" (the Service Bus PE group id).
  - `custom_network_interface_name` - (Optional) Custom NIC name.
  - `tags`                          - (Optional) Per-endpoint tags (merged over the module tags).
  EOT
  type = map(object({
    subnet_id                     = string
    name                          = optional(string)
    private_dns_zone_ids          = optional(list(string))
    private_ip_address            = optional(string)
    member_name                   = optional(string, "namespace")
    custom_network_interface_name = optional(string)
    tags                          = optional(map(string), {})
  }))
  default  = {}
  nullable = false
}

###############################################################
# ENTITIES: QUEUES
###############################################################
variable "queues" {
  description = "Map of queues to create. Key is the queue name unless `name` is set. Null fields fall back to provider defaults."
  type = map(object({
    name                                    = optional(string, null)
    max_size_in_megabytes                   = optional(number, null)
    max_message_size_in_kilobytes           = optional(number, null)
    max_delivery_count                      = optional(number, null)
    lock_duration                           = optional(string, null)
    default_message_ttl                     = optional(string, null)
    auto_delete_on_idle                     = optional(string, null)
    duplicate_detection_history_time_window = optional(string, null)
    requires_session                        = optional(bool, null)
    requires_duplicate_detection            = optional(bool, null)
    dead_lettering_on_message_expiration    = optional(bool, null)
    partitioning_enabled                    = optional(bool, null)
    batched_operations_enabled              = optional(bool, null)
    express_enabled                         = optional(bool, null)
    forward_to                              = optional(string, null)
    forward_dead_lettered_messages_to       = optional(string, null)
    status                                  = optional(string, null)
  }))
  default  = {}
  nullable = false
}

###############################################################
# ENTITIES: TOPICS (+ nested SUBSCRIPTIONS)
###############################################################
variable "topics" {
  description = "Map of topics to create (Standard/Premium only). Each topic may declare a map of subscriptions. Null fields fall back to provider defaults."
  type = map(object({
    name                                    = optional(string, null)
    max_size_in_megabytes                   = optional(number, null)
    max_message_size_in_kilobytes           = optional(number, null)
    default_message_ttl                     = optional(string, null)
    auto_delete_on_idle                     = optional(string, null)
    duplicate_detection_history_time_window = optional(string, null)
    requires_duplicate_detection            = optional(bool, null)
    partitioning_enabled                    = optional(bool, null)
    batched_operations_enabled              = optional(bool, null)
    express_enabled                         = optional(bool, null)
    support_ordering                        = optional(bool, null)
    status                                  = optional(string, null)
    subscriptions = optional(map(object({
      name                                      = optional(string, null)
      max_delivery_count                        = optional(number, 10) # provider-required
      lock_duration                             = optional(string, null)
      default_message_ttl                       = optional(string, null)
      auto_delete_on_idle                       = optional(string, null)
      requires_session                          = optional(bool, null)
      dead_lettering_on_message_expiration      = optional(bool, null)
      dead_lettering_on_filter_evaluation_error = optional(bool, null)
      batched_operations_enabled                = optional(bool, null)
      forward_to                                = optional(string, null)
      forward_dead_lettered_messages_to         = optional(string, null)
      status                                    = optional(string, null)
    })), {})
  }))
  default  = {}
  nullable = false
}

###############################################################
# NAMESPACE AUTHORIZATION RULES (SAS)
###############################################################
variable "authorization_rules" {
  description = "Map of namespace-level SAS authorization rules. Only usable when local_auth_enabled = true. Key is the rule name."
  type = map(object({
    listen = optional(bool, true)
    send   = optional(bool, true)
    manage = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    # `manage` requires both listen and send (provider constraint).
    condition     = alltrue([for r in values(var.authorization_rules) : r.manage == false || (r.listen && r.send)])
    error_message = "An authorization rule with manage = true must also have listen = true and send = true."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}

###############################################################
# RESOURCE LOCK
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the namespace. Set to null to skip."
  type = object({
    kind = string
    name = optional(string, null)
  })
  default  = null
  nullable = true

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], coalesce(var.lock != null ? var.lock.kind : null, "CanNotDelete"))
    error_message = "lock.kind must be 'CanNotDelete' or 'ReadOnly'."
  }
}

###############################################################
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  description = "Map of role assignments at the namespace scope (delegated to ../RoleAssignment). Common roles: 'Azure Service Bus Data Sender/Receiver/Owner'. Default principal_type='ServicePrincipal'."
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string, "ServicePrincipal")
    condition                        = optional(string, null)
    condition_version                = optional(string, null)
    description                      = optional(string, null)
    skip_service_principal_aad_check = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for ra in values(var.role_assignments) : contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)])
    error_message = "Each role_assignments[*].principal_type must be one of User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}
