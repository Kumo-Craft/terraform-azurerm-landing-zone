###############################################################
# MODULE: TlsSelfSignedCert - Main
###############################################################

###############################################################
# Naming Convention — delegated to the in-repo Naming submodule.
# key_vault_certificate is not a key in Azure/naming/azurerm 0.4.3,
# so we use the inline slug pattern: cert-{acr}-{env}-{region}-{workload}
# Example: cert-mgm-prod-gwc-ingress
#
# NOTE: Cert names are typically SEMANTIC (e.g. "lb-internal-mtls",
# "kafka-broker-ca"). var.cert_name remains the PRIMARY path; the
# naming vars provide a conventional fallback when cert_name is null.
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.cert_name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  name = var.cert_name != null ? var.cert_name : "cert-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RSA Private Key
###############################################################
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = var.key_size
}

###############################################################
# Self-signed X.509 Certificate
#
# `allowed_uses` covers what an nginx Ingress TLS cert needs:
#   - server_auth      : Extended Key Usage = TLS Web Server Auth
#   - digital_signature: Key Usage = digitalSignature (TLS handshake)
#   - key_encipherment : Key Usage = keyEncipherment (RSA key exchange)
###############################################################
resource "tls_self_signed_cert" "this" {
  private_key_pem = tls_private_key.this.private_key_pem

  subject {
    common_name  = var.common_name
    organization = var.organization
  }

  dns_names    = var.dns_names
  ip_addresses = var.ip_addresses

  validity_period_hours = var.validity_days * 24
  early_renewal_hours   = var.early_renewal_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

###############################################################
# Key Vault Certificate (import)
#
# Azure Key Vault stores certs in 3 forms simultaneously:
#   - certificate object (the X.509 cert)
#   - secret object      (cert + private key as PEM or PFX, depending
#                         on secret_properties.content_type)
#   - key object         (the underlying RSA key, for cryptographic ops)
#
# The Application Routing addon CSI driver fetches via the SECRET
# endpoint, so we set content_type = "application/x-pem-file" and
# concatenate cert + private key as PEM. The addon then materializes
# the result as a standard Kubernetes TLS Secret in the Ingress's
# namespace, which nginx-controller consumes via `tls.secretName`.
#
# Key format: Azure KV's PEM import path REQUIRES PKCS#8 (`-----BEGIN
# PRIVATE KEY-----`), not PKCS#1 (`-----BEGIN RSA PRIVATE KEY-----`).
# The `tls` provider exposes both: `.private_key_pem` is PKCS#1 (used
# by tls_self_signed_cert above, which accepts either), and
# `.private_key_pem_pkcs8` is PKCS#8 — what KV wants. Passing PKCS#1
# yields a 400 "PEM X.509 certificate content is in an unexpected
# format" from Azure with no useful diagnostic.
#
# `issuer_parameters.name = "Self"` is the marker for imports. The
# certificate_policy block must be present (Azure requirement) even
# for imports — it dictates what would happen on renewal.
###############################################################
resource "azurerm_key_vault_certificate" "this" {
  name         = local.name
  key_vault_id = var.key_vault_id

  certificate {
    contents = base64encode("${tls_self_signed_cert.this.cert_pem}${tls_private_key.this.private_key_pem_pkcs8}")
  }

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = var.key_size
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pem-file"
    }
  }

  tags = var.tags
}

###############################################################
# RESOURCE: Management Lock (optional)
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_key_vault_certificate.this.versionless_id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}

###############################################################
# RESOURCE: Role Assignments — delegated to ../RoleAssignment
###############################################################
module "rbac" {
  source   = "../RoleAssignment"
  for_each = var.role_assignments

  scope                            = azurerm_key_vault_certificate.this.versionless_id
  principal_id                     = each.value.principal_id
  principal_type                   = each.value.principal_type
  role_definition_id_or_name       = each.value.role_definition_id_or_name
  condition                        = each.value.condition
  condition_version                = each.value.condition_version
  description                      = each.value.description
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check
}
