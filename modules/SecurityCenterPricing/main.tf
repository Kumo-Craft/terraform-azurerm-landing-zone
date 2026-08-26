###############################################################
# MODULE: SecurityCenterPricing - Main
# Active des plans Microsoft Defender for Cloud (pricing tiers) sur
# la souscription ciblée par le PROVIDER.
#
# NB: azurerm_security_center_subscription_pricing n'a AUCUN argument
# de scope / subscription -- il s'applique toujours à la souscription
# du provider. S'assurer que le provider est scopé sur la bonne sub.
#
# IAM: le principal qui déploie a besoin d'Owner (ou Security Admin)
# sur la sub. Contributor -> 403 sur Microsoft.Security/pricings.
#
# ⚠️ La SUPPRESSION d'une entrée (ou du module) remet le plan à "Free"
#    pour ce resource_type. Passer "Standard" impacte TOUTES les
#    ressources de ce type dans la sub -> coût potentiellement élevé.
###############################################################

resource "azurerm_security_center_subscription_pricing" "this" {
  for_each = var.plans

  resource_type = each.key
  tier          = each.value.tier
  subplan       = each.value.subplan

  dynamic "extension" {
    for_each = each.value.extension
    content {
      name                            = extension.value.name
      additional_extension_properties = extension.value.additional_extension_properties
    }
  }
}
