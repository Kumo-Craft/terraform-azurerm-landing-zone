###############################################################
# MODULE: SecurityCenterSubscription - Main
# Description: Microsoft Defender for Cloud security contact at the
#              subscription level, deployed via azapi against
#              Microsoft.Security/securityContacts@2023-12-01-preview.
#
# WHY azapi (not azurerm): azurerm_security_center_contact only exposes the
# LEGACY schema (email/phone/alert_notifications/alerts_to_admins) and cannot
# express `notificationsSources` — verified against azurerm 4.81.0 (no
# notifications_sources attribute). Without notificationsSources[AttackPath],
# Deploy-ASC-SecurityContacts (Deploy-MDFC-Config initiative) stays NON-COMPLIANT
# even with a correctly configured contact. This module owns the FULL PUT so the
# new schema is expressed end-to-end (no split-brain where an out-of-band value is
# silently clobbered on the next apply).
#
# Scope: the CONTACT only. azurerm_security_center_setting (MCAS / WDATP) is the
# other half of the SecurityCenter* family — intentionally NOT implemented here.
###############################################################

locals {
  # subscription_id may arrive bare or as a path; normalize to the /subscriptions/<guid>
  # form used as the azapi parent_id (subscription-scoped resource). Mirrors the
  # SecurityCenterWorkspace scope normalization.
  subscription_scope = startswith(var.subscription_id, "/subscriptions/") ? var.subscription_id : "/subscriptions/${var.subscription_id}"

  # Build notificationsSources[] from the typed input. null → [] → block omitted below,
  # which preserves whatever the subscription already has (nothing imposed).
  notifications_sources = var.notifications_sources == null ? [] : concat(
    var.notifications_sources.alert != null ? [{
      sourceType      = "Alert"
      minimalSeverity = var.notifications_sources.alert.minimal_severity
    }] : [],
    var.notifications_sources.attack_path != null ? [{
      sourceType       = "AttackPath"
      minimalRiskLevel = var.notifications_sources.attack_path.minimal_risk_level
    }] : [],
  )

  # Assemble properties via merge() so unset optional fields are OMITTED keys (not null
  # values) — the module writes only what it is told to, satisfying the "own it end-to-end
  # or don't touch it" rule.
  contact_properties = merge(
    {
      emails    = var.email
      isEnabled = var.enabled
    },
    var.phone != null ? { phone = var.phone } : {},
    var.notifications_by_role != null ? {
      notificationsByRole = {
        state = var.notifications_by_role.state
        roles = var.notifications_by_role.roles
      }
    } : {},
    length(local.notifications_sources) > 0 ? { notificationsSources = local.notifications_sources } : {},
  )
}

###############################################################
# RESOURCE: Security Contact (securityContacts/default) via azapi
###############################################################
resource "azapi_resource" "this" {
  # ⚠️ name is FIXED to "default" — Azure allows exactly ONE security contact per
  # subscription, only under this name. Not exposed as a variable.
  type      = "Microsoft.Security/securityContacts@2023-12-01-preview"
  name      = "default"
  parent_id = local.subscription_scope

  body = {
    properties = local.contact_properties
  }
}

###############################################################
# STATE MIGRATION (azurerm_security_center_contact -> azapi_resource)
#
# Prior versions created azurerm_security_center_contact.this. This `moved` block
# uses azapi's officially-supported azurerm->azapi cross-type migration
# (Terraform >= 1.8, azapi >= 2.1 — both satisfied by this repo's pins): it is a
# pure STATE RELABEL — `0 to add, 0 to change, 0 to destroy` — after which the next
# plan is an in-place UPDATE that adds notificationsSources. The real
# securityContacts/default is never destroyed or recreated. `azurerm` is retained in
# version.tf solely so the `from` type resolves.
#
# ⚠️ VALIDATE the first upgrade against ONE non-prod subscription: the plan MUST show
# `0 to destroy`. azapi documents the move flow for root-module resources; if the
# state-move does not apply cleanly for a resource nested in this child module, the
# plan will reveal it (a destroy/create instead of a move) — fall back to:
#   terraform state rm  'module.<x>.azurerm_security_center_contact.this'
#   terraform import    'module.<x>.azapi_resource.this' \
#     '/subscriptions/<SUB_ID>/providers/Microsoft.Security/securityContacts/default'
###############################################################
moved {
  from = azurerm_security_center_contact.this
  to   = azapi_resource.this
}
