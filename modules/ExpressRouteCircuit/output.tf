###############################################################
# MODULE: ExpressRouteCircuit - Outputs
###############################################################

output "id" {
  description = "The ID of the ExpressRoute circuit"
  value       = azurerm_express_route_circuit.this.id
}

output "name" {
  description = "The name of the ExpressRoute circuit"
  value       = azurerm_express_route_circuit.this.name
}

output "service_key" {
  description = "Service Key (s-tag) — share with the provider to provision the circuit on their side"
  value       = azurerm_express_route_circuit.this.service_key
  sensitive   = true
}

output "service_provider_provisioning_state" {
  description = "Provider-side provisioning state (NotProvisioned / Provisioning / Provisioned)"
  value       = azurerm_express_route_circuit.this.service_provider_provisioning_state
}

output "private_peering_id" {
  description = "ID of the AzurePrivatePeering. Returns empty string when peering is not configured (phase 1) — Terragrunt strips null outputs from dependency objects, so empty string is used as the sentinel."
  value       = var.private_peering != null ? azurerm_express_route_circuit_peering.private[0].id : ""
  sensitive   = true
}

output "microsoft_peering_id" {
  description = "ID of the Microsoft Peering, or empty string when not configured."
  value       = var.microsoft_peering != null ? azurerm_express_route_circuit_peering.microsoft[0].id : ""
  sensitive   = true
}

output "private_peering_azure_ports" {
  description = "MSEE port allocations from Microsoft (primary/secondary). Empty strings until the provider finishes physical port plumbing — useful as a readiness signal."
  sensitive   = true
  value = var.private_peering != null ? {
    primary   = azurerm_express_route_circuit_peering.private[0].primary_azure_port
    secondary = azurerm_express_route_circuit_peering.private[0].secondary_azure_port
  } : null
}

output "resource" {
  description = "The complete ExpressRoute circuit resource object (sensitive because it contains service_key)"
  value       = azurerm_express_route_circuit.this
  sensitive   = true
}
