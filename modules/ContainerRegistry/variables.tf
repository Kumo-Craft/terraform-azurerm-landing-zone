###############################################################
# MODULE: ContainerRegistry - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# ACR name: alphanumeric only, no hyphens! 5-50 chars
# Convention: cr{subscription_acronym}{environment}{region_code}{workload}
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Explicit registry name. If null, computed automatically."

  validation {
    condition     = var.name == null || can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "ACR name must be 5-50 alphanumeric characters (no hyphens)."
  }

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set (legacy resource), or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided (convention naming)."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. api, mgm)"

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
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload name (e.g. 001). No hyphens — ACR names are alphanumeric only."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9]{0,15}$", var.workload))
    error_message = "workload must be 1-16 alphanumeric characters (no hyphens for ACR)."
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
# ACR CONFIGURATION
###############################################################
variable "sku" {
  type        = string
  description = "Registry SKU: Basic, Standard, Premium"
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be Basic, Standard, or Premium."
  }
}

variable "admin_enabled" {
  type        = bool
  description = "Enable admin account (not recommended in production)"
  default     = false
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Enable public network access"
  default     = false
}

variable "zone_redundancy_enabled" {
  type        = bool
  description = "Enable zone redundancy (Premium only)"
  default     = true
}

variable "data_endpoint_enabled" {
  type        = bool
  description = "Enable data endpoint (Premium only, required for PE)"
  default     = true
}

variable "georeplications" {
  description = "Geo-replication configuration (Premium only)"
  type = list(object({
    location                  = string
    zone_redundancy_enabled   = optional(bool, true)
    regional_endpoint_enabled = optional(bool, false)
    tags                      = optional(map(string), {})
  }))
  default = []
}

variable "network_rule_set" {
  description = "Network rule set configuration (Premium only)"
  type = object({
    default_action = optional(string, "Deny")
    ip_rule = optional(list(object({
      action   = optional(string, "Allow")
      ip_range = string
    })), [])
  })
  default = null

  validation {
    condition = var.network_rule_set == null || alltrue([
      for r in var.network_rule_set.ip_rule : r.action == "Allow"
    ])
    error_message = "ip_rule.action must be \"Allow\" — it is the only value accepted by the Azure API (azurerm schema: action is Required with a single valid value)."
  }
}

###############################################################
# SECURITY HARDENING (Premium SKU)
###############################################################
variable "anonymous_pull_enabled" {
  description = "Allow unauthenticated repository read access. Default false (security best-practice)."
  type        = bool
  default     = false
}

variable "export_policy_enabled" {
  description = <<-EOT
  Allow exporting repository artifacts (ACR import / export pipeline). Defaults to `false` (secure-by-default).

  **Azure constraint (MS Learn — data-loss-prevention):** `export_policy_enabled = false` is only valid when
  `public_network_access_enabled = false`. Setting export=false while public access is enabled is rejected by
  the Azure API and is caught by a plan-time precondition in this module.

  Set `export_policy_enabled = true` explicitly if you require artifact export (e.g. cross-registry import
  or export pipeline). Requires `sku = "Premium"`.
  EOT
  type        = bool
  default     = false
}

variable "retention_policy_in_days" {
  description = "Number of days to retain untagged manifests before auto-purge (Premium SKU only). null = manifests kept indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.retention_policy_in_days == null || (var.retention_policy_in_days >= 1 && var.retention_policy_in_days <= 365)
    error_message = "retention_policy_in_days must be between 1 and 365."
  }
}

variable "trust_policy_enabled" {
  description = <<-EOT
  Enable content trust — Docker Content Trust / Notary v1 image signing (Premium SKU only).

  **Deprecated by Azure (MS Learn — container-registry-content-trust-deprecation):** DCT cannot be
  enabled on new / never-enabled registries after 2026-05-31 and is fully retired on 2028-03-31.
  Setting this to `true` on a new registry will fail at the Azure API. Use the Notary Project
  (notation) for image signing instead. Kept for pre-existing registries only; defaults to `false`.
  Relates to Checkov CKV_AZURE_164 (skipped in main.tf — see rationale there).
  EOT
  type        = bool
  default     = false
}

variable "quarantine_policy_enabled" {
  description = <<-EOT
  Enable the ACR quarantine policy (Premium SKU only). Relates to Checkov CKV_AZURE_166.

  **PREVIEW feature (MS Learn).** When enabled, every pushed image is quarantined and ALL pulls fail
  until an external scan + `AcrQuarantineWriter` orchestrator marks each image verified. Do NOT enable
  unless you operate such a verify pipeline, or the registry becomes unusable. Defaults to `false`.
  EOT
  type        = bool
  default     = false
}

variable "network_rule_bypass_option" {
  description = "Whether to allow trusted Azure services to access a network-restricted registry. Allowed values: AzureServices, None. Defaults to AzureServices (non-breaking)."
  type        = string
  default     = "AzureServices"

  validation {
    condition     = contains(["AzureServices", "None"], var.network_rule_bypass_option)
    error_message = "network_rule_bypass_option must be \"AzureServices\" or \"None\"."
  }
}

