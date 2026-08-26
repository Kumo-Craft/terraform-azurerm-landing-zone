###############################################################
# MODULE: DomainServices - Variables
###############################################################

###############################################################
# NAMING CONVENTION
# Convention: aadds-{acronym}-{env}-{region}-{workload}
#   e.g. aadds-idt-prod-gwc-domain
###############################################################
variable "name" {
  type        = string
  default     = null
  description = "Optional. Explicit resource (display) name. If null, computed from naming components as aadds-{acronym}-{env}-{region}-{workload}."

  validation {
    condition = (
      var.name != null
      || (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either `name` must be set, or all of `subscription_acronym`, `environment`, `region_code`, `workload` must be provided."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. idt, con, mgm)."

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd)."

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu)."

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "workload" {
  type        = string
  default     = "domain"
  description = "Workload name / naming suffix segment (e.g. domain)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9_-]{0,30}$", var.workload))
    error_message = "workload must be 1 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

###############################################################
# REQUIRED VARIABLES
###############################################################
variable "location" {
  type        = string
  description = "Azure region where the managed domain is deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Resource group hosting the managed domain."
  nullable    = false
}

variable "domain_name" {
  type        = string
  description = <<-EOT
    The DNS domain name for the managed domain (FQDN, e.g. aadds.contoso.com).

    Constraints:
    - Must be a valid FQDN with at least two labels.
    - The leading label (used as the NetBIOS name) must be <= 15 characters.
    - Use a **custom, routable** domain you own. Do NOT use the tenant default
      `*.onmicrosoft.com` — it is not routable and prevents secure LDAP with
      your own certificate (Microsoft owns that DNS namespace).
    Changing this forces a new managed domain.
  EOT
  nullable    = false

  validation {
    condition     = can(regex("^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", var.domain_name))
    error_message = "domain_name must be a valid FQDN with at least two labels (e.g. aadds.contoso.com)."
  }

  validation {
    condition     = length(split(".", var.domain_name)[0]) <= 15
    error_message = "The leading domain label (NetBIOS name) must be 15 characters or fewer."
  }
}

variable "replica_subnet_id" {
  type        = string
  description = "Resource ID of the subnet for the initial replica set (dedicated /24+ subnet, NSG allowing AzureActiveDirectoryDomainServices). Changing this forces a new managed domain."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/.+/subnets/.+$", var.replica_subnet_id))
    error_message = "replica_subnet_id must be a full subnet ARM ID."
  }
}

variable "sku" {
  type        = string
  default     = "Standard"
  description = "SKU for the managed domain. One of Standard, Enterprise, Premium."

  validation {
    condition     = contains(["Standard", "Enterprise", "Premium"], var.sku)
    error_message = "sku must be one of Standard, Enterprise, Premium."
  }
}

variable "domain_configuration_type" {
  type        = string
  default     = "FullySynced"
  description = "Configuration type. FullySynced (User Forest — syncs all objects) or ResourceTrusting (Resource Forest). Changing this forces a new managed domain."

  validation {
    condition     = contains(["FullySynced", "ResourceTrusting"], var.domain_configuration_type)
    error_message = "domain_configuration_type must be FullySynced or ResourceTrusting."
  }
}

variable "filtered_sync_enabled" {
  type        = bool
  default     = false
  description = "Enable group-based filtered (scoped) synchronisation."
  nullable    = false
}

###############################################################
# NOTIFICATIONS
###############################################################
variable "notifications" {
  type = object({
    additional_recipients = optional(list(string), [])
    notify_dc_admins      = optional(bool, true)
    notify_global_admins  = optional(bool, true)
  })
  default     = {}
  nullable    = false
  description = "Alert notifications for the managed domain (extra recipients + notify AAD DC Administrators / Global Administrators)."
}

###############################################################
# SECURITY — hardened by default (MS "Harden a managed domain")
###############################################################
variable "security" {
  type = object({
    kerberos_armoring_enabled       = optional(bool, true)  # ON  — FAST/Kerberos armoring
    kerberos_rc4_encryption_enabled = optional(bool, false) # OFF — weak cipher
    ntlm_v1_enabled                 = optional(bool, false) # OFF — legacy NTLM v1
    tls_v1_enabled                  = optional(bool, false) # OFF — legacy TLS 1.0
    sync_kerberos_passwords         = optional(bool, true)  # ON  — required for Kerberos auth
    sync_ntlm_passwords             = optional(bool, false) # OFF — do not sync NTLM hashes
    sync_on_prem_passwords          = optional(bool, false) # OFF — enable only for hybrid (Entra Connect)
  })
  default     = {}
  nullable    = false
  description = <<-EOT
    Managed domain security settings. Hardened by default per Microsoft's
    "Harden a Microsoft Entra Domain Services managed domain":
      - Kerberos armoring ENABLED
      - NTLM v1, TLS 1.0, Kerberos RC4 DISABLED
      - NTLM password sync DISABLED
      - Kerberos password sync ENABLED (required for Kerberos authentication)
    Set `sync_on_prem_passwords = true` only for hybrid tenants using Entra Connect.
    Note: disabling `sync_ntlm_passwords` breaks LDAP simple binds — keep it off
    unless a legacy app requires them.
  EOT
}

###############################################################
# SECURE LDAP (LDAPS) — optional, sensitive
###############################################################
variable "secure_ldap" {
  type = object({
    enabled                  = optional(bool, true)
    external_access_enabled  = optional(bool, false)
    pfx_certificate          = string
    pfx_certificate_password = string
  })
  default     = null
  nullable    = true
  sensitive   = true
  description = <<-EOT
    Optional secure LDAP (LDAPS) configuration. Null = LDAPS disabled.
      - pfx_certificate          : base64-encoded PKCS#12 (PFX) bundle holding the LDAPS cert + key.
      - pfx_certificate_password : password decrypting the PFX bundle.
      - external_access_enabled  : expose LDAPS (TCP 636) to the Internet. Default false —
                                   keep OFF unless the subnet NSG restricts source ranges,
                                   else you invite Internet bruteforce.
    Marked sensitive: the whole object carries the certificate + password.
  EOT
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
  Optional Resource Lock. The resource also carries an unconditional
  `lifecycle.prevent_destroy` guard at the Terraform level — this variable adds
  a second, Azure-side guard that survives state loss/refresh.

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
  default     = {}
  nullable    = false
  description = "Tags to apply to the managed domain."
}
