###############################################################
# MODULE: SecurityCenterSubscription - Variables
###############################################################

variable "subscription_id" {
  type        = string
  nullable    = false
  description = <<-EOT
  Subscription the Microsoft Defender for Cloud security contact applies to. Accepts a
  bare GUID or a full /subscriptions/<guid> path (normalized in main.tf).

  With the azapi rewrite this is now FUNCTIONAL, not just an assertion: it is the
  `parent_id` of the securityContacts resource, so the contact is created on exactly this
  subscription (the azapi provider's credentials must have access to it). This supersedes
  the previous client_config precondition guardrail (PR #148), which existed only because
  the old azurerm_security_center_contact had no subscription argument.
  EOT

  validation {
    condition     = can(regex("^(/subscriptions/)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID or a /subscriptions/<guid> path."
  }
}

variable "email" {
  type        = string
  nullable    = false
  description = "Security contact email(s) that receive Microsoft Defender for Cloud notifications. Azure supports multiple recipients separated by ';' or ',' (maps to properties.emails)."

  validation {
    # Accept one OR several addresses separated by ';' or ',' (Azure allows
    # multi-recipient contacts, e.g. "soc@x.com;ciso@x.com").
    condition = alltrue([
      for e in split(";", replace(var.email, ",", ";")) :
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", trimspace(e)))
    ])
    error_message = "email must be one or more valid email addresses separated by ';' or ','."
  }
}

variable "phone" {
  type        = string
  default     = null
  description = "Optional security contact phone number (maps to properties.phone; omitted when null)."
}

variable "enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Whether the security contact is enabled (maps to properties.isEnabled). Default true — the whole point of the module. Replaces the legacy alert_notifications flag."
}

variable "notifications_by_role" {
  description = <<-EOT
  Email notifications to holders of specific RBAC roles on the subscription (maps to
  properties.notificationsByRole). Replaces the legacy alerts_to_admins flag.

  - state : "On" or "Off". Default "On".
  - roles : subset of AccountAdmin / Contributor / Owner / ServiceAdmin. Default ["Owner"].

  Default `{ state = "On", roles = ["Owner"] }` preserves the previous alerts_to_admins=true
  behaviour and matches the live state on sub-pgroup-shared-corp-prod. Set to `null` to omit
  the block entirely (Defender then sends role notifications to no one).
  EOT
  type = object({
    state = optional(string, "On")
    roles = optional(list(string), ["Owner"])
  })
  default  = {}
  nullable = true

  validation {
    condition     = var.notifications_by_role == null || contains(["On", "Off"], var.notifications_by_role.state)
    error_message = "notifications_by_role.state must be \"On\" or \"Off\"."
  }
  validation {
    condition = var.notifications_by_role == null || alltrue([
      for r in var.notifications_by_role.roles : contains(["AccountAdmin", "Contributor", "Owner", "ServiceAdmin"], r)
    ])
    error_message = "notifications_by_role.roles must be a subset of AccountAdmin, Contributor, Owner, ServiceAdmin."
  }
}

variable "notifications_sources" {
  description = <<-EOT
  Notification sources evaluated for email delivery (maps to properties.notificationsSources,
  API 2023-12-01-preview). This is the field the legacy azurerm_security_center_contact could
  not express, which kept Deploy-ASC-SecurityContacts non-compliant despite a configured contact.

  - alert.minimal_severity      : "High" / "Medium" / "Low"  (sourceType "Alert")
  - attack_path.minimal_risk_level : "Critical" / "High" / "Medium" / "Low" (sourceType "AttackPath")

  Default `null` → the block is OMITTED (preserves current behaviour; nothing imposed). Declare
  it to satisfy the policy's existence condition — the ALZ-compliant posture is
  `{ alert = { minimal_severity = "High" }, attack_path = { minimal_risk_level = "Critical" } }`.
  Provide at least one of alert / attack_path when the object is set.
  EOT
  type = object({
    alert = optional(object({
      minimal_severity = optional(string, "High")
    }))
    attack_path = optional(object({
      minimal_risk_level = optional(string, "Critical")
    }))
  })
  default  = null
  nullable = true

  validation {
    condition     = var.notifications_sources == null || var.notifications_sources.alert != null || var.notifications_sources.attack_path != null
    error_message = "When notifications_sources is set, provide at least one of alert / attack_path (else leave it null)."
  }
  validation {
    condition     = try(var.notifications_sources.alert, null) == null || contains(["High", "Medium", "Low"], var.notifications_sources.alert.minimal_severity)
    error_message = "notifications_sources.alert.minimal_severity must be \"High\", \"Medium\" or \"Low\"."
  }
  validation {
    condition     = try(var.notifications_sources.attack_path, null) == null || contains(["Critical", "High", "Medium", "Low"], var.notifications_sources.attack_path.minimal_risk_level)
    error_message = "notifications_sources.attack_path.minimal_risk_level must be \"Critical\", \"High\", \"Medium\" or \"Low\"."
  }
}
