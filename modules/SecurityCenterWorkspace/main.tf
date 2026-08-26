###############################################################
# MODULE: SecurityCenterWorkspace - Main
# One Microsoft.Security/workspaceSettings/default per subscription.
# The ARM resource name is always 'default' (Azure constraint), so
# this module exposes no `name` variable.
#
# IAM requirement: the deploying principal needs **Owner** on the
# target subscription (or a custom role with
# Microsoft.Security/workspaceSettings/* permissions). Contributor
# is NOT sufficient — the action will 403.
###############################################################

locals {
  # Accept both /subscriptions/<guid> and bare GUID forms.
  scope = startswith(var.subscription_id, "/subscriptions/") ? var.subscription_id : "/subscriptions/${var.subscription_id}"
}

resource "azurerm_security_center_workspace" "this" {
  scope        = local.scope
  workspace_id = var.log_analytics_workspace_id
}
