###############################################################
# MODULE: PrivateEndpoint - Outputs
###############################################################

output "resources" {
  description = "Map of endpoint key => complete Private Endpoint resource object"
  value       = azurerm_private_endpoint.this
}

output "ids" {
  description = "Map of endpoint key => Private Endpoint ID"
  value       = { for k, v in azurerm_private_endpoint.this : k => v.id }
}

output "private_ip_addresses" {
  description = "Map of endpoint key => private IP address"
  value = {
    for k, v in azurerm_private_endpoint.this :
    k => try(v.private_service_connection[0].private_ip_address, null)
  }
}
