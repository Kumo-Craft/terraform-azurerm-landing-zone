###############################################################
# MODULE: TlsSelfSignedCert - Variables
#
# Generates a self-signed TLS certificate via the `tls` provider
# and imports it into an existing Azure Key Vault as a Certificate
# resource. Suitable for internal/private clusters where browser
# trust isn't needed (the cert chain is rejected by browsers but
# the TLS handshake succeeds and all origin/redirect checks pass).
#
# Use cases:
#   - Argo CD / Grafana / Prometheus UI on a VPN-only AKS cluster
#   - Internal-only nginx Ingress fronted by AKS Application Routing
#
# Pattern:
#   1. tls_private_key + tls_self_signed_cert produce PEM material
#   2. PEM (cert || key) is base64-encoded and imported as an
#      azurerm_key_vault_certificate with issuer_parameters.name = "Self"
#   3. App Routing CSI driver pulls the cert via the standard
#      `kubernetes.azure.com/tls-cert-keyvault-uri` Ingress annotation
#
# The caller is responsible for granting `Key Vault Secrets User`
# to the App Routing UAMI (or any other reader) on the target KV.
###############################################################

###############################################################
# NAMING CONVENTION
#
# Cert names are typically SEMANTIC (e.g. "lb-internal-mtls",
# "kafka-broker-ca") rather than slug-based. This module therefore
# keeps var.cert_name as the PRIMARY naming path. The 4 standard
# naming vars (subscription_acronym / environment / region_code /
# workload) are added as an alternative: when cert_name is null they
# are used to compute a slug-based name via the ../Naming submodule
# (cert-{acr}-{env}-{region}-{workload}).
#
# EXCEPTION NOTE: key_vault_certificate is NOT a key in
# Azure/naming/azurerm 0.4.3, so the inline slug prefix "cert-" is
# used here (same pattern as DnsResolver, FlowLogs, Ampls).
###############################################################
variable "cert_name" {
  type        = string
  description = "Name of the certificate inside the Key Vault. Must be unique per KV and match `[a-zA-Z0-9-]{1,127}`. If null, a name is computed from subscription_acronym/environment/region_code/workload as cert-{acr}-{env}-{region}-{workload}."
  default     = null

  validation {
    condition     = var.cert_name == null || can(regex("^[a-zA-Z0-9-]{1,127}$", var.cert_name))
    error_message = "cert_name must be 1-127 alphanumeric / hyphen characters."
  }

  validation {
    condition = (
      var.cert_name != null ||
      (var.subscription_acronym != null && var.environment != null && var.region_code != null && var.workload != null)
    )
    error_message = "Either var.cert_name must be set, OR all of subscription_acronym/environment/region_code/workload must be provided."
  }
}

variable "subscription_acronym" {
  type        = string
  default     = null
  description = "Subscription acronym (e.g. mgm). Used for computed naming when var.cert_name is null."

  validation {
    condition     = var.subscription_acronym == null || can(regex("^[a-z]{2,5}$", var.subscription_acronym))
    error_message = "subscription_acronym must be 2 to 5 lowercase letters."
  }
}

variable "environment" {
  type        = string
  default     = null
  description = "Environment (e.g. prod, nprd). Used for computed naming when var.cert_name is null."

  validation {
    condition     = var.environment == null || can(regex("^[a-z]{2,4}$", var.environment))
    error_message = "environment must be 2 to 4 lowercase letters."
  }
}

variable "region_code" {
  type        = string
  default     = null
  description = "Region code (e.g. gwc, weu). Used for computed naming when var.cert_name is null."

  validation {
    condition     = var.region_code == null || can(regex("^[a-z]{2,5}$", var.region_code))
    error_message = "region_code must be 2 to 5 lowercase letters."
  }
}

variable "location" {
  type        = string
  default     = null
  description = "Azure region (e.g. germanywestcentral). Passed to the Naming submodule when used."
}

variable "workload" {
  type        = string
  default     = null
  description = "Workload component (e.g. management). Used for computed naming when var.cert_name is null."

  validation {
    condition     = var.workload == null || can(regex("^[a-z][a-z0-9_-]{1,30}$", var.workload))
    error_message = "workload must be 2 to 31 characters: lowercase letters, digits, hyphens, underscores."
  }
}

variable "key_vault_id" {
  type        = string
  description = "Resource ID of the Key Vault that will host the certificate."
  nullable    = false
}

variable "common_name" {
  type        = string
  description = "Subject CN of the certificate (e.g. `*.shc.az.epttst.lu`). Goes into the cert's distinguished name. Wildcard CN is accepted but modern browsers/clients rely on Subject Alternative Names — always populate `dns_names` as well."
  nullable    = false
}

variable "organization" {
  type        = string
  description = "Subject O field. Cosmetic — shown in cert viewers."
  default     = "Post Luxembourg"
}

variable "dns_names" {
  type        = list(string)
  description = "Subject Alternative Names (DNS). Modern TLS clients verify the SAN list, not the CN. Include the wildcard and any specific hostnames the cert should be valid for. Example: [\"*.shc.az.epttst.lu\", \"shc.az.epttst.lu\"]."
  default     = []
}

variable "ip_addresses" {
  type        = list(string)
  description = "Subject Alternative Names (IP). Rarely needed for ingress certs."
  default     = []
}

variable "validity_days" {
  type        = number
  description = "Cert validity in days. Default 365 (1 year) — the modern recommended baseline (aligns with CAB Forum BR-style guidance for short-lived certs). Increase ONLY if you have a documented rotation deferral. Range: 1-3650."
  default     = 365

  validation {
    condition     = var.validity_days > 0 && var.validity_days <= 3650
    error_message = "validity_days must be between 1 and 3650 (10 years)."
  }
}

variable "early_renewal_hours" {
  type        = number
  description = "Hours before expiry to trigger renewal at next plan/apply. 0 = no early renewal (cert renewed only after expiry). For shorter validity_days (e.g. 90 days), consider 168 (7 days) to give CI time to roll out the new cert."
  default     = 0
  nullable    = false
}

variable "key_size" {
  type        = number
  description = "RSA key size in bits."
  default     = 2048

  validation {
    condition     = contains([2048, 3072, 4096], var.key_size)
    error_message = "key_size must be 2048, 3072, or 4096."
  }
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
  description = "Map of role assignments at the Key Vault certificate scope. Default principal_type='ServicePrincipal'."
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

variable "tags" {
  type        = map(string)
  description = "Tags applied to the Key Vault certificate object."
  default     = {}
  nullable    = false
}
