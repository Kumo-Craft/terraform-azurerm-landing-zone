###############################################################
# RBAC — Role Assignments
###############################################################

# Deployment tenant — used as the tenant_id for externally-supplied
# principals (e.g. Grafana's identity) granted on the Hub database.
data "azurerm_client_config" "current" {}

# ADF Managed Identity → Storage Blob Data Contributor
module "adf_storage_blob" {
  source = "../RoleAssignment"

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.this.identity[0].principal_id
}

moved {
  from = azurerm_role_assignment.adf_storage_blob
  to   = module.adf_storage_blob.azurerm_role_assignment.this
}

# ADF Managed Identity → Reader on Storage Account
module "adf_storage_reader" {
  source = "../RoleAssignment"

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Reader"
  principal_id         = azurerm_data_factory.this.identity[0].principal_id
}

moved {
  from = azurerm_role_assignment.adf_storage_reader
  to   = module.adf_storage_reader.azurerm_role_assignment.this
}

# Azure Cost Management Exports SP → Storage Blob Data Contributor
module "cost_mgmt_exports_storage" {
  source = "../RoleAssignment"
  count  = var.cost_management_exports_principal_id != null ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.cost_management_exports_principal_id
}

# F-3: count-gated module requires [0] index on the `to` address.
moved {
  from = azurerm_role_assignment.cost_mgmt_exports_storage
  to   = module.cost_mgmt_exports_storage[0].azurerm_role_assignment.this
}

# ADX Cluster → Storage Blob Data Contributor (for data ingestion)
module "adx_storage_blob" {
  source = "../RoleAssignment"
  count  = var.enable_data_explorer ? 1 : 0

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kusto_cluster.this[0].identity[0].principal_id
}

# F-3: count-gated module requires [0] index on the `to` address.
moved {
  from = azurerm_role_assignment.adx_storage_blob
  to   = module.adx_storage_blob[0].azurerm_role_assignment.this
}

# ADX Cluster → Azure Event Hubs Data Receiver on the Event Hub namespace.
# The EventGrid data connection (azurerm_kusto_eventgrid_data_connection.costs)
# consumes evh-costs-ingestion using the cluster's SystemAssigned identity.
# Without this role the cluster cannot read the Event Hub → 0 ingestion, silent
# (provisioningState stays Succeeded, no ingestion failures). Recreating the data
# connection does NOT recreate this role, so the pipeline stays dead.
module "adx_eventhub_receiver" {
  source = "../RoleAssignment"
  count  = var.enable_data_explorer ? 1 : 0

  scope                = azurerm_eventhub_namespace.this[0].id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_kusto_cluster.this[0].identity[0].principal_id
}

# ADF Managed Identity → ADX Database Ingestor (Ingestion DB)
# F-5: depends_on ensures ADF SystemAssigned identity is provisioned
# before Kusto role assignment is attempted.
resource "azurerm_kusto_database_principal_assignment" "adf_ingestion" {
  count = var.enable_data_explorer ? 1 : 0

  name                = "adf-ingestor"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.this[0].name
  database_name       = azurerm_kusto_database.ingestion[0].name
  tenant_id           = azurerm_data_factory.this.identity[0].tenant_id
  principal_id        = azurerm_data_factory.this.identity[0].principal_id
  principal_type      = "App"
  role                = "Ingestor"

  depends_on = [azurerm_data_factory.this]
}

# ADF Managed Identity → ADX Database Viewer (Hub DB)
# F-5: depends_on ensures ADF SystemAssigned identity is provisioned
# before Kusto role assignment is attempted.
resource "azurerm_kusto_database_principal_assignment" "adf_hub_viewer" {
  count = var.enable_data_explorer ? 1 : 0

  name                = "adf-viewer"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.this[0].name
  database_name       = azurerm_kusto_database.hub[0].name
  tenant_id           = azurerm_data_factory.this.identity[0].tenant_id
  principal_id        = azurerm_data_factory.this.identity[0].principal_id
  principal_type      = "App"
  role                = "Viewer"

  depends_on = [azurerm_data_factory.this]
}

# Extra Viewer principals on the Hub database (e.g. Grafana's identity).
# Mirrors adf_hub_viewer. Gated on enable_data_explorer so the [0]-indexed
# cluster/database refs are only read when the ADX stack exists.
resource "azurerm_kusto_database_principal_assignment" "hub_additional_viewers" {
  for_each = var.enable_data_explorer ? var.hub_additional_viewers : {}

  name                = "viewer-${each.key}"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.this[0].name
  database_name       = azurerm_kusto_database.hub[0].name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  principal_id        = each.value
  principal_type      = "App"
  role                = "Viewer"
}

# Mêmes viewers sur la base Ingestion. Les fonctions de service de Hub (Costs(),
# etc.) font un cross-database vers database('Ingestion').*_final_* ; un cross-db
# exige Viewer sur LES DEUX bases. Sans ça, un viewer Hub-only (Grafana) reçoit
# un 403 sur Ingestion → "No data".
resource "azurerm_kusto_database_principal_assignment" "ingestion_additional_viewers" {
  for_each = var.enable_data_explorer ? var.hub_additional_viewers : {}

  name                = "ing-viewer-${each.key}"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.this[0].name
  database_name       = azurerm_kusto_database.ingestion[0].name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  principal_id        = each.value
  principal_type      = "App"
  role                = "Viewer"
}
