###############################################################
# MODULE: RouteTable - Outputs
###############################################################

output "id" {
  description = "The route table ID"
  value       = azurerm_route_table.this.id
}

output "name" {
  description = "The route table name"
  value       = azurerm_route_table.this.name
}

output "routes" {
  description = "The route definitions applied to the route table"
  value       = azurerm_route.this
}

output "route_ids" {
  description = "Map of route map key => route resource ID."
  value       = { for k, v in azurerm_route.this : k => v.id }
}

output "resource" {
  description = "The complete route table resource object"
  value       = azurerm_route_table.this
}
