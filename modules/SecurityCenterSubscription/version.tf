terraform {
  required_version = ">= 1.12.0"
  required_providers {
    # azapi carries the resource: azurerm_security_center_contact only exposes the
    # LEGACY securityContacts schema (email/phone/alert_notifications/alerts_to_admins)
    # and cannot express notificationsSources (Alert.minimalSeverity + AttackPath
    # .minimalRiskLevel) required by Deploy-ASC-SecurityContacts. Verified against
    # azurerm 4.81.0 schema (no notifications_sources) — so this module deploys
    # Microsoft.Security/securityContacts@2023-12-01-preview directly via azapi.
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    # azurerm is retained ONLY so the `moved` block in main.tf can reference the
    # former azurerm_security_center_contact.this type during the azurerm->azapi
    # state migration. The module no longer creates any azurerm resource.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
