###############################################################
# Azure Data Explorer (Kusto) — Cluster + Databases
###############################################################

resource "azurerm_kusto_cluster" "this" {
  count = var.enable_data_explorer ? 1 : 0

  # CKV_AZURE_180 (DataExplorerSKUHasSLA): the default SKU intentionally remains
  # the cost-optimized "Dev(No SLA)" tier — this is a FinOps hub whose default
  # posture favours minimal cost, and the SLA/SKU is fully caller-configurable
  # via var.adx_sku_name (production consumers set a Standard_* SKU with SLA).
  # This is an availability/cost design choice, not a security control, so the
  # secure-by-default sweep leaves the default unchanged.
  # checkov:skip=CKV_AZURE_180: SKU is configurable via var.adx_sku_name; Dev(No SLA) is the deliberate cost-optimized default for FinOps dev deployments.
  # checkov:skip=CKV_AZURE_75: double (infrastructure) encryption is exposed via var.adx_double_encryption_enabled; kept opt-in / default false because it is a creation-only ForceNew property — forcing it by default would destroy+recreate existing ADX clusters (loss of ingested data). Enable per new deployment.
  name                = local.adx_name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku {
    name     = var.adx_sku_name
    capacity = var.adx_sku_capacity
  }

  identity {
    type = "SystemAssigned"
  }

  # F-13: explicit zones override; falls back to env-driven default.
  zones = var.adx_zones != null ? var.adx_zones : (startswith(var.adx_sku_name, "Dev") ? [] : ["1", "2", "3"])

  # CKV_AZURE_74 — encrypt the cluster VM disks at rest (Microsoft-managed keys).
  # Secure-by-default true. Not ForceNew: enabling on an existing cluster is an
  # in-place update that restarts the cluster (no data loss).
  disk_encryption_enabled = var.adx_disk_encryption_enabled

  # CKV_AZURE_75 — infrastructure-level (double) encryption of cluster storage.
  # OPT-IN, default false (see var.adx_double_encryption_enabled and the
  # checkov:skip above). This is a creation-only property (Azure cannot toggle it
  # after creation); the azurerm provider marks it ForceNew, so enabling it on an
  # EXISTING cluster forces destroy + recreate. Kept opt-in so it never rebuilds
  # a live FinOpsHub cluster implicitly — enable on new deployments.
  double_encryption_enabled = var.adx_double_encryption_enabled

  public_network_access_enabled = var.enable_public_access
  tags                          = local.common_tags
}

###############################################################
# Database — Ingestion (raw + transformed cost data)
###############################################################
resource "azurerm_kusto_database" "ingestion" {
  count = var.enable_data_explorer ? 1 : 0

  name                = "Ingestion"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.this[0].name
  location            = var.location
  hot_cache_period    = "P${var.adx_hot_cache_days}D"
  soft_delete_period  = "P${var.adx_soft_delete_days}D"
}

###############################################################
# Database — Hub (query functions for Power BI)
###############################################################
resource "azurerm_kusto_database" "hub" {
  count = var.enable_data_explorer ? 1 : 0

  name                = "Hub"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.this[0].name
  location            = var.location
  hot_cache_period    = "P${var.adx_hot_cache_days}D"
  soft_delete_period  = "P${var.adx_soft_delete_days}D"
}

###############################################################
# KQL Scripts — Ingestion DB setup
###############################################################
resource "azurerm_kusto_script" "ingestion_setup" {
  count = var.enable_data_explorer ? 1 : 0

  name        = "ingestion-setup"
  database_id = azurerm_kusto_database.ingestion[0].id

  script_content                     = file("${path.module}/kql/ingestion_setup.kql")
  continue_on_errors_enabled         = true
  force_an_update_when_value_changed = md5(file("${path.module}/kql/ingestion_setup.kql"))
}

###############################################################
# KQL Scripts — Hub DB setup
###############################################################
resource "azurerm_kusto_script" "hub_setup" {
  count = var.enable_data_explorer ? 1 : 0

  name        = "hub-setup"
  database_id = azurerm_kusto_database.hub[0].id

  script_content                     = file("${path.module}/kql/hub_setup.kql")
  continue_on_errors_enabled         = true
  force_an_update_when_value_changed = md5(file("${path.module}/kql/hub_setup.kql"))

  depends_on = [azurerm_kusto_script.ingestion_setup]
}

###############################################################
# Event Hub Namespace + Event Hub
# Required as an intermediate for EventGrid → ADX data connection
###############################################################
resource "azurerm_eventhub_namespace" "this" {
  count = var.enable_data_explorer ? 1 : 0

  name                = local.evhns_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  capacity            = 1

  tags = local.common_tags
}

resource "azurerm_eventhub" "costs_ingestion" {
  count = var.enable_data_explorer ? 1 : 0

  name              = "evh-costs-ingestion"
  namespace_id      = azurerm_eventhub_namespace.this[0].id
  partition_count   = 2
  message_retention = 1
}

###############################################################
# EventGrid Event Subscription
# Storage blob events on ingestion container → Event Hub
###############################################################
resource "azurerm_eventgrid_event_subscription" "ingestion_to_eventhub" {
  count = var.enable_data_explorer ? 1 : 0

  name  = "ingestion-blob-to-eventhub"
  scope = azurerm_storage_account.this.id

  eventhub_endpoint_id = azurerm_eventhub.costs_ingestion[0].id

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/ingestion"
    subject_ends_with   = ".parquet"
  }

  depends_on = [azurerm_eventgrid_system_topic.this]
}

###############################################################
# ADX EventGrid Data Connection
# Event Hub → ADX Ingestion database → Costs_raw table
###############################################################
resource "azurerm_kusto_eventgrid_data_connection" "costs" {
  count = var.enable_data_explorer ? 1 : 0

  name                = "ingestion-costs-eventgrid"
  resource_group_name = var.resource_group_name
  cluster_name        = azurerm_kusto_cluster.this[0].name
  database_name       = azurerm_kusto_database.ingestion[0].name
  location            = var.location

  storage_account_id           = azurerm_storage_account.this.id
  eventhub_id                  = azurerm_eventhub.costs_ingestion[0].id
  eventhub_consumer_group_name = "$Default"
  managed_identity_id          = azurerm_kusto_cluster.this[0].id

  table_name        = "Costs_raw"
  mapping_rule_name = "Costs_raw_mapping"
  data_format       = "PARQUET"

  blob_storage_event_type = "Microsoft.Storage.BlobCreated"

  depends_on = [
    azurerm_kusto_script.ingestion_setup,
    module.adx_storage_blob,
    module.adx_eventhub_receiver,
    azurerm_eventgrid_event_subscription.ingestion_to_eventhub,
  ]
}
