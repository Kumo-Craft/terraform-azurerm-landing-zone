###############################################################
# Application Insights — 1 per firewall (PAN-OS metrics)
###############################################################

resource "azurerm_application_insights" "this" {
  for_each = var.log_analytics_workspace_id != null ? var.firewalls : {}

  name                = "apin-${local.prefix}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  application_type    = "other"
  workspace_id        = var.log_analytics_workspace_id

  # PAN-OS pushes custom metrics via the Instrumentation Key (local auth).
  # Disabling local auth would silently break metric ingestion from the
  # firewalls — the key is pasted into PAN-OS device settings and Azure
  # would start rejecting key-authenticated pushes.
  # Ref: PaloAltoNetworks vmseries-modules application_insights — emits
  # metrics_instrumentation_key and does NOT set local_authentication_disabled.
  local_authentication_disabled = false

  tags = local.common_tags
}

###############################################################
# Custom Role — PAN-OS Application Insights (least privilege)
# Ref: https://docs.paloaltonetworks.com/vm-series/11-1/vm-series-deployment/
#      set-up-the-vm-series-firewall-on-azure/about-the-vm-series-firewall-on-azure/
#      vm-series-on-azure-service-principal-permissions
###############################################################

data "azurerm_subscription" "current" {}

resource "azurerm_role_definition" "panos_appinsights" {
  count = var.log_analytics_workspace_id != null ? 1 : 0

  name        = "PAN-OS AppInsights ${local.prefix}-${var.workload}"
  scope       = data.azurerm_subscription.current.id
  description = "Custom role for VM-Series Application Insights monitoring (PAN-OS metrics)."

  permissions {
    actions = [
      "Microsoft.Authorization/*/read",
      "Microsoft.Network/networkInterfaces/read",
      "Microsoft.Network/networkSecurityGroups/read",
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Compute/virtualMachines/read",
    ]
  }

  assignable_scopes = [
    data.azurerm_subscription.current.id
  ]
}

###############################################################
# Role Assignment — SPN PAN-OS
###############################################################

module "panos_appinsights" {
  source = "../RoleAssignment"
  count  = var.panos_spn_object_id != null ? 1 : 0

  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.panos_appinsights[0].role_definition_resource_id
  principal_id       = var.panos_spn_object_id
}

moved {
  from = azurerm_role_assignment.panos_appinsights
  to   = module.panos_appinsights[0].azurerm_role_assignment.this
}
