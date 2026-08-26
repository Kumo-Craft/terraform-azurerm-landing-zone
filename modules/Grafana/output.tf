###############################################################
# MODULE: Grafana - Outputs
###############################################################

###############################################################
# Canonical outputs (F-3)
###############################################################
output "id" {
  description = "Grafana resource ID."
  value       = azurerm_dashboard_grafana.this.id
}

output "name" {
  description = "Grafana resource name."
  value       = azurerm_dashboard_grafana.this.name
}

output "resource" {
  description = "Full azurerm_dashboard_grafana resource object."
  value       = azurerm_dashboard_grafana.this
}

output "endpoint" {
  description = "Grafana endpoint URL."
  value       = azurerm_dashboard_grafana.this.endpoint
}

output "private_endpoint_id" {
  description = "Grafana Private Endpoint ID (null when private_endpoint is not configured)"
  value       = try(azurerm_private_endpoint.this[0].id, null)
}

###############################################################
# Deprecated aliases — kept for one-cycle backward compatibility.
# Will be removed in v0.3.0. Migrate callers to canonical names.
###############################################################
output "grafana_id" {
  description = "DEPRECATED — use output 'id'. Will be removed in v0.3.0."
  value       = azurerm_dashboard_grafana.this.id
}

output "grafana_name" {
  description = "DEPRECATED — use output 'name'. Will be removed in v0.3.0."
  value       = azurerm_dashboard_grafana.this.name
}

output "grafana_resource" {
  description = "DEPRECATED — use output 'resource'. Will be removed in v0.3.0."
  value       = azurerm_dashboard_grafana.this
}

output "grafana_endpoint" {
  description = "DEPRECATED — use output 'endpoint'. Will be removed in v0.3.0."
  value       = azurerm_dashboard_grafana.this.endpoint
}
