###############################################################
# MODULE: DomainServices - Main
# Description: Microsoft Entra Domain Services (managed AD DS,
#              Microsoft.AAD/domainServices). One managed domain
#              + optional Resource Lock. User Forest mode.
#
# ── OUT-OF-BAND PREREQUISITES (NOT managed by this module) ──
# Entra Domain Services depends on tenant-level objects that
# Terraform cannot reliably manage and that live outside this
# module's subscription scope. Provision them once, out-of-band,
# BEFORE applying this module:
#
#   1. Resource Provider — register `Microsoft.AAD` on the target
#      subscription.
#   2. Service Principal — the "Domain Controller Services" published
#      application (app id 2565bd9d-da50-47d4-8b85-4c97f669dc36) must
#      have a service principal in the tenant. Create it manually
#      (e.g. `azuread_service_principal`), it does not exist by default.
#   3. Group — an "AAD DC Administrators" security group in Entra ID
#      (members administer the managed domain).
#   4. Password hashes — cloud users must reset their password (and
#      hybrid tenants must enable legacy hash sync in Entra Connect)
#      so NTLM/Kerberos hashes exist for the domain to authenticate.
#   5. Networking — the replica subnet must carry an NSG allowing
#      `AzureActiveDirectoryDomainServices` inbound (443/5986) and
#      LDAPS (636) if secure_ldap is enabled.
#
# See: https://learn.microsoft.com/entra/identity/domain-services/tutorial-create-instance
###############################################################

resource "time_static" "time" {}

###############################################################
# Naming Convention — composed from the in-repo Naming submodule's
# suffix output with the house literal prefix `aadds-` (Azure/naming
# has no domain-services type, so we keep the literal).
# Convention: aadds-{acronym}-{env}-{region}-{workload}
# Example:    aadds-idt-prod-gwc-domain
###############################################################
module "naming" {
  source   = "../Naming"
  for_each = var.name == null ? toset(["this"]) : toset([])

  subscription_acronym = var.subscription_acronym
  environment          = var.environment
  region_code          = var.region_code
  workload             = var.workload
}

locals {
  name = var.name != null ? var.name : "aadds-${join("-", module.naming["this"].suffix)}"
}

###############################################################
# RESOURCE: Entra Domain Services managed domain
###############################################################
resource "azurerm_active_directory_domain_service" "this" {
  name                      = local.name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  domain_name               = var.domain_name
  sku                       = var.sku
  domain_configuration_type = var.domain_configuration_type
  filtered_sync_enabled     = var.filtered_sync_enabled

  initial_replica_set {
    subnet_id = var.replica_subnet_id
  }

  notifications {
    additional_recipients = var.notifications.additional_recipients
    notify_dc_admins      = var.notifications.notify_dc_admins
    notify_global_admins  = var.notifications.notify_global_admins
  }

  # Hardened defaults — see var.security.
  security {
    kerberos_armoring_enabled       = var.security.kerberos_armoring_enabled
    kerberos_rc4_encryption_enabled = var.security.kerberos_rc4_encryption_enabled
    ntlm_v1_enabled                 = var.security.ntlm_v1_enabled
    tls_v1_enabled                  = var.security.tls_v1_enabled
    sync_kerberos_passwords         = var.security.sync_kerberos_passwords
    sync_ntlm_passwords             = var.security.sync_ntlm_passwords
    sync_on_prem_passwords          = var.security.sync_on_prem_passwords
  }

  dynamic "secure_ldap" {
    for_each = var.secure_ldap != null ? [var.secure_ldap] : []
    content {
      enabled                  = secure_ldap.value.enabled
      external_access_enabled  = secure_ldap.value.external_access_enabled
      pfx_certificate          = secure_ldap.value.pfx_certificate
      pfx_certificate_password = secure_ldap.value.pfx_certificate_password
    }
  }

  tags = merge(
    var.tags,
    {
      CreatedOn = formatdate("DD-MM-YYYY hh:mm", timeadd(time_static.time.id, "1h"))
    }
  )

  # A managed domain holds directory state (users, groups, joined machines).
  # Destruction is catastrophic and irreversible — password hashes are lost.
  lifecycle {
    prevent_destroy = true
  }
}

###############################################################
# RESOURCE: Management Lock
###############################################################
module "lock" {
  source = "../ResourceLock"

  locks = var.lock != null ? {
    this = {
      scope      = azurerm_active_directory_domain_service.this.id
      lock_level = var.lock.kind
      name       = var.lock.name
    }
  } : {}
}