###############################################################
# IDENTITY & CUSTOMER-MANAGED KEY (Premium SKU)
###############################################################
variable "identity_ids" {
  description = "Set of User-Assigned Identity IDs to attach to the registry. Required when customer_managed_key is set (the MI accesses Key Vault). Empty = no managed identity."
  type        = set(string)
  default     = []
}

variable "customer_managed_key" {
  description = "CMK encryption configuration (Premium SKU only). When set, requires one entry in identity_ids whose client_id matches identity_client_id below."
  type = object({
    key_vault_key_id   = string
    identity_client_id = string
  })
  default = null
}

###############################################################
# DIAGNOSTIC SETTINGS
###############################################################
variable "diagnostic_setting" {
  description = "Optional diagnostic settings emitting to a Log Analytics Workspace. Default categories cover ContainerRegistryRepositoryEvents + ContainerRegistryLoginEvents (audit trail for image pulls/pushes/login attempts)."
  type = object({
    name                       = optional(string, "diag")
    log_analytics_workspace_id = string
    categories                 = optional(list(string), ["ContainerRegistryRepositoryEvents", "ContainerRegistryLoginEvents"])
    metrics_enabled            = optional(bool, true)
  })
  default = null
}

###############################################################
# RBAC & LOCK
###############################################################
variable "role_assignments" {
  description = <<-EOT
  A map of role assignments to create on this ACR. The map key is deliberately
  arbitrary to avoid issues where map keys may be unknown at plan time.

  - `role_definition_id_or_name`             - (Required) The ID or name of the role definition (e.g. "AcrPull", "AcrPush").
  - `principal_id`                           - (Required) The ID of the principal to assign the role to.
  - `principal_type`                         - (Optional) User, Group, or ServicePrincipal.
  - `condition`                              - (Optional) ABAC condition.
  - `condition_version`                      - (Optional) Condition version ("2.0").
  - `description`                            - (Optional) Description.
  - `skip_service_principal_aad_check`       - (Optional) Skip AAD check.
  - `delegated_managed_identity_resource_id` - (Optional) Cross-tenant.
  EOT
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    principal_type                         = optional(string)
    condition                              = optional(string)
    condition_version                      = optional(string)
    description                            = optional(string)
    skip_service_principal_aad_check       = optional(bool, false)
    delegated_managed_identity_resource_id = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for ra in values(var.role_assignments) :
      ra.principal_type == null || contains(["User", "Group", "ServicePrincipal"], ra.principal_type)
    ])
    error_message = "principal_type must be User, Group, or ServicePrincipal (or null for auto-detect)."
  }
}

###############################################################
# PRIVATE ENDPOINTS
# Delegated to the in-repo PrivateEndpoint submodule. Target
# sub-resource is always "registry"; the private DNS zone is
# privatelink.azurecr.io. ACR Private Link requires the Premium SKU.
###############################################################
variable "private_endpoints" {
  description = <<-EOT
  A map of Private Endpoints to create for this registry. The map key is arbitrary.
  Each endpoint targets the registry with sub-resource `registry` and resolves via
  `privatelink.azurecr.io` (plus the data endpoint `<region>.data.privatelink.azurecr.io`).

  ACR Private Link is **Premium-only** — `sku` must be "Premium" when this map is non-empty.

  - `subnet_id`                     - (Required) Subnet for the Private Endpoint NIC (disable private-endpoint network policies on it).
  - `name`                          - (Optional) PE name. Defaults to `pe-{registry_name}-{key}`.
  - `private_dns_zone_ids`          - (Optional) Private DNS zone IDs for `privatelink.azurecr.io`. Omit when an ALZ DINE policy wires DNS.
  - `private_ip_address`            - (Optional) Static private IPv4 (dynamic when null).
  - `member_name`                   - (Optional) IP config member name. Defaults to "registry".
  - `custom_network_interface_name` - (Optional) Custom NIC name.
  - `tags`                          - (Optional) Per-endpoint tags.
  EOT
  type = map(object({
    subnet_id                     = string
    name                          = optional(string)
    private_dns_zone_ids          = optional(list(string))
    private_ip_address            = optional(string)
    member_name                   = optional(string, "registry")
    custom_network_interface_name = optional(string)
    tags                          = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for pe in var.private_endpoints : can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", pe.subnet_id))])
    error_message = "Each private endpoint subnet_id must be a valid subnet resource ID."
  }

  validation {
    condition     = alltrue([for pe in var.private_endpoints : pe.private_ip_address == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", pe.private_ip_address))])
    error_message = "Each private endpoint private_ip_address must be a valid IPv4 address."
  }
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string)
  })
  default     = null
  description = <<-EOT
  Controls the Resource Lock configuration for this resource.

  - `kind` - (Required) "CanNotDelete" or "ReadOnly".
  - `name` - (Optional) Lock name. Generated from kind if not specified.
  EOT

  validation {
    condition     = var.lock != null ? contains(["CanNotDelete", "ReadOnly"], var.lock.kind) : true
    error_message = "Lock kind must be either \"CanNotDelete\" or \"ReadOnly\"."
  }
}

###############################################################
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  description = "Tags"
  default     = {}
  nullable    = false
}
