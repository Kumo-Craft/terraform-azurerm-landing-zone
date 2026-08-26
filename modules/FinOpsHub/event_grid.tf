###############################################################
# Event Grid — System Topic for Storage blob events
###############################################################
# Required for ADF blob event triggers to work.
# ADF creates its own Event Grid subscription internally,
# but the system topic must exist on the storage account.
###############################################################

resource "azurerm_eventgrid_system_topic" "this" {
  name                = local.evgt_name
  resource_group_name = var.resource_group_name
  location            = var.location
  source_resource_id  = azurerm_storage_account.this.id
  topic_type          = "Microsoft.Storage.StorageAccounts"
  tags                = local.common_tags
}
