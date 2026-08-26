###############################################################
# MODULE: ApplicationGateway - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name. If null, computed from naming components."

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
  description = "Subscription acronym (e.g. api, con)"

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
  description = "Workload name (e.g. apim, web)"

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
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

variable "appgw_subnet_id" {
  type        = string
  description = "Dedicated subnet ID for the Application Gateway"
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.appgw_subnet_id))
    error_message = "appgw_subnet_id must be a valid Azure Subnet resource ID."
  }
}

###############################################################
# OPTIONAL VARIABLES
###############################################################
variable "create_public_ip" {
  type        = bool
  description = "Create a public IP. WARNING: exposes AppGW to internet. Prod traffic must go through Palo Alto FW."
  default     = false
}

variable "private_ip_address" {
  type        = string
  description = "Static private IP for the private frontend. If null, dynamic allocation."
  default     = null

  validation {
    condition     = var.private_ip_address == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.private_ip_address))
    error_message = "private_ip_address must be a valid IPv4 address."
  }
}

variable "waf_mode" {
  type        = string
  description = "WAF mode: Detection or Prevention"
  default     = "Prevention"

  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention."
  }
}

variable "default_rule_set_version" {
  type        = string
  description = "Microsoft Default Rule Set version. Current GA = 2.1 (April 2026)."
  default     = "2.1"
}

variable "bot_manager_rule_set_version" {
  type        = string
  description = "Microsoft Bot Manager Rule Set version. Current GA = 1.1 (adds advanced bot detection over 1.0)."
  default     = "1.1"
}

###############################################################
# TLS / HTTP HARDENING
###############################################################
variable "ssl_policy_type" {
  type        = string
  description = "SSL policy mode: Predefined (use Azure-curated lists) or CustomV2 (set min_protocol_version + cipher_suites). 'Custom' is deprecated."
  default     = "Predefined"

  validation {
    condition     = contains(["Predefined", "Custom", "CustomV2"], var.ssl_policy_type)
    error_message = "ssl_policy_type must be 'Predefined', 'Custom', or 'CustomV2'."
  }
}

variable "ssl_policy_name" {
  type        = string
  description = "Predefined SSL policy name. Default 'AppGwSslPolicy20220101S' = TLS 1.2 only + strong ciphers (Microsoft 'strict' baseline). Set to null when ssl_policy_type = CustomV2."
  default     = "AppGwSslPolicy20220101S"
}

variable "ssl_policy_min_protocol_version" {
  type        = string
  description = "Minimum TLS version when ssl_policy_type = CustomV2. Allowed: TLSv1_2, TLSv1_3."
  default     = null
}

variable "ssl_policy_cipher_suites" {
  type        = list(string)
  description = "Cipher suite list when ssl_policy_type = CustomV2. See azurerm docs for the allowed suite names."
  default     = null
}

###############################################################
# TLS CERTIFICATE (for the default HTTPS listener)
###############################################################
variable "ssl_certificate_name" {
  type        = string
  description = "Logical name of the SSL certificate bound to the default HTTPS listener. Referenced by the listener even when no cert is supplied yet (AGIC/manual config manages real certs post-create)."
  default     = "appgw-ssl-cert"
  nullable    = false
}

variable "ssl_certificate_key_vault_secret_id" {
  type        = string
  description = <<-EOT
  Key Vault Secret ID of the (base64 unencrypted PFX) certificate used for TLS termination on the default HTTPS listener.

  The default listener is HTTPS-only (secure baseline). Deploying therefore REQUIRES a certificate:
  set this to a Key Vault secret/certificate ID. When set, an `ssl_certificate` block is created and
  the listener uses it. TLS termination with Key Vault certs requires a UserAssigned identity
  (see `identity_type` / `identity_ids`) granted "Key Vault Certificate User" on the vault, and is
  limited to the v2 SKUs (this module is WAF_v2). Use the versionless secret ID to enable auto-rotation.

  Left null by default so plan/validate stay green in bootstrap/AGIC-managed scenarios; a real apply
  needs a value (or a cert injected by AGIC on the ignore_changed listeners).
  EOT
  default     = null

  validation {
    condition     = var.ssl_certificate_key_vault_secret_id == null || can(regex("^https://[^/]+\\.vault\\.azure\\.net/(secrets|certificates)/", var.ssl_certificate_key_vault_secret_id))
    error_message = "ssl_certificate_key_vault_secret_id must be a Key Vault secret or certificate URI (https://<vault>.vault.azure.net/secrets/... or /certificates/...)."
  }
}

variable "http2_enabled" {
  type        = bool
  description = "Enable HTTP/2 on frontend listeners. Recommended (modern HTTP/2 multiplexing, lower latency)."
  default     = true
}

variable "force_firewall_policy_association" {
  type        = bool
  description = "Force the attached WAF policy to apply to ALL listeners on this AppGW, even if a different policy is bound at listener level. Recommended true for security baseline (prevents listener-level escape hatches)."
  default     = true
}

###############################################################
# IDENTITY (for Key Vault SSL cert access)
###############################################################
variable "identity_type" {
  type        = string
  description = "Identity type: 'UserAssigned' (only one supported by AppGW). Set to null when no KV-managed certs are used. AGIC also typically uses a UAMI to fetch certs from Key Vault."
  default     = null

  validation {
    condition     = var.identity_type == null || var.identity_type == "UserAssigned"
    error_message = "AppGW only supports 'UserAssigned' identity (no SystemAssigned)."
  }
}

variable "identity_ids" {
  type        = list(string)
  description = "List of UAMI resource IDs to attach. Required when identity_type = UserAssigned. The UAMI needs Key Vault Certificate User on the KV holding SSL certs."
  default     = []
  nullable    = false
}

variable "min_capacity" {
  type        = number
  description = "Minimum capacity (autoscale)"
  default     = 1
}

variable "max_capacity" {
  type        = number
  description = "Maximum capacity (autoscale)"
  default     = 3
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones"
  default     = ["1", "2", "3"]
}

###############################################################
# LOCK
###############################################################
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
# RBAC COMPOSITION
###############################################################
variable "role_assignments" {
  type = map(object({
    role_definition_id_or_name       = string
    principal_id                     = string
    principal_type                   = optional(string, "ServicePrincipal")
    condition                        = optional(string)
    condition_version                = optional(string)
    description                      = optional(string)
    skip_service_principal_aad_check = optional(bool, false)
  }))
  default     = {}
  nullable    = false
  description = "Map of role assignments scoped to the Application Gateway resource."

  validation {
    condition = alltrue([
      for ra in values(var.role_assignments) :
      contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], ra.principal_type)
    ])
    error_message = "principal_type must be one of User/Group/ServicePrincipal/ForeignGroup/Device."
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
