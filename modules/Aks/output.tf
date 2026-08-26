###############################################################
# MODULE: Aks - Outputs
###############################################################

output "id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.this.name
}

output "fqdn" {
  description = "Private FQDN of the cluster"
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "node_resource_group" {
  description = "Node resource group name"
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "kubelet_identity" {
  description = "Cluster kubelet identity"
  value       = azurerm_kubernetes_cluster.this.kubelet_identity
}

output "web_app_routing_identity_principal_id" {
  description = "Principal (object) ID of the auto-created UAMI used by the Application Routing addon. Null when enable_web_app_routing = false."
  value       = try(azurerm_kubernetes_cluster.this.web_app_routing[0].web_app_routing_identity[0].object_id, null)
}

output "web_app_routing_identity_client_id" {
  description = "Client ID of the auto-created UAMI used by the Application Routing addon. Null when enable_web_app_routing = false."
  value       = try(azurerm_kubernetes_cluster.this.web_app_routing[0].web_app_routing_identity[0].client_id, null)
}

output "resource" {
  description = "The complete AKS cluster resource object"
  value       = azurerm_kubernetes_cluster.this
  sensitive   = true
}

output "kube_config_raw" {
  description = "Raw kubeconfig (sensitive)"
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "host" {
  description = "Cluster endpoint (sensitive)"
  value       = azurerm_kubernetes_cluster.this.kube_config[0].host
  sensitive   = true
}

output "lock_id" {
  description = "Management lock ID (null if var.lock is null)"
  value       = try(module.lock.ids["this"], null)
}
