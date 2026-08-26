###############################################################
# Main Resource — Storage Account is the primary leaf resource
# for FinOpsHub (RG is caller-provided since v0.2.49).
###############################################################
output "resource" {
  description = "The FinOps Hub storage account object (primary resource)"
  value       = azurerm_storage_account.this
  sensitive   = true
}

###############################################################
# Storage Account
###############################################################
output "storage_account_id" {
  description = "The ID of the FinOps Hub storage account"
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "The name of the FinOps Hub storage account"
  value       = azurerm_storage_account.this.name
}

###############################################################
# Azure Data Explorer
###############################################################
output "adx_cluster_id" {
  description = "The ID of the ADX cluster"
  value       = try(azurerm_kusto_cluster.this[0].id, null)
}

output "adx_cluster_uri" {
  description = "The URI of the ADX cluster"
  value       = try(azurerm_kusto_cluster.this[0].uri, null)
}

output "adx_cluster_name" {
  description = "The name of the ADX cluster"
  value       = try(azurerm_kusto_cluster.this[0].name, null)
}

###############################################################
# Data Factory
###############################################################
output "data_factory_id" {
  description = "The ID of the Data Factory"
  value       = azurerm_data_factory.this.id
}

output "data_factory_name" {
  description = "The name of the Data Factory"
  value       = azurerm_data_factory.this.name
}

output "data_factory_principal_id" {
  description = "The principal ID of the Data Factory managed identity"
  value       = azurerm_data_factory.this.identity[0].principal_id
}

###############################################################
# Event Hub
###############################################################
output "eventhub_namespace_id" {
  description = "The ID of the Event Hub Namespace"
  value       = try(azurerm_eventhub_namespace.this[0].id, null)
}

output "adx_ingestion_uri" {
  description = "The data ingestion URI of the ADX cluster"
  value       = try(azurerm_kusto_cluster.this[0].data_ingestion_uri, null)
}

output "hub_additional_viewer_ids" {
  description = "Map of hub_additional_viewers key => Kusto database principal assignment ID (empty when none / ADX disabled)."
  value       = { for k, r in azurerm_kusto_database_principal_assignment.hub_additional_viewers : k => r.id }
}
