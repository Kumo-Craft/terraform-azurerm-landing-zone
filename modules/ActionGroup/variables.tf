###############################################################
# MODULE: ActionGroup - Variables
###############################################################

###############################################################
# NAMING CONVENTION
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit name that bypasses the convention entirely — use for legacy resources. When null, the 4 house vars below must all be set."

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
  description = "Region code (e.g. gwc, weu)"

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = "ama"
  description = "Workload name (e.g. ama)"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  nullable    = false
}

###############################################################
# ACTION GROUP CONFIGURATION
###############################################################
variable "short_name" {
  type        = string
  default     = "ldz-ama"
  description = "Short name for the action group (max 12 chars)"

  validation {
    condition     = length(var.short_name) >= 1 && length(var.short_name) <= 12
    error_message = "short_name must be between 1 and 12 characters."
  }
}

variable "email_addresses" {
  type        = list(string)
  default     = []
  sensitive   = true
  description = "List of email addresses for alert email receivers"
}

variable "push_email_addresses" {
  type        = list(string)
  default     = []
  sensitive   = true
  description = "List of email addresses for Azure App push receivers"
}

###############################################################
# OPTIONAL RECEIVERS
###############################################################
variable "webhook_receivers" {
  description = "Map of webhook receivers. Useful for ServiceNow / PagerDuty / Logic App integration (AMBA baseline pattern). Key is a logical name (max 50 chars when truncated)."
  type = map(object({
    service_uri             = string
    use_common_alert_schema = optional(bool, true)
    # Optional AAD-backed webhook auth (only set when needed):
    aad_auth = optional(object({
      object_id      = string
      identifier_uri = optional(string, null)
      tenant_id      = optional(string, null)
    }), null)
  }))
  default  = {}
  nullable = false
  validation {
    condition     = alltrue([for w in values(var.webhook_receivers) : can(regex("^https?://", w.service_uri))])
    error_message = "Each webhook_receivers[*].service_uri must be a valid http(s) URL."
  }
}

variable "sms_receivers" {
  description = "Map of SMS receivers for on-call escalation. Key is a logical name (must be <= 50 chars)."
  type = map(object({
    country_code = string
    phone_number = string
  }))
  default  = {}
  nullable = false
  validation {
    condition     = alltrue([for s in values(var.sms_receivers) : can(regex("^[0-9]{1,4}$", s.country_code))])
    error_message = "Each sms_receivers[*].country_code must be 1-4 digits (no leading '+')."
  }
  validation {
    condition     = alltrue([for s in values(var.sms_receivers) : can(regex("^[0-9]{4,15}$", s.phone_number))])
    error_message = "Each sms_receivers[*].phone_number must be 4-15 digits (no country code prefix, no separators)."
  }
}

variable "arm_role_receivers" {
  description = "Map of ARM role receivers. Sends alerts to all principals with the specified built-in role at the alert resource's scope. Common AMBA pattern for Azure-native escalation. Common role_ids: Owner '8e3af657-a8ff-443c-a75c-2fe8c4bcb635', Contributor 'b24988ac-6180-42a0-ab88-20f7382dd24c', Monitoring Contributor '749f88d5-cbae-40b8-bcfc-e573ddc772fa', Monitoring Reader '43d0d8ad-25c7-4714-9337-8ba259a9fe05'. Key is logical name."
  type = map(object({
    role_id                 = string
    use_common_alert_schema = optional(bool, true)
  }))
  default  = {}
  nullable = false
  validation {
    condition     = alltrue([for r in values(var.arm_role_receivers) : can(regex("^[0-9a-f-]{36}$", r.role_id))])
    error_message = "Each arm_role_receivers[*].role_id must be a built-in role definition GUID (36-char hex with dashes)."
  }
}

###############################################################
# RESOURCE LOCK
###############################################################
variable "lock" {
  description = "Optional resource lock (CanNotDelete / ReadOnly) on the Action Group. CanNotDelete protects alert delivery from accidental deletion. Set to null to skip."
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
# TAGS
###############################################################
variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply"
}
